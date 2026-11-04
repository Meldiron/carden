#!/usr/bin/env python3
"""App Store Connect publisher for Carden.

Idempotent: every subcommand looks up what already exists and creates or
updates only what differs, so it is safe to run again after a partial failure.

    asc_publish.py all --dry-run          # print every request, send nothing
    asc_publish.py status                 # what exists in App Store Connect
    asc_publish.py audit                  # submission checklist, no writes
    asc_publish.py testflight --build 103 # wait for build 103, add to the groups, beta review
    asc_publish.py release --version 1.7.0 --build 103   # prepare the App Store version
    asc_publish.py draft [--events]       # fill the review draft (version, products, events); never submits
    asc_publish.py submit --yes           # create and submit the review submission
    asc_publish.py events [--window 10] [--primary 5]   # In-App Event drafts: the next world-day events and the
                                          # next major holidays after them (never submitted)

Reads metadata from store/metadata (see tools/store/README.md). Credentials:
the team API key secrets/AuthKey_9QC72A5QMN.p8 (override with ASC_KEY_ID and
ASC_KEY_PATH) and the Issuer ID from the environment variable ASC_ISSUER_ID or
secrets/app-store-connect-issuer-id.txt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Callable, Iterable

try:
    import jwt  # pyjwt
    import requests
except ImportError as exc:  # pragma: no cover
    sys.exit(f"missing dependency: {exc}. Install pyjwt, cryptography and requests.")

# ---------------------------------------------------------------------------
# Fixed facts
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[2]
META = ROOT / "store" / "metadata"
EN = META / "en-US"
SUBS_DIR = META / "subscriptions"
SCREENSHOT_DIR = ROOT / "store" / "screenshots" / "iphone-6.9"

APP_ID = "6821644423"
BUNDLE_ID = "com.matejbaco.cardjigsawworld"
KEY_ID = os.environ.get("ASC_KEY_ID", "").strip() or "9QC72A5QMN"
KEY_PATH = Path(os.environ.get("ASC_KEY_PATH", "").strip() or ROOT / "secrets" / f"AuthKey_{KEY_ID}.p8").expanduser()
ISSUER_FILE = ROOT / "secrets" / "app-store-connect-issuer-id.txt"
VERSION_STRING = "2.0.0"  # `release` and `submit` replace this with the version they work on
PUBSPEC = ROOT / "pubspec.yaml"
PLATFORM = "IOS"
LOCALE = "en-US"  # replaced at startup by the app's primaryLocale (en-GB for this app); metadata stays in store/metadata/en-US
BASE_TERRITORY = "USA"
SCREENSHOT_TYPE = "APP_IPHONE_67"
BETA_GROUP_NAME = "Public testers"
# The `api` Appwrite Function (execute `any` since 2026-10-17; docs/functions.md, "Apple's notifications").
# verify-purchase keeps the same code, so retries Apple sent to its old address still apply once.
NOTIFICATIONS_URL = "https://cjw-api.fra.appwrite.run/purchase/notifications"
# READY_FOR_REVIEW: in a review draft that has not been sent; still editable until it is submitted.
EDITABLE_VERSION_STATES = ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
# Review submissions that are still open (not yet sent to Apple, or sent and not finished).
PENDING_SUBMISSION_STATES = ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")
ACTIVE_SUBMISSION_STATES = ("WAITING_FOR_REVIEW", "IN_REVIEW")
BUILD_POLL_SECONDS = 30

API = "https://api.appstoreconnect.apple.com"

# In-App Events (cmd_events): metadata from tools/store/make_app_events.py, media outside git.
APP_EVENTS = META / "app_events.json"
EVENT_MEDIA = Path(os.environ.get("CJW_APP_EVENT_MEDIA", "~/.local/share/card-jigsaw-world/app-events")).expanduser()
EVENT_WINDOW = 10        # Apple publishes at most 10 events at a time (15 approved)
EVENT_PRIMARY = 5        # the other 5 approved slots: the next major holidays after the window
EVENT_LEAD_DAYS = 2      # events starting sooner are left alone (too late for review)
EVENT_EDITABLE_STATES = ("DRAFT", "REJECTED")
# Asset types whose upload commit takes only `uploaded` (Apple rejects sourceFileChecksum on them).
NO_CHECKSUM_ASSETS = ("appEventScreenshots", "appEventVideoClips")

ALL_ORDER = [
    "app-info",
    "version",
    "age-rating",
    "price-free",
    "screenshots",
    "iap",
    "subscriptions",
    "review-info",
    "testflight",
]

# Limits App Store Connect enforces; checked before anything is sent.
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "description": 4000,
    "keywords": 100,
    "release_notes": 4000,
    "iap_name": 30,
    "iap_description": 45,
}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def read_text(name: str, required: bool = True) -> str:
    path = EN / name
    if not path.exists():
        if required:
            sys.exit(f"missing metadata file: {path}")
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_json(path: Path) -> dict:
    if not path.exists():
        sys.exit(f"missing metadata file: {path}")
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    return {k: v for k, v in data.items() if not k.startswith("_")}


def is_placeholder(value: Any) -> bool:
    return not isinstance(value, str) or not value or value.startswith("[")


def check_limit(field: str, value: str) -> None:
    limit = LIMITS.get(field)
    if limit and len(value) > limit:
        sys.exit(f"{field} is {len(value)} characters; App Store Connect allows {limit}")


def md5_of(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def same_price(a: Any, b: Any) -> bool:
    try:
        return abs(float(a) - float(b)) < 0.0005
    except (TypeError, ValueError):
        return False


def log(msg: str) -> None:
    print(msg, flush=True)


def pubspec_version() -> str:
    """The marketing version from pubspec.yaml (`1.7.0+10` -> `1.7.0`)."""
    for line in PUBSPEC.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().split("+", 1)[0]
    sys.exit(f"no `version:` line in {PUBSPEC}")


def read_whats_new(path_arg: str | None) -> str | None:
    """Text for whatsNew: the file given with --whats-new-file, else release_notes.txt.
    An empty file means "do not touch whatsNew" and returns None."""
    if path_arg is None:
        return read_text("release_notes.txt")
    path = Path(path_arg).expanduser()
    if not path.exists():
        sys.exit(f"--whats-new-file: {path} does not exist")
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        log(f"  {path.name} is empty; leaving what's new untouched")
        return None
    check_limit("release_notes", text)
    return text


# ---------------------------------------------------------------------------
# API client
# ---------------------------------------------------------------------------


class ApiError(RuntimeError):
    def __init__(self, status: int, errors: list[dict], method: str, url: str):
        self.status = status
        self.errors = errors
        super().__init__(f"{method} {url} -> {status}: " + "; ".join(
            f"{e.get('code', '')} {e.get('title', '')}: {e.get('detail', '')}" for e in errors) or str(status))

    def mentions(self, *words: str) -> bool:
        text = json.dumps(self.errors).lower()
        return any(w.lower() in text for w in words)

    @property
    def already_exists(self) -> bool:
        return self.status == 409 and self.mentions("already exists", "already been", "duplicate", "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE")


class Client:
    """Thin JSON:API client with JWT auth, pagination and a dry-run mode."""

    def __init__(self, dry_run: bool, verbose: bool):
        self.dry_run = dry_run
        self.verbose = verbose
        self.session = requests.Session()
        self._token: str | None = None
        self._token_exp = 0.0
        self._dry_counter = 0
        self.issuer_id = self._load_issuer()
        if not dry_run and not KEY_PATH.exists():
            sys.exit(f"private key not found: {KEY_PATH}")

    # -- auth ---------------------------------------------------------------

    @staticmethod
    def _load_issuer() -> str:
        issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
        if not issuer and ISSUER_FILE.exists():
            issuer = ISSUER_FILE.read_text(encoding="utf-8").strip()
        if not issuer:
            sys.exit(
                "App Store Connect Issuer ID is missing.\n"
                "Find it in App Store Connect > Users and Access > Integrations > App Store Connect API\n"
                "(\"Issuer ID\" at the top of the page), then either\n"
                "  export ASC_ISSUER_ID=<issuer id>\n"
                f"or write it to {ISSUER_FILE.relative_to(ROOT)}"
            )
        return issuer

    def token(self) -> str:
        now = time.time()
        if self._token and now < self._token_exp - 60:
            return self._token
        if self.dry_run and not KEY_PATH.exists():
            self._token, self._token_exp = "dry-run-token", now + 1200
            return self._token
        key = KEY_PATH.read_text(encoding="utf-8")
        payload = {"iss": self.issuer_id, "iat": int(now), "exp": int(now) + 19 * 60, "aud": "appstoreconnect-v1"}
        self._token = jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
        self._token_exp = now + 19 * 60
        return self._token

    # -- core request -------------------------------------------------------

    def request(self, method: str, path: str, body: dict | None = None, params: dict | None = None,
                raw: bytes | None = None, headers: dict | None = None, allow_404: bool = False) -> dict | None:
        url = path if path.startswith("http") else API + path
        if self.dry_run and method != "GET":
            self._dry_counter += 1
            log(f"[dry-run] {method} {url}" + (f" params={json.dumps(params)}" if params else ""))
            if body is not None:
                log("          " + json.dumps(body, indent=2).replace("\n", "\n          "))
            if raw is not None:
                log(f"          <{len(raw)} bytes>")
            return self._dry_response(method, path, body)
        if self.dry_run and method == "GET":
            if self.verbose:
                log(f"[dry-run] GET {url}" + (f" params={json.dumps(params)}" if params else ""))
            return self._dry_get(path, params)

        # Asset upload operations go to presigned object-storage URLs, which
        # reject requests that also carry an Authorization header.
        hdrs = {} if (path.startswith("http") and not path.startswith(API)) else {"Authorization": f"Bearer {self.token()}"}
        if headers:
            hdrs.update(headers)
        if self.verbose:
            log(f"{method} {url}" + (f" params={json.dumps(params)}" if params else ""))
            if body is not None:
                log("  " + json.dumps(body))
        for attempt in range(5):
            resp = self.session.request(method, url, json=body, params=params, data=raw, headers=hdrs, timeout=120)
            if resp.status_code == 429 or resp.status_code >= 500:
                wait = 2 ** attempt
                log(f"  {resp.status_code} from Apple, retrying in {wait}s")
                time.sleep(wait)
                continue
            break
        if resp.status_code == 404 and allow_404:
            return None
        if resp.status_code >= 400:
            try:
                errors = resp.json().get("errors", [])
            except ValueError:
                errors = [{"title": resp.text[:300]}]
            raise ApiError(resp.status_code, errors, method, url)
        if resp.status_code == 204 or not resp.content:
            return {}
        return resp.json()

    # -- dry-run stand-ins --------------------------------------------------

    def _dry_response(self, method: str, path: str, body: dict | None) -> dict:
        if body and isinstance(body.get("data"), dict):
            data = dict(body["data"])
            data.setdefault("id", f"DRY-{data.get('type', 'resource')}-{self._dry_counter}")
            return {"data": data}
        return {"data": None}

    def _dry_get(self, path: str, params: dict | None) -> dict:
        """Synthetic empty answers so every flow takes its 'create' branch and
        the printed requests show the full shape. Territories and
        equalizations return a short list so per-territory requests show up."""
        p = path.split("?")[0]
        if p.endswith("/territories"):
            return self._dry_list([self._territory(t) for t in ("USA", "GBR", "DEU")])
        if p.endswith("/equalizations"):
            return self._dry_list([
                {"id": f"DRY-pricePoint-{t}", "type": "pricePoints", "attributes": {"customerPrice": "?"},
                 "relationships": {"territory": {"data": {"type": "territories", "id": t}}}}
                for t in ("GBR", "DEU")
            ])
        if p.endswith("/appCategories"):
            return self._dry_list([])
        if p.endswith("/v1/builds"):
            number = (params or {}).get("filter[version]", "0")
            return self._dry_list([{"id": f"DRY-build-{number}", "type": "builds",
                                    "attributes": {"version": str(number), "processingState": "VALID", "uploadedDate": "dry-run",
                                                   "usesNonExemptEncryption": None}}])
        if p.endswith("/appStoreVersions"):
            return self._dry_list([])
        # Single resources answered by to-one relationship endpoints.
        single = ("ageRatingDeclaration", "appStoreReviewDetail", "appPriceSchedule", "appAvailabilityV2",
                  "iapPriceSchedule", "inAppPurchaseAvailability", "appStoreReviewScreenshot",
                  "subscriptionAvailability", "betaAppReviewDetail", "betaLicenseAgreement")
        if p.rsplit("/", 1)[-1] in single:
            return {"data": None}
        return self._dry_list([])

    @staticmethod
    def _territory(code: str) -> dict:
        return {"id": code, "type": "territories", "attributes": {"currency": "USD"}}

    @staticmethod
    def _dry_list(items: list) -> dict:
        return {"data": items, "links": {}}

    # -- convenience --------------------------------------------------------

    def get_list(self, path: str, params: dict | None = None, limit: int = 200) -> list[dict]:
        """GET a collection, following `links.next` until exhausted."""
        params = dict(params or {})
        params.setdefault("limit", limit)
        out: list[dict] = []
        resp = self.request("GET", path, params=params)
        while resp is not None:
            out.extend(resp.get("data") or [])
            nxt = (resp.get("links") or {}).get("next")
            if not nxt:
                break
            resp = self.request("GET", nxt)
        return out

    def get_one(self, path: str, params: dict | None = None) -> dict | None:
        resp = self.request("GET", path, params=params, allow_404=True)
        if not resp:
            return None
        data = resp.get("data")
        return data if isinstance(data, dict) else None

    def create(self, type_: str, attributes: dict | None = None, relationships: dict | None = None,
               included: list | None = None, path: str | None = None) -> dict:
        data: dict[str, Any] = {"type": type_}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        body: dict[str, Any] = {"data": data}
        if included:
            body["included"] = included
        resp = self.request("POST", path or f"/v1/{type_}", body)
        return (resp or {}).get("data") or {}

    def update(self, type_: str, id_: str, attributes: dict | None = None, relationships: dict | None = None,
               path: str | None = None) -> dict:
        data: dict[str, Any] = {"type": type_, "id": id_}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        resp = self.request("PATCH", path or f"/v1/{type_}/{id_}", {"data": data})
        return (resp or {}).get("data") or {}

    def upsert(self, type_: str, existing: dict | None, attributes: dict, relationships: dict | None = None,
               create_path: str | None = None, patch_path: str | None = None, label: str = "",
               refetch: Callable[[], dict | None] | None = None) -> dict:
        """Create when `existing` is None, else PATCH only the attributes that differ.
        A 409 'already exists' on create is retried as a PATCH after `refetch`
        (or a GET of the create path) finds the resource."""
        label = label or type_
        if existing:
            current = existing.get("attributes") or {}
            diff = {k: v for k, v in attributes.items() if current.get(k) != v}
            if not diff:
                log(f"  {label}: up to date")
                return existing
            log(f"  {label}: updating {', '.join(sorted(diff))}")
            return self.update(type_, existing["id"], diff, path=patch_path)
        log(f"  {label}: creating")
        try:
            return self.create(type_, attributes, relationships, path=create_path)
        except ApiError as err:
            if not err.already_exists or refetch is None:
                raise
            log(f"  {label}: Apple says it already exists (409); refetching and updating instead")
            found = refetch()
            if found is None:
                raise
            attrs = {k: v for k, v in attributes.items() if k != "locale"}
            return self.upsert(type_, found, attrs, patch_path=patch_path, label=label)


# ---------------------------------------------------------------------------
# Shared lookups
# ---------------------------------------------------------------------------


def localized(cfg: dict) -> dict:
    """The localization block for the app's primary locale, falling back to en-US text."""
    locs = cfg["localizations"]
    return locs.get(LOCALE) or locs["en-US"]


def rel(type_: str, id_: str) -> dict:
    return {"data": {"type": type_, "id": id_}}


def rel_many(type_: str, ids: Iterable[str]) -> dict:
    return {"data": [{"type": type_, "id": i} for i in ids]}


def attr(res: dict | None, key: str, default: Any = None) -> Any:
    return ((res or {}).get("attributes") or {}).get(key, default)


def territory_of(res: dict) -> str | None:
    return (((res.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")


def related_id(res: dict | None, name: str) -> str | None:
    """Id of a to-one relationship when the response carries it inline."""
    return ((((res or {}).get("relationships") or {}).get(name) or {}).get("data") or {}).get("id")


def version_state(version: dict | None) -> str | None:
    return attr(version, "appVersionState") or attr(version, "appStoreState")


class Store:
    """Everything the subcommands share: client, cached lookups and metadata."""

    def __init__(self, client: Client, opts: argparse.Namespace | None = None):
        self.c = client
        self.opts = opts or argparse.Namespace()
        self._cache: dict[str, Any] = {}

    def opt(self, name: str, default: Any = None) -> Any:
        return getattr(self.opts, name, default)

    def cached(self, key: str, fn: Callable[[], Any]) -> Any:
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    # -- app level ----------------------------------------------------------

    def app(self) -> dict | None:
        return self.cached("app", lambda: self.c.get_one(f"/v1/apps/{APP_ID}"))

    def app_info(self) -> dict:
        def find() -> dict:
            infos = self.c.get_list(f"/v1/apps/{APP_ID}/appInfos")
            editable = [i for i in infos if attr(i, "state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "WAITING_FOR_REVIEW", "READY_FOR_REVIEW")]
            chosen = (editable or infos or [None])[-1]
            if chosen is None:
                if self.c.dry_run:
                    return {"id": "DRY-appInfo", "type": "appInfos", "attributes": {}}
                sys.exit("the app has no appInfos record; create the app in App Store Connect first")
            return chosen
        return self.cached("appInfo", find)

    def territories(self) -> list[str]:
        return self.cached("territories", lambda: [t["id"] for t in self.c.get_list("/v1/territories")])

    def version(self, create: bool = False) -> dict | None:
        def find() -> dict | None:
            found = self.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions",
                                    {"filter[versionString]": VERSION_STRING, "filter[platform]": PLATFORM})
            return found[0] if found else None
        version = self.cached("version", find)
        if version is None and create:
            # Only one editable version can exist per platform. If there is one
            # (for example the "1.0" App Store Connect creates with the app, or
            # a rejected version), rename it; when the newest version is past
            # editing (in review, approved, live) a new version is created.
            old = self.editable_version()
            if old:
                log(f"  appStoreVersion {attr(old, 'versionString')} ({version_state(old)}): renaming to {VERSION_STRING}")
                version = self.c.update("appStoreVersions", old["id"], {"versionString": VERSION_STRING})
                if not version.get("attributes"):
                    version = {**old, "attributes": {**(old.get("attributes") or {}), "versionString": VERSION_STRING}}
            else:
                newest = self.all_versions()[-1] if self.all_versions() else None
                if newest:
                    log(f"  newest appStoreVersion {attr(newest, 'versionString')} is {version_state(newest)}, not editable")
                log(f"  appStoreVersion {VERSION_STRING}: creating")
                version = self.c.create("appStoreVersions",
                                        {"platform": PLATFORM, "versionString": VERSION_STRING, "copyright": read_text("copyright.txt")},
                                        {"app": rel("apps", APP_ID)})
            self._cache["version"] = version
            self._cache.pop("versions", None)
        return version

    def version_localization(self, version: dict, create: bool = False) -> dict | None:
        key = f"vloc-{version['id']}"
        def find() -> dict | None:
            found = self.c.get_list(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", {"filter[locale]": LOCALE})
            return found[0] if found else None
        loc = self.cached(key, find)
        if loc is None and create:
            log(f"  appStoreVersionLocalization {LOCALE}: creating")
            loc = self.c.create("appStoreVersionLocalizations", {"locale": LOCALE}, {"appStoreVersion": rel("appStoreVersions", version["id"])})
            self._cache[key] = loc
        return loc

    def all_versions(self) -> list[dict]:
        return self.cached("versions", lambda: self.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": PLATFORM}))

    def editable_version(self) -> dict | None:
        """The one appStoreVersion per platform that can still be changed, if any."""
        return next((v for v in self.all_versions() if version_state(v) in EDITABLE_VERSION_STATES), None)

    def latest_build(self) -> dict | None:
        def find() -> dict | None:
            builds = self.c.get_list("/v1/builds", {"filter[app]": APP_ID, "sort": "-uploadedDate", "limit": 5}, limit=5)
            return builds[0] if builds else None
        return self.cached("build", find)

    def build_by_number(self, number: str) -> dict | None:
        builds = self.c.get_list("/v1/builds", {"filter[app]": APP_ID, "filter[version]": number, "sort": "-uploadedDate", "limit": 5}, limit=5)
        return builds[0] if builds else None

    def latest_valid_build(self, marketing_version: str | None = None) -> dict | None:
        """Newest processed build; with `marketing_version`, only builds of that
        pre-release version (falls back to the newest valid build of any version)."""
        params = {"filter[app]": APP_ID, "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 5}
        if marketing_version:
            builds = self.c.get_list("/v1/builds", {**params, "filter[preReleaseVersion.version]": marketing_version}, limit=5)
            if builds:
                return builds[0]
            log(f"  no processed build of version {marketing_version}; using the newest processed build instead")
        builds = self.c.get_list("/v1/builds", params, limit=5)
        return builds[0] if builds else None

    def wait_for_build(self, number: str, timeout_minutes: float) -> dict:
        """Poll until build `number` exists and is processed (VALID). Exits on
        INVALID / FAILED or when the timeout passes."""
        deadline = time.time() + timeout_minutes * 60
        last_state = None
        while True:
            build = self.build_by_number(number)
            state = attr(build, "processingState") if build else None
            if state != last_state:
                log(f"  build {number}: {state or 'not visible yet'}")
                last_state = state
            if state == "VALID":
                self._cache["build"] = build
                return build
            if state in ("INVALID", "FAILED"):
                sys.exit(f"build {number} finished processing as {state}; check the email from App Store Connect for the reason")
            if self.c.dry_run:
                return build or {"id": f"DRY-build-{number}", "type": "builds", "attributes": {"version": number, "processingState": "VALID"}}
            if time.time() >= deadline:
                sys.exit(f"build {number} did not reach VALID within {timeout_minutes:g} minutes (last state: {state or 'not visible'})")
            time.sleep(BUILD_POLL_SECONDS)

    # -- uploads ------------------------------------------------------------

    def drop_if_changed(self, type_: str, asset: dict | None, path: Path) -> dict | None:
        """A one-per-parent asset (a review screenshot) whose file changed since it was uploaded is
        deleted, so `upload_asset` puts the new file up; returns the asset to keep, or None."""
        if asset is None or not path.exists():
            return asset
        checksum = attr(asset, "sourceFileChecksum")
        if checksum and checksum != md5_of(path):
            log(f"  {type_}: {path.name} changed, replacing")
            self.c.request("DELETE", f"/v1/{type_}/{asset['id']}")
            return None
        return asset

    def upload_asset(self, type_: str, parent_rel: dict, path: Path, existing: list[dict] | None = None,
                     patch_path: str | None = None, extra: dict | None = None) -> dict | None:
        """Reserve, upload, commit. Returns None when an asset with the same file
        name is already there (idempotent by file name)."""
        if not path.exists():
            shown = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
            log(f"  {type_}: {shown} not found, skipping")
            return None
        for res in existing or []:
            if attr(res, "fileName") == path.name:
                state = ((attr(res, "assetDeliveryState") or {}).get("state")) or "present"
                if state in ("AWAITING_UPLOAD", "FAILED"):
                    # A reservation from an interrupted upload; drop it and start over.
                    log(f"  {type_}: {path.name} stale ({state}), deleting and re-uploading")
                    self.c.request("DELETE", f"/v1/{type_}/{res['id']}")
                    continue
                log(f"  {type_}: {path.name} already uploaded ({state})")
                return res
        size = path.stat().st_size
        log(f"  {type_}: uploading {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path.name} ({size} bytes)")
        try:
            reserved = self.c.create(type_, {"fileName": path.name, "fileSize": size, **(extra or {})}, parent_rel)
        except ApiError as e:
            if e.status == 409:
                # Apple keeps one asset of this kind; it is already there (possibly still processing).
                log(f"  {type_}: already present on Apple's side, keeping it")
                return None
            raise
        ops = attr(reserved, "uploadOperations") or []
        data = path.read_bytes()
        if not ops and self.c.dry_run:
            ops = [{"method": "PUT", "url": f"https://upload.example/{type_}/{path.name}", "offset": 0, "length": size, "requestHeaders": []}]
        for op in ops:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            self.c.request(op.get("method", "PUT"), op["url"], raw=chunk, headers=headers)
        commit = {"uploaded": True}
        if type_ not in NO_CHECKSUM_ASSETS:
            commit["sourceFileChecksum"] = md5_of(path)
        return self.c.update(type_, reserved["id"], commit, path=patch_path)

    def describe_price_schedule(self, schedule: dict) -> str:
        resp = self.c.request("GET", f"/v1/appPriceSchedules/{schedule['id']}/manualPrices",
                              params={"include": "appPricePoint,territory", "limit": 200}, allow_404=True) or {}
        points = {i["id"]: attr(i, "customerPrice") for i in resp.get("included") or [] if i.get("type") == "appPricePoints"}
        parts = []
        for price in resp.get("data") or []:
            pp = (((price.get("relationships") or {}).get("appPricePoint") or {}).get("data") or {}).get("id")
            parts.append(f"{territory_of(price)}={points.get(pp, '?')}")
        return ", ".join(parts) or "no manual prices"

    # -- prices -------------------------------------------------------------

    def price_point(self, list_path: str, price: str, label: str) -> dict:
        points = self.c.get_list(list_path, {"filter[territory]": BASE_TERRITORY, "include": "territory"})
        for p in points:
            if same_price(attr(p, "customerPrice"), price):
                return p
        if self.c.dry_run:
            return {"id": f"DRY-pricePoint-USD-{price}", "type": "pricePoints", "attributes": {"customerPrice": price}}
        offered = sorted({attr(p, "customerPrice") for p in points}, key=float)
        sys.exit(f"{label}: no {BASE_TERRITORY} price point for {price}. Available: {', '.join(offered)}")

    def equalized(self, eq_path: str, base_point: dict, extra_params: dict | None = None) -> dict[str, str]:
        """territory code -> price point id, including the base territory."""
        out = {BASE_TERRITORY: base_point["id"]}
        params = {"include": "territory"}
        params.update(extra_params or {})
        for p in self.c.get_list(eq_path, params):
            t = territory_of(p)
            if t:
                out.setdefault(t, p["id"])
        return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_app_info(s: Store) -> None:
    log("== app-info")
    app = s.app() or {"id": APP_ID, "attributes": {}}
    app_attrs = {
        "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT",  # licensed photos and museum images
        "subscriptionStatusUrl": NOTIFICATIONS_URL,
        "subscriptionStatusUrlVersion": "V2",
        "subscriptionStatusUrlForSandbox": NOTIFICATIONS_URL,
        "subscriptionStatusUrlVersionForSandbox": "V2",
    }
    # Apple wants each notification URL together with its version, so a changed URL sends all four.
    current = app.get("attributes") or {}
    if app.get("id") and any(current.get(k) != v for k, v in app_attrs.items() if k.startswith("subscriptionStatus")):
        diff = {k: v for k, v in app_attrs.items() if k.startswith("subscriptionStatus") or current.get(k) != v}
        log(f"  app (content rights, App Store Server Notification URLs): updating {', '.join(sorted(diff))}")
        s.c.update("apps", app["id"], diff)
    else:
        s.c.upsert("apps", app, app_attrs, label="app (content rights, App Store Server Notification URLs)")
    info = s.app_info()
    cats = read_json(EN / "categories.json")
    rels = {k: rel("appCategories", v) for k, v in cats.items() if v}
    current = info.get("relationships") or {}
    changed = {k: v for k, v in rels.items() if ((current.get(k) or {}).get("data") or {}).get("id") != v["data"]["id"]}
    if changed or s.c.dry_run or not current:
        log(f"  appInfo {info['id']}: setting categories {', '.join(f'{k}={v}' for k, v in cats.items())}")
        s.c.update("appInfos", info["id"], relationships=rels)
    else:
        log("  categories: up to date")

    name, subtitle = read_text("name.txt"), read_text("subtitle.txt")
    check_limit("name", name)
    check_limit("subtitle", subtitle)
    attrs = {"name": name, "subtitle": subtitle, "privacyPolicyUrl": read_text("privacy_url.txt")}
    locs = s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"filter[locale]": LOCALE})
    s.c.upsert("appInfoLocalizations", locs[0] if locs else None, {**attrs, "locale": LOCALE} if not locs else attrs,
               {"appInfo": rel("appInfos", info["id"])}, label=f"appInfoLocalization {LOCALE}",
               refetch=lambda: next(iter(s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"filter[locale]": LOCALE})), None))


def version_localization_attrs() -> dict:
    fields = {
        "description": read_text("description.txt"),
        "keywords": read_text("keywords.txt"),
        "promotionalText": read_text("promotional_text.txt"),
        "supportUrl": read_text("support_url.txt"),
        "marketingUrl": read_text("marketing_url.txt"),
        "whatsNew": read_text("release_notes.txt"),
    }
    check_limit("description", fields["description"])
    check_limit("keywords", fields["keywords"])
    check_limit("promotional_text", fields["promotionalText"])
    check_limit("release_notes", fields["whatsNew"])
    name_words = {w.lower() for w in re.findall(r"[a-z]+", read_text("name.txt"), re.I)}
    clash = [k for k in fields["keywords"].split(",") if k.lower() in name_words]
    if clash:
        sys.exit(f"keywords repeat words from the app name: {', '.join(clash)}")
    if ", " in fields["keywords"]:
        sys.exit("keywords.txt: remove the space after commas")
    return fields


def sync_version_metadata(s: Store, whats_new: str | None = None, only_whats_new: bool = False) -> tuple[dict, str]:
    """Copyright and the primary-locale localization of the current version.

    `whats_new` replaces release_notes.txt; None leaves whatsNew alone. With
    `only_whats_new` an existing localization gets just whatsNew (a brand new
    one is still filled completely, since Apple requires description and
    keywords before the version can be submitted). Returns the version and a
    word describing what happened to whatsNew (updated / untouched / rejected)."""
    whats_new_result = "updated"
    version = s.version(create=True)
    assert version
    copyright_ = read_text("copyright.txt")
    if attr(version, "copyright") != copyright_:
        log(f"  appStoreVersion {version['id']}: setting copyright")
        s.c.update("appStoreVersions", version["id"], {"copyright": copyright_})
    else:
        log("  copyright: up to date")
    existed = s.version_localization(version) is not None
    loc = s.version_localization(version, create=True)
    assert loc
    fields = version_localization_attrs()
    if whats_new is not None:
        fields["whatsNew"] = whats_new
    if only_whats_new and existed:
        fields = {"whatsNew": fields["whatsNew"]} if whats_new is not None else {}
    elif whats_new is None and only_whats_new:
        fields.pop("whatsNew")
    if "whatsNew" not in fields:
        whats_new_result = "untouched"
    if not fields:
        log(f"  appStoreVersionLocalization {LOCALE}: nothing to change")
        return version, whats_new_result
    try:
        s.c.upsert("appStoreVersionLocalizations", loc, fields, label=f"appStoreVersionLocalization {LOCALE}")
    except ApiError as err:
        if err.mentions("whatsNew", "what's new") and "whatsNew" in fields:
            log("  Apple rejected whatsNew (first version of the app); retrying without it")
            fields.pop("whatsNew")
            whats_new_result = "rejected by Apple (first version has no what's new)"
            if fields:
                s.c.upsert("appStoreVersionLocalizations", loc, fields, label=f"appStoreVersionLocalization {LOCALE}")
        else:
            raise
    return version, whats_new_result


def cmd_version(s: Store) -> None:
    log("== version")
    sync_version_metadata(s)


def cmd_age_rating(s: Store) -> None:
    log("== age-rating")
    info = s.app_info()
    decl = s.c.get_one(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    wanted = read_json(EN / "age_rating.json")
    if decl is None:
        if not s.c.dry_run:
            sys.exit("no ageRatingDeclaration on the appInfo; open the app in App Store Connect once so it is created")
        decl = {"id": "DRY-ageRatingDeclaration", "attributes": {}}
    s.c.upsert("ageRatingDeclarations", decl, wanted, label="ageRatingDeclaration")


def cmd_price_free(s: Store) -> None:
    log("== price-free")
    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    described = s.describe_price_schedule(schedule) if schedule and not s.c.dry_run else ""
    if schedule and described and described != "no manual prices":
        log(f"  appPriceSchedule exists: {described}; leaving it (change it in App Store Connect > Pricing to reset)")
    else:
        # App Store Connect creates an empty placeholder schedule (no manual prices) with the app record.
        point = s.price_point(f"/v1/apps/{APP_ID}/appPricePoints", "0", "app price")
        log(f"  appPriceSchedule: creating, free in {BASE_TERRITORY} (price point {point['id']}), other territories equalised by Apple")
        s.c.create(
            "appPriceSchedules",
            relationships={
                "app": rel("apps", APP_ID),
                "baseTerritory": rel("territories", BASE_TERRITORY),
                "manualPrices": rel_many("appPrices", ["${price-free}"]),
            },
            included=[{
                "type": "appPrices",
                "id": "${price-free}",
                "attributes": {"startDate": None},
                "relationships": {"appPricePoint": rel("appPricePoints", point["id"])},
            }],
        )

    territories = s.territories()
    availability = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    have = set()
    if availability:
        have = {territory_of(t) for t in s.c.get_list(f"/v2/appAvailabilities/{availability['id']}/territoryAvailabilities", {"include": "territory"})
                if attr(t, "available")}
    missing = [t for t in territories if t not in have]
    if availability and not missing and attr(availability, "availableInNewTerritories"):
        log(f"  availability: all {len(territories)} territories, up to date")
        return
    log(f"  appAvailabilityV2: creating with {len(territories)} territories ({len(missing)} newly available)")
    s.c.create(
        "appAvailabilities",
        {"availableInNewTerritories": True},
        {"app": rel("apps", APP_ID), "territoryAvailabilities": rel_many("territoryAvailabilities", [f"${{{t}}}" for t in territories])},
        included=[{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                   "relationships": {"territory": rel("territories", t)}} for t in territories],
        path="/v2/appAvailabilities",
    )


def cmd_screenshots(s: Store) -> None:
    log("== screenshots")
    files = sorted(SCREENSHOT_DIR.glob("*.png"))
    if not files:
        log(f"  no PNGs in {SCREENSHOT_DIR.relative_to(ROOT)}; run tools/store/compose_glass.py first")
        return
    version = s.version(create=True)
    loc = s.version_localization(version, create=True)
    sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets", {"filter[screenshotDisplayType]": SCREENSHOT_TYPE})
    if sets:
        sset = sets[0]
        log(f"  appScreenshotSet {SCREENSHOT_TYPE}: exists")
    else:
        log(f"  appScreenshotSet {SCREENSHOT_TYPE}: creating")
        sset = s.c.create("appScreenshotSets", {"screenshotDisplayType": SCREENSHOT_TYPE},
                          {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", loc["id"])})
    existing = s.c.get_list(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
    # The folder is the source of truth: a screenshot whose file changed is replaced, and one
    # with no file of its name (an older, longer set) is removed.
    local = {p.name: p for p in files}
    kept = []
    for res in existing:
        name = attr(res, "fileName")
        png = local.get(name)
        checksum = attr(res, "sourceFileChecksum")
        if png is None:
            log(f"  appScreenshots: {name} is not in {SCREENSHOT_DIR.relative_to(ROOT)}, deleting")
            s.c.request("DELETE", f"/v1/appScreenshots/{res['id']}")
        elif checksum and checksum != md5_of(png):
            log(f"  appScreenshots: {name} changed, replacing")
            s.c.request("DELETE", f"/v1/appScreenshots/{res['id']}")
        else:
            kept.append(res)
    existing = kept
    uploaded: list[str] = []
    for png in files:
        res = s.upload_asset("appScreenshots", {"appScreenshotSet": rel("appScreenshotSets", sset["id"])}, png, existing)
        if res:
            uploaded.append(res["id"])
    # Keep the App Store order equal to the file order.
    current_order = [e["id"] for e in existing]
    if uploaded and uploaded != current_order:
        log("  appScreenshotSet: setting order")
        s.c.request("PATCH", f"/v1/appScreenshotSets/{sset['id']}/relationships/appScreenshots", rel_many("appScreenshots", uploaded))


def cmd_iap(s: Store) -> None:
    log("== iap")
    cfg = read_json(SUBS_DIR / "consumables.json")
    existing = {attr(p, "productId"): p for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2")}
    for product in cfg["products"]:
        pid = product["productId"]
        check_limit("iap_name", product["name"])
        check_limit("iap_description", product["description"])
        iap = existing.get(pid)
        attrs = {"name": product["referenceName"], "reviewNote": product["reviewNote"]}
        if iap is None:
            log(f"  {pid}: creating consumable")
            iap = s.c.create("inAppPurchases", {**attrs, "productId": pid, "inAppPurchaseType": "CONSUMABLE"},
                             {"app": rel("apps", APP_ID)}, path="/v2/inAppPurchases")
        else:
            s.c.upsert("inAppPurchases", iap, attrs, patch_path=f"/v2/inAppPurchases/{iap['id']}", label=f"{pid} ({attr(iap, 'state')})")
        iid = iap["id"]

        locs = s.c.get_list(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")
        loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
        loc_attrs = {"name": product["name"], "description": product["description"]}
        s.c.upsert("inAppPurchaseLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
                   {"inAppPurchaseV2": rel("inAppPurchases", iid)}, label=f"  {pid} localization {LOCALE}",
                   refetch=lambda: next((l for l in s.c.get_list(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations") if attr(l, "locale") == LOCALE), None))

        schedule = s.c.get_one(f"/v2/inAppPurchases/{iid}/iapPriceSchedule")
        if schedule:
            log(f"    {pid} price schedule: exists (delete it in App Store Connect to re-price)")
        else:
            point = s.price_point(f"/v2/inAppPurchases/{iid}/pricePoints", product["customerPrice"], pid)
            by_territory = s.equalized(f"/v1/inAppPurchasePricePoints/{point['id']}/equalizations", point, {"filter[inAppPurchaseV2]": iid})
            log(f"    {pid} price schedule: creating, USD {product['customerPrice']} equalised to {len(by_territory)} territories")
            s.c.create(
                "inAppPurchasePriceSchedules",
                relationships={
                    "inAppPurchase": rel("inAppPurchases", iid),
                    "baseTerritory": rel("territories", BASE_TERRITORY),
                    "manualPrices": rel_many("inAppPurchasePrices", [f"${{{t}}}" for t in by_territory]),
                },
                included=[{"type": "inAppPurchasePrices", "id": f"${{{t}}}", "attributes": {"startDate": None},
                           "relationships": {"inAppPurchasePricePoint": rel("inAppPurchasePricePoints", pp),
                                             "inAppPurchaseV2": rel("inAppPurchases", iid)}}
                          for t, pp in by_territory.items()],
            )

        avail = s.c.get_one(f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability")
        if avail:
            log(f"    {pid} availability: exists")
        else:
            territories = s.territories()
            log(f"    {pid} availability: creating for {len(territories)} territories")
            s.c.create("inAppPurchaseAvailabilities", {"availableInNewTerritories": True},
                       {"inAppPurchase": rel("inAppPurchases", iid), "availableTerritories": rel_many("territories", territories)})

        # The App Review screenshot: the product's own ("reviewScreenshot" on the product: the store
        # scrolled to its section), else the file's default (the top of the store).
        review = product.get("reviewScreenshot") or cfg.get("reviewScreenshot")
        review_png = ROOT / review if review else None
        if review_png:
            shot = s.c.get_one(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot")
            shot = s.drop_if_changed("inAppPurchaseAppStoreReviewScreenshots", shot, review_png)
            s.upload_asset("inAppPurchaseAppStoreReviewScreenshots", {"inAppPurchaseV2": rel("inAppPurchases", iid)}, review_png,
                           [shot] if shot else [])


def patch_outside_review_draft(s: Store, sub: dict, attrs: dict, label: str) -> dict:
    """PATCH a subscription that sits in the app's open review draft. Apple refuses some fields
    (familySharable, 2026-10-14) while the subscription's version is an item of a review submission
    that has not been sent: lift that item out, PATCH, put it back. The draft is never submitted.
    Apple sometimes refuses the first try right after another subscription of the group changed;
    it accepts a second one a few seconds later."""
    current = sub.get("attributes") or {}
    diff = {k: v for k, v in attrs.items() if current.get(k) != v}
    versions = {v["id"] for v in s.c.get_list(f"/v1/subscriptions/{sub['id']}/versions")}
    drafts = [x for x in s.c.get_list(f"/v1/apps/{APP_ID}/reviewSubmissions", {"filter[platform]": PLATFORM})
              if attr(x, "state") in PENDING_SUBMISSION_STATES]
    for attempt in range(2):
        moved: list[tuple[str, str]] = []
        try:
            for draft in drafts:
                resp = s.c.request("GET", f"/v1/reviewSubmissions/{draft['id']}/items",
                                   params={"limit": 50, "include": "subscriptionVersion"}) or {}
                for item in resp.get("data") or []:
                    vid = related_id(item, "subscriptionVersion")
                    if vid in versions:
                        s.c.request("DELETE", f"/v1/reviewSubmissionItems/{item['id']}")
                        moved.append((draft["id"], vid))
            log(f"    {label}: lifted {len(moved)} item(s) out of the review draft, updating {', '.join(sorted(diff))}")
            return s.c.update("subscriptions", sub["id"], diff)
        except ApiError as err:
            if attempt == 1 or err.status != 409:
                raise
            log(f"    {label}: Apple refused ({err.status}); retrying in 20 s")
        finally:
            for draft_id, vid in moved:
                s.c.create("reviewSubmissionItems", relationships={
                    "reviewSubmission": rel("reviewSubmissions", draft_id),
                    "subscriptionVersion": rel("subscriptionVersions", vid)})
            if moved:
                log(f"    {label}: put {len(moved)} item(s) back into the review draft")
        if not s.c.dry_run:
            time.sleep(20)
    return sub


WINBACK_ATTRS = ("referenceName", "offerMode", "duration", "periodCount", "customerEligibilityPaidSubscriptionDurationInMonths",
                 "customerEligibilityTimeSinceLastSubscribedInMonths", "customerEligibilityWaitBetweenOffersInMonths",
                 "priority", "promotionIntent", "endDate")
# Subscription states that accept offers (Apple: "Offers can only be created for approved subscriptions").
WINBACK_STATES = ("APPROVED",)
WINBACK_EDITABLE = ("customerEligibilityPaidSubscriptionDurationInMonths", "customerEligibilityTimeSinceLastSubscribedInMonths",
                    "customerEligibilityWaitBetweenOffersInMonths", "priority", "promotionIntent", "endDate")


def sync_winback_offers(s: Store, sid: str, pid: str, cfg: dict) -> None:
    """Win-back offers (`winBackOffers` in the subscription's metadata): StoreKit offers for people whose
    subscription lapsed. The App Store shows them itself (subscription settings, the product page, and in
    the app through StoreKit messages). Created once per `offerId`, priced per territory from the USD price
    point like the subscription; afterwards only the eligibility, priority, promotion and end date can change."""
    offers = cfg.get("winBackOffers") or []
    if not offers:
        return
    state = attr(s.c.get_one(f"/v1/subscriptions/{sid}"), "state")
    if state not in WINBACK_STATES and not s.c.dry_run:
        log(f"    win-back offers: waiting, the subscription is {state} (Apple creates offers only for approved"
            f" subscriptions; run `subscriptions` again after approval)")
        return
    existing = {attr(o, "offerId"): o for o in s.c.get_list(f"/v1/subscriptions/{sid}/winBackOffers")}
    for o in offers:
        oid = o["offerId"]
        attrs = {k: o[k] for k in WINBACK_ATTRS if k in o}
        if oid in existing:
            s.c.upsert("winBackOffers", existing[oid], {k: v for k, v in attrs.items() if k in WINBACK_EDITABLE},
                       label=f"    win-back {oid}")
            continue
        # Apple wants a start date after today (its own clock); tomorrow is always accepted.
        attrs.update({"offerId": oid, "startDate": o.get("startDate") or time.strftime("%Y-%m-%d", time.gmtime(time.time() + 36 * 3600))})
        included, refs = [], []
        if o["offerMode"] != "FREE_TRIAL":
            point = s.price_point(f"/v1/subscriptions/{sid}/pricePoints", o["price"]["customerPrice"], f"{pid} win-back")
            by_territory = s.equalized(f"/v1/subscriptionPricePoints/{point['id']}/equalizations", point, {"filter[subscription]": sid})
            for i, (t, pp) in enumerate(sorted(by_territory.items())):
                local = f"${{price-{i}}}"
                refs.append({"type": "winBackOfferPrices", "id": local})
                included.append({"type": "winBackOfferPrices", "id": local,
                                 "relationships": {"territory": rel("territories", t),
                                                   "subscriptionPricePoint": rel("subscriptionPricePoints", pp)}})
        log(f"    win-back {oid}: creating ({o['offerMode']} {o['duration']} x{o['periodCount']}"
            + (f", USD {o['price']['customerPrice']} in {len(refs)} territories" if refs else "") + ")")
        s.c.create("winBackOffers", attrs, {"subscription": rel("subscriptions", sid), "prices": {"data": refs}}, included=included)


SUBSCRIPTION_FILES = ("vip_monthly.json", "vip_yearly.json")


def check_promotional_images() -> None:
    """Each plan needs its own promotional image: App Review rejected 2.0.0 (Guideline 2.3.2, 2026-11-04)
    for one image shared by both plans, small text and a price reference. Refuses a missing file, two plans
    naming the same file, or two files with the same content (test/store_promo_test.dart checks the same)."""
    seen: dict[str, str] = {}
    for name in SUBSCRIPTION_FILES:
        cfg = read_json(SUBS_DIR / name)
        path = ROOT / cfg["promotionalImage"]
        if not path.exists():
            sys.exit(f"{name}: promotional image {cfg['promotionalImage']} not found (python tools/store/make_promo.py)")
        digest = md5_of(path)
        if digest in seen:
            sys.exit(f"{name}: promotional image {cfg['promotionalImage']} is the same as {seen[digest]}'s; "
                     "Apple rejects duplicate promotional images (Guideline 2.3.2)")
        seen[digest] = name


def sync_promotional_image(s: Store, sid: str, pid: str, path: Path) -> None:
    """Keep exactly this file as the plan's promotional image: an image with other content is deleted first
    (the rejected shared image of 2.0.0 included), then the file is uploaded. Apple names every uploaded image
    "SOURCE", so the image is matched by its checksum (by file name only when Apple gives no checksum)."""
    images = s.c.get_list(f"/v1/subscriptions/{sid}/images")
    pending = [i for i in images if (attr(i, "assetDeliveryState") or {}).get("state") in ("AWAITING_UPLOAD", "FAILED")]
    keep = []
    for img in (i for i in images if i not in pending):
        checksum = attr(img, "sourceFileChecksum")
        if (checksum == md5_of(path)) if checksum else (attr(img, "fileName") == path.name):
            keep.append(img)
            continue
        log(f"  subscriptionImages: the image on Apple is not the current {path.name}, replacing it")
        try:
            s.c.request("DELETE", f"/v1/subscriptionImages/{img['id']}")
        except ApiError as e:
            if e.status == 409:
                sys.exit(f"  {pid}: Apple keeps the promotional image while the plan sits in a review submission ({e}). "
                         "Take the plan's item out of the submission, run subscriptions again, then put it back "
                         "(apple-release skill, 'Promotional images').")
            raise
    if keep:
        log(f"  subscriptionImages: {path.name} already present, keeping it")
    else:
        s.upload_asset("subscriptionImages", {"subscription": rel("subscriptions", sid)}, path, pending)


def cmd_subscriptions(s: Store) -> None:
    log("== subscriptions")
    check_promotional_images()
    group_cfg = read_json(SUBS_DIR / "group.json")
    groups = s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups", {"filter[referenceName]": group_cfg["referenceName"]})
    if groups:
        group = groups[0]
        log(f"  subscriptionGroup {group_cfg['referenceName']}: exists ({group['id']})")
    else:
        log(f"  subscriptionGroup {group_cfg['referenceName']}: creating")
        group = s.c.create("subscriptionGroups", {"referenceName": group_cfg["referenceName"]}, {"app": rel("apps", APP_ID)})
    gid = group["id"]
    glocs = s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations")
    gloc = next((l for l in glocs if attr(l, "locale") == LOCALE), None)
    g_attrs = dict(localized(group_cfg))
    try:
        s.c.upsert("subscriptionGroupLocalizations", gloc, g_attrs if gloc else {**g_attrs, "locale": LOCALE},
                   {"subscriptionGroup": rel("subscriptionGroups", gid)}, label=f"group localization {LOCALE}",
                   refetch=lambda: next((l for l in s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations") if attr(l, "locale") == LOCALE), None))
    except ApiError as e:
        # Apple locks the group's name and custom app name before the first App Store release (409
        # UNMODIFIABLE even outside the review draft, 2026-10-15); change them in App Store Connect and
        # go on with the plans.
        if e.status != 409 or gloc is None:
            raise
        log(f"  group localization {LOCALE}: locked by Apple, left as is ({e})")

    in_group = {attr(x, "productId"): x for x in s.c.get_list(f"/v1/subscriptionGroups/{gid}/subscriptions")}
    territories = s.territories()
    for name in SUBSCRIPTION_FILES:
        cfg = read_json(SUBS_DIR / name)
        pid = cfg["productId"]
        log(f"  -- {pid}")
        sub = in_group.get(pid)
        if sub is None and cfg.get("appStoreId"):
            sub = s.c.get_one(f"/v1/subscriptions/{cfg['appStoreId']}")
        attrs = {"name": cfg["referenceName"], "reviewNote": cfg["reviewNote"], "subscriptionPeriod": cfg["subscriptionPeriod"],
                 "groupLevel": cfg["groupLevel"], "familySharable": cfg["familySharable"]}
        if sub is None:
            log(f"    {pid}: creating")
            sub = s.c.create("subscriptions", {**attrs, "productId": pid}, {"group": rel("subscriptionGroups", gid)})
        else:
            try:
                sub = s.c.upsert("subscriptions", sub, attrs, label=f"  {pid} ({attr(sub, 'state')})")
            except ApiError as err:
                if err.status != 409 or not err.mentions("UNMODIFIABLE", "can not be modified"):
                    raise
                sub = patch_outside_review_draft(s, sub, attrs, pid)
        sid = sub["id"]

        locs = s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
        loc_attrs = dict(localized(cfg))
        check_limit("iap_name", loc_attrs["name"])
        check_limit("iap_description", loc_attrs["description"])
        s.c.upsert("subscriptionLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
                   {"subscription": rel("subscriptions", sid)}, label=f"  {pid} localization {LOCALE}",
                   refetch=lambda: next((l for l in s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations") if attr(l, "locale") == LOCALE), None))

        # Prices: one subscriptionPrices record per territory, equalised from the USD price point.
        price = cfg["price"]["customerPrice"]
        priced = {territory_of(p) for p in s.c.get_list(f"/v1/subscriptions/{sid}/prices", {"include": "territory"})}
        point = s.price_point(f"/v1/subscriptions/{sid}/pricePoints", price, pid)
        by_territory = s.equalized(f"/v1/subscriptionPricePoints/{point['id']}/equalizations", point, {"filter[subscription]": sid})
        todo = {t: pp for t, pp in by_territory.items() if t not in priced}
        log(f"    prices: USD {price} -> {len(by_territory)} territories, {len(priced)} already set, creating {len(todo)}")
        for t, pp in todo.items():
            s.c.create("subscriptionPrices", {"preserveCurrentPrice": False},
                       {"subscription": rel("subscriptions", sid), "subscriptionPricePoint": rel("subscriptionPricePoints", pp),
                        "territory": rel("territories", t)})

        # Introductory offer: free trial, one per territory.
        offer = cfg["introductoryOffer"]
        offered = {territory_of(o) for o in s.c.get_list(f"/v1/subscriptions/{sid}/introductoryOffers", {"include": "territory"})}
        todo_t = [t for t in territories if t not in offered]
        log(f"    introductory offer {offer['offerMode']} {offer['duration']}: {len(offered)} territories set, creating {len(todo_t)}")
        for t in todo_t:
            s.c.create("subscriptionIntroductoryOffers",
                       {"offerMode": offer["offerMode"], "duration": offer["duration"], "numberOfPeriods": offer["numberOfPeriods"]},
                       {"subscription": rel("subscriptions", sid), "territory": rel("territories", t)})

        sync_winback_offers(s, sid, pid, cfg)

        shot = s.c.get_one(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        shot = s.drop_if_changed("subscriptionAppStoreReviewScreenshots", shot, ROOT / cfg["reviewScreenshot"])
        s.upload_asset("subscriptionAppStoreReviewScreenshots", {"subscription": rel("subscriptions", sid)},
                       ROOT / cfg["reviewScreenshot"], [shot] if shot else [])
        sync_promotional_image(s, sid, pid, ROOT / cfg["promotionalImage"])

        avail = s.c.get_one(f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if avail:
            log("    availability: exists")
        else:
            log(f"    availability: creating for {len(territories)} territories")
            s.c.create("subscriptionAvailabilities", {"availableInNewTerritories": True},
                       {"subscription": rel("subscriptions", sid), "availableTerritories": rel_many("territories", territories)})


def contact_attrs() -> dict:
    contact = read_json(EN / "review_contact.json")
    attrs = {}
    skipped = []
    for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
        if is_placeholder(contact.get(key)):
            skipped.append(key)
        else:
            attrs[key] = contact[key]
    if skipped:
        log(f"  review_contact.json still has placeholders for {', '.join(skipped)}; sending the rest")
    attrs["demoAccountRequired"] = bool(contact.get("demoAccountRequired", False))
    return attrs


def cmd_review_info(s: Store) -> None:
    log("== review-info")
    version = s.version(create=True)
    detail = s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
    attrs = {**contact_attrs(), "notes": read_text("review_notes.txt")}
    s.c.upsert("appStoreReviewDetails", detail, attrs, {"appStoreVersion": rel("appStoreVersions", version["id"])}, label="appStoreReviewDetail",
               refetch=lambda: s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail"))


def set_build_notes(s: Store, bid: str, text: str) -> None:
    """The build's own "What to Test" text that testers see in TestFlight (betaBuildLocalization)."""
    blocs = s.c.get_list(f"/v1/builds/{bid}/betaBuildLocalizations")
    bloc = next((l for l in blocs if attr(l, "locale") == LOCALE), None)
    whats_new = {"whatsNew": text}
    s.c.upsert("betaBuildLocalizations", bloc, whats_new if bloc else {**whats_new, "locale": LOCALE},
               {"build": rel("builds", bid)}, label=f"betaBuildLocalization {LOCALE}",
               refetch=lambda: next((l for l in s.c.get_list(f"/v1/builds/{bid}/betaBuildLocalizations") if attr(l, "locale") == LOCALE), None))


def cmd_build_notes(s: Store) -> None:
    """Set only the "What to Test" text of one build (--build N, default the latest), e.g. to fix or
    backfill a build's summary. Text: --whats-new-file, default testflight_build_notes.txt."""
    log("== build-notes")
    wanted = s.opt("build")
    build = s.build_by_number(str(wanted)) if wanted else s.latest_build()
    if build is None:
        sys.exit(f"build {wanted or '(latest)'} not found")
    path = s.opt("whats_new_file") or str(EN / "testflight_build_notes.txt")
    text = read_whats_new(path)
    if text is None:
        return
    log(f"  build {attr(build, 'version')}: {len(text)} characters")
    set_build_notes(s, build["id"], text)


def cmd_testflight(s: Store) -> None:
    log("== testflight")
    contact = contact_attrs()
    what_to_test = read_text("testflight_what_to_test.txt")
    locs = s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations")
    loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
    loc_attrs = {"description": what_to_test, "marketingUrl": read_text("marketing_url.txt"), "privacyPolicyUrl": read_text("privacy_url.txt")}
    if "contactEmail" in contact:
        loc_attrs["feedbackEmail"] = contact["contactEmail"]
    s.c.upsert("betaAppLocalizations", loc, loc_attrs if loc else {**loc_attrs, "locale": LOCALE},
               {"app": rel("apps", APP_ID)}, label=f"betaAppLocalization {LOCALE}",
               refetch=lambda: next((l for l in s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations") if attr(l, "locale") == LOCALE), None))

    detail = s.c.get_one(f"/v1/apps/{APP_ID}/betaAppReviewDetail")
    detail_attrs = {**contact, "notes": read_text("review_notes.txt")}
    if "contactPhone" not in contact:
        log("  betaAppReviewDetail: skipped, Apple requires contactPhone (fill review_contact.json and rerun)")
        detail = False
    if detail is None:
        if s.c.dry_run:
            detail = {"id": "DRY-betaAppReviewDetail", "attributes": {}}
        else:
            sys.exit("no betaAppReviewDetail on the app; App Store Connect creates it with the app record")
    if detail is not False:
        s.c.upsert("betaAppReviewDetails", detail, detail_attrs, label="betaAppReviewDetail")

    agreement = s.c.get_one(f"/v1/apps/{APP_ID}/betaLicenseAgreement")
    text = read_text("beta_license_agreement.txt")
    if agreement is None:
        if s.c.dry_run:
            agreement = {"id": "DRY-betaLicenseAgreement", "attributes": {}}
        else:
            sys.exit("no betaLicenseAgreement on the app; App Store Connect creates it with the app record")
    s.c.upsert("betaLicenseAgreements", agreement, {"agreementText": text}, label="betaLicenseAgreement")

    groups = s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups")
    group = next((g for g in groups if attr(g, "name") == BETA_GROUP_NAME), None)
    group_attrs = {"publicLinkEnabled": True, "publicLinkLimitEnabled": False, "feedbackEnabled": True}
    group = s.c.upsert("betaGroups", group, group_attrs if group else {**group_attrs, "name": BETA_GROUP_NAME, "isInternalGroup": False},
                       {"app": rel("apps", APP_ID)}, label=f"betaGroup '{BETA_GROUP_NAME}'")
    link = attr(group, "publicLink")
    if link:
        log(f"  public TestFlight link: {link}")

    wanted = s.opt("build") or os.environ.get("ASC_BUILD_NUMBER", "").strip() or None
    if wanted:
        log(f"  waiting for build {wanted} to finish processing (up to {s.opt('timeout', 40):g} min)")
        build = s.wait_for_build(str(wanted), float(s.opt("timeout", 40)))
    else:
        build = s.latest_build()
    if build is None:
        log("  no build uploaded yet; skipping build metadata (run tools/store/upload_build.sh, then this again)")
        return
    bid = build["id"]
    log(f"  {'build' if wanted else 'latest build'} {attr(build, 'version')} ({attr(build, 'processingState')}, uploaded {attr(build, 'uploadedDate')})")
    if attr(build, "usesNonExemptEncryption") is not False:
        log("  build: setting usesNonExemptEncryption=false")
        s.c.update("builds", bid, {"usesNonExemptEncryption": False})
    else:
        log("  build: usesNonExemptEncryption already false")
    # A build's "What to Test" is the per-build TL;DR, never the version-wide release notes.
    whats_new_text = read_whats_new(s.opt("whats_new_file") or str(EN / "testflight_build_notes.txt"))
    if whats_new_text is not None:
        set_build_notes(s, bid, whats_new_text)
    in_group = {b["id"] for b in s.c.get_list(f"/v1/betaGroups/{group['id']}/builds")}
    if bid in in_group:
        log("  build already in the public group")
    else:
        log(f"  adding build to '{BETA_GROUP_NAME}'")
        s.c.request("POST", f"/v1/betaGroups/{group['id']}/relationships/builds", rel_many("builds", [bid]))

    # Internal groups (App Store Connect users) can install a build straight
    # away, without Beta App Review. Groups that get every build automatically
    # need nothing; the others get the build added by hand here.
    for g in groups:
        if not attr(g, "isInternalGroup"):
            continue
        name = attr(g, "name")
        if attr(g, "hasAccessToAllBuilds"):
            log(f"  internal group {name}: has access to all builds (installable now)")
            continue
        if bid in {b["id"] for b in s.c.get_list(f"/v1/betaGroups/{g['id']}/builds")}:
            log(f"  internal group {name}: build already added (installable now)")
            continue
        s.c.request("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", rel_many("builds", [bid]))
        log(f"  internal group {name}: build added (installable now)")

    # External testers (the public link) can only install a build that has passed
    # Beta App Review. Submit the build unless it already has a submission.
    detail = s.c.get_one(f"/v1/builds/{bid}/buildBetaDetail")
    ext_state = attr(detail, "externalBuildState") if detail else None
    submission = s.c.get_one(f"/v1/builds/{bid}/betaAppReviewSubmission")
    if submission:
        log(f"  beta app review: {attr(submission, 'betaReviewState')} (external state {ext_state})")
    elif ext_state == "READY_FOR_BETA_SUBMISSION":
        if s.c.dry_run:
            log("  beta app review: would submit the build")
        else:
            try:
                r = s.c.create("betaAppReviewSubmissions", None, {"build": rel("builds", bid)})
                log(f"  beta app review: submitted ({attr(r, 'betaReviewState')}); the public link works once Apple approves it")
            except ApiError as e:
                if e.status == 422 and any("ANOTHER_BUILD_IN_REVIEW" in (x.get("code") or "") for x in e.errors):
                    # Apple reviews one build per version; this build inherits that approval.
                    log("  beta app review: another build of this version is already in review; this build follows it automatically")
                else:
                    raise
    else:
        log(f"  beta app review: external state {ext_state}, nothing to submit")


# ---------------------------------------------------------------------------
# Read-only commands
# ---------------------------------------------------------------------------


FEEDBACK_DIR = ROOT / "store" / "feedback"
FEEDBACK_LEDGER = FEEDBACK_DIR / "resolved.json"


def _feedback_items(s: Store) -> list[dict]:
    items = []
    for kind in ("betaFeedbackScreenshotSubmissions", "betaFeedbackCrashSubmissions"):
        for it in s.c.get_list(f"/v1/apps/{APP_ID}/{kind}", {"limit": 200}):
            it["_kind"] = kind
            items.append(it)
    items.sort(key=lambda i: attr(i, "createdDate") or "")
    return items


def _ledger() -> dict:
    return json.loads(FEEDBACK_LEDGER.read_text()) if FEEDBACK_LEDGER.exists() else {}


def cmd_feedback(s: Store) -> int:
    """List TestFlight feedback (screenshots and crashes) that is not yet
    resolved; `--resolve ID[,ID] --note TEXT` deletes those items from App Store
    Connect (Apple has no "resolved" state, deletion is the native way to close
    feedback) and records them in store/feedback/resolved.json so they can
    still be looked up later."""
    args = s.opts
    ledger = _ledger()
    items = _feedback_items(s)
    if args.resolve:
        wanted = [x.strip() for x in args.resolve.split(",") if x.strip()]
        by_id = {i["id"]: i for i in items}
        for fid in wanted:
            it = by_id.get(fid)
            if not it:
                log(f"  {fid}: not found on Apple (already deleted?)")
                continue
            a = it["attributes"]
            ledger[fid] = {
                "kind": it["_kind"], "createdDate": a.get("createdDate"), "email": a.get("email"),
                "device": f"{a.get('deviceModel')} iOS {a.get('osVersion')}", "comment": a.get("comment"),
                "resolvedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "note": args.note or "",
                "screenshots": [str(p.relative_to(ROOT)) for p in _save_feedback_shots(it)],
            }
            if s.c.dry_run:
                log(f"  {fid}: would delete on Apple")
            else:
                s.c.request("DELETE", f"/v1/{it['_kind']}/{fid}")
                log(f"  {fid}: resolved and deleted on Apple")
        FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)
        FEEDBACK_LEDGER.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n")
        return 0
    open_items = [i for i in items if i["id"] not in ledger]
    log(f"== feedback: {len(open_items)} open, {len(ledger)} resolved")
    for it in open_items:
        a = it["attributes"]
        kind = "crash" if "Crash" in it["_kind"] else "screenshot"
        shots = _save_feedback_shots(it)
        log(f"  {it['id']}  {a.get('createdDate', '')[:16]}  {kind}  {a.get('email')}  {a.get('deviceModel')} iOS {a.get('osVersion')}")
        log(f"      {a.get('comment') or (a.get('crashLog') or '')[:160]!r}")
        for p in shots:
            log(f"      {p.relative_to(ROOT)}")
    return 0


def _save_feedback_shots(it: dict) -> list[Path]:
    out = []
    folder = FEEDBACK_DIR / it["id"]
    for n, shot in enumerate(attr(it, "screenshots") or []):
        url = shot.get("url")
        if not url:
            continue
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"{n + 1}.png"
        if not path.exists():
            path.write_bytes(requests.get(url, timeout=60).content)
        out.append(path)
    return out


def cmd_status(s: Store, categories: bool = False) -> None:
    log("== status")
    app = s.app()
    log(f"  app {APP_ID}: {attr(app, 'name')} ({attr(app, 'bundleId')}) primaryLocale={attr(app, 'primaryLocale')}")
    for info in s.c.get_list(f"/v1/apps/{APP_ID}/appInfos"):
        cats = {k: ((v.get('data') or {}).get('id')) for k, v in (info.get('relationships') or {}).items() if 'ategory' in k and v.get('data')}
        log(f"  appInfo {info['id']}: state={attr(info, 'state')} ageRating={attr(info, 'appStoreAgeRating')} {cats}")
        for loc in s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations"):
            log(f"    {attr(loc, 'locale')}: name={attr(loc, 'name')!r} subtitle={attr(loc, 'subtitle')!r} privacy={attr(loc, 'privacyPolicyUrl')}")
    for v in s.c.get_list(f"/v1/apps/{APP_ID}/appStoreVersions", {"filter[platform]": PLATFORM}):
        log(f"  appStoreVersion {attr(v, 'versionString')}: state={attr(v, 'appVersionState') or attr(v, 'appStoreState')} copyright={attr(v, 'copyright')!r}")
        for loc in s.c.get_list(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations"):
            sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
            shots = {attr(x, 'screenshotDisplayType'): len(s.c.get_list(f"/v1/appScreenshotSets/{x['id']}/appScreenshots")) for x in sets}
            log(f"    {attr(loc, 'locale')}: description={len(attr(loc, 'description') or '')} chars keywords={attr(loc, 'keywords')!r} screenshots={shots}")
        detail = s.c.get_one(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")
        log(f"    reviewDetail: {'set' if detail else 'missing'}")
    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    log(f"  appPriceSchedule: {'set' if schedule else 'missing'}")
    avail = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    log(f"  appAvailabilityV2: {'set' if avail else 'missing'}")
    for iap in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2"):
        log(f"  iap {attr(iap, 'productId')}: {attr(iap, 'inAppPurchaseType')} state={attr(iap, 'state')} id={iap['id']}")
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups"):
        log(f"  subscriptionGroup {attr(g, 'referenceName')} ({g['id']})")
        for sub in s.c.get_list(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            prices = s.c.get_list(f"/v1/subscriptions/{sub['id']}/prices")
            offers = s.c.get_list(f"/v1/subscriptions/{sub['id']}/introductoryOffers")
            log(f"    {attr(sub, 'productId')}: state={attr(sub, 'state')} period={attr(sub, 'subscriptionPeriod')} prices={len(prices)} introOffers={len(offers)} id={sub['id']}")
    build = s.latest_build()
    log(f"  latest build: {attr(build, 'version') if build else 'none'}" + (f" ({attr(build, 'processingState')})" if build else ""))
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups"):
        log(f"  betaGroup {attr(g, 'name')!r}: public={attr(g, 'publicLinkEnabled')} link={attr(g, 'publicLink')}")
    if categories:
        log("  appCategories (ids for categories.json):")
        for cat in s.c.get_list("/v1/appCategories", {"filter[platforms]": PLATFORM, "exists[parent]": "false", "include": "subcategories"}):
            subs = [x["id"] for x in ((cat.get("relationships") or {}).get("subcategories") or {}).get("data") or []]
            log(f"    {cat['id']}: {', '.join(subs)}")


AuditRow = tuple[str, str, str, str]  # state, what, detail, section ("store" or "testflight")


def cmd_audit(s: Store) -> int:
    """Checklist for App Store submission and a public TestFlight link. Read-only."""
    log("== audit")
    return _print_audit(audit_rows(s))


def audit_rows(s: Store) -> list[AuditRow]:
    rows: list[AuditRow] = []
    section = "store"

    def row(state: str, what: str, detail: str = "") -> None:
        rows.append((state, what, detail, section))

    def ok_if(cond: Any, what: str, detail: str = "") -> None:
        row("OK" if cond else "MISSING", what, detail)

    app = s.app()
    ok_if(app, "app record", f"{attr(app, 'name')} {attr(app, 'bundleId')}" if app else f"GET /v1/apps/{APP_ID} returned nothing")
    if not app and not s.c.dry_run:
        return rows

    info = s.app_info()
    rels = info.get("relationships") or {}
    primary = ((rels.get("primaryCategory") or {}).get("data")) or s.c.get_one(f"/v1/appInfos/{info['id']}/primaryCategory")
    ok_if(primary, "primary category", primary["id"] if primary else None)
    locs = s.c.get_list(f"/v1/appInfos/{info['id']}/appInfoLocalizations")
    loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
    ok_if(loc and attr(loc, "name"), f"app name ({LOCALE})")
    ok_if(loc and attr(loc, "subtitle"), f"subtitle ({LOCALE})")
    ok_if(loc and attr(loc, "privacyPolicyUrl"), "privacy policy URL")
    decl = s.c.get_one(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    ok_if(decl and attr(decl, "violenceCartoonOrFantasy") is not None, "age rating questionnaire")

    version = s.version()
    ok_if(version, f"appStoreVersion {VERSION_STRING} ({PLATFORM})")
    if version:
        ok_if(attr(version, "copyright"), "copyright")
        vloc = s.version_localization(version)
        ok_if(vloc, f"version localization ({LOCALE})")
        if vloc:
            for key in ("description", "keywords", "supportUrl"):
                ok_if(attr(vloc, key), f"  {key}")
            row("OK" if attr(vloc, "promotionalText") else "N/A", "  promotionalText (optional)")
            row("OK" if attr(vloc, "marketingUrl") else "N/A", "  marketingUrl (optional)")
            sets = s.c.get_list(f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")
            by_type = {attr(x, "screenshotDisplayType"): x for x in sets}
            shots = s.c.get_list(f"/v1/appScreenshotSets/{by_type[SCREENSHOT_TYPE]['id']}/appScreenshots") if SCREENSHOT_TYPE in by_type else []
            complete = [x for x in shots if ((attr(x, "assetDeliveryState") or {}).get("state")) in ("COMPLETE", None)]
            ok_if(complete, f"  screenshots {SCREENSHOT_TYPE}", f"{len(complete)} of {len(shots)} delivered")
            row("OK" if "APP_IPAD_PRO_3GEN_129" in by_type else "N/A", "  screenshots iPad 13-inch (only if the app runs on iPad)")
        detail = s.c.get_one(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
        ok_if(detail, "App Review contact (appStoreReviewDetail)")
        if detail:
            for key in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
                ok_if(attr(detail, key), f"  {key}")
            row("OK" if attr(detail, "notes") else "N/A", "  review notes (optional)")
        build_rel = ((version.get("relationships") or {}).get("build") or {}).get("data") or s.c.get_one(f"/v1/appStoreVersions/{version['id']}/build")
        ok_if(build_rel, "build attached to the version",
              f"build {attr(build_rel, 'version')}" if build_rel and build_rel.get("attributes") else "select a build in App Store Connect or PATCH appStoreVersions/{id}/relationships/build")

    schedule = s.c.get_one(f"/v1/apps/{APP_ID}/appPriceSchedule")
    described = s.describe_price_schedule(schedule) if schedule and not s.c.dry_run else ""
    ok_if(schedule and described != "no manual prices", "price schedule (free)", described or "run `price-free`")
    avail = s.c.get_one(f"/v1/apps/{APP_ID}/appAvailabilityV2")
    ok_if(avail, "territory availability")
    ok_if(attr(app, "contentRightsDeclaration") if app else None, "content rights declaration", "`app-info` sets USES_THIRD_PARTY_CONTENT (licensed photos)")
    urls = (attr(app, "subscriptionStatusUrl"), attr(app, "subscriptionStatusUrlForSandbox")) if app else (None, None)
    ok_if(all(u == NOTIFICATIONS_URL for u in urls), "App Store Server Notification URLs (production + sandbox, V2)", f"{urls[0]} / {urls[1]}")

    cfg = read_json(SUBS_DIR / "consumables.json")
    existing = {attr(p, "productId"): p for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2")}
    for product in cfg["products"]:
        pid = product["productId"]
        iap = existing.get(pid)
        if not iap:
            row("MISSING", f"iap {pid}")
            continue
        locs_i = s.c.get_list(f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")
        sched = s.c.get_one(f"/v2/inAppPurchases/{iap['id']}/iapPriceSchedule")
        shot = s.c.get_one(f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot")
        parts = [f"state={attr(iap, 'state')}", f"localizations={len(locs_i)}", f"price={'set' if sched else 'MISSING'}", f"reviewScreenshot={'set' if shot else 'missing'}"]
        ok_if(locs_i and sched, f"iap {pid}", " ".join(parts))

    group_cfg = read_json(SUBS_DIR / "group.json")
    groups = s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups", {"filter[referenceName]": group_cfg["referenceName"]})
    ok_if(groups, f"subscription group {group_cfg['referenceName']}")
    if groups:
        glocs = s.c.get_list(f"/v1/subscriptionGroups/{groups[0]['id']}/subscriptionGroupLocalizations")
        ok_if(glocs, "  group localization")
        subs = {attr(x, "productId"): x for x in s.c.get_list(f"/v1/subscriptionGroups/{groups[0]['id']}/subscriptions")}
        for name in ("vip_monthly.json", "vip_yearly.json"):
            scfg = read_json(SUBS_DIR / name)
            pid = scfg["productId"]
            sub = subs.get(pid)
            if not sub:
                row("MISSING", f"  subscription {pid}")
                continue
            sid = sub["id"]
            n_loc = len(s.c.get_list(f"/v1/subscriptions/{sid}/subscriptionLocalizations"))
            n_price = len(s.c.get_list(f"/v1/subscriptions/{sid}/prices"))
            n_offer = len(s.c.get_list(f"/v1/subscriptions/{sid}/introductoryOffers"))
            shot = s.c.get_one(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
            avail_s = s.c.get_one(f"/v1/subscriptions/{sid}/subscriptionAvailability")
            ok_if(n_loc and n_price and shot and avail_s, f"  subscription {pid}",
                  f"state={attr(sub, 'state')} localizations={n_loc} prices={n_price} introOffers={n_offer} reviewScreenshot={'set' if shot else 'MISSING'} availability={'set' if avail_s else 'MISSING'}")
            row("OK" if n_offer else "MISSING", f"    {pid} introductory offer (1 week free)")

    # TestFlight
    section = "testflight"
    blocs = s.c.get_list(f"/v1/apps/{APP_ID}/betaAppLocalizations")
    bloc = next((l for l in blocs if attr(l, "locale") == LOCALE), None)
    ok_if(bloc and attr(bloc, "feedbackEmail"), "TestFlight feedback email (betaAppLocalization)")
    ok_if(bloc and attr(bloc, "description"), "TestFlight 'what to test' description")
    ok_if(bloc and attr(bloc, "privacyPolicyUrl"), "TestFlight privacy policy URL")
    bdetail = s.c.get_one(f"/v1/apps/{APP_ID}/betaAppReviewDetail")
    ok_if(bdetail and attr(bdetail, "contactEmail") and attr(bdetail, "contactFirstName"), "TestFlight beta review contact")
    agreement = s.c.get_one(f"/v1/apps/{APP_ID}/betaLicenseAgreement")
    row("OK" if agreement and attr(agreement, "agreementText") else "N/A", "TestFlight license agreement (optional, Apple's default applies)")
    build = s.latest_build()
    ok_if(build, "uploaded build", f"{attr(build, 'version')} {attr(build, 'processingState')}" if build else "run tools/store/upload_build.sh")
    if build:
        ok_if(attr(build, "processingState") == "VALID", "  build processed", attr(build, "processingState"))
        ok_if(attr(build, "usesNonExemptEncryption") is not None, "  export compliance (usesNonExemptEncryption)", "set ITSAppUsesNonExemptEncryption in Info.plist or run `testflight`")
        bl = s.c.get_list(f"/v1/builds/{build['id']}/betaBuildLocalizations")
        row("OK" if any(attr(x, "whatsNew") for x in bl) else "N/A", "  build 'what to test' (optional)")
    groups_b = s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups")
    public = [g for g in groups_b if attr(g, "publicLinkEnabled")]
    ok_if(public, "public TestFlight group", ", ".join(f"{attr(g, 'name')} {attr(g, 'publicLink')}" for g in public))
    if public and build:
        in_group = {b["id"] for b in s.c.get_list(f"/v1/betaGroups/{public[0]['id']}/builds")}
        ok_if(build["id"] in in_group, "  latest build in the public group")
    section = "store"
    row("N/A", "App privacy (data collection) questionnaire", "no public API; fill in App Store Connect > App Privacy")
    row("N/A", "Paid Applications agreement, banking and tax", "no public API; App Store Connect > Business")
    return rows


def _print_audit(rows: list[AuditRow]) -> int:
    missing = 0
    for state, what, detail, _section in rows:
        missing += state == "MISSING"
        log(f"  [{state:7}] {what}" + (f"  - {detail}" if detail else ""))
    log(f"  {missing} missing item(s)")
    return 1 if missing else 0


# ---------------------------------------------------------------------------
# App Store release: version + build, then the review submission
# ---------------------------------------------------------------------------


def cmd_release(s: Store) -> None:
    """Prepare the App Store version: find or create it, set the release type,
    attach the build, write what's new (and the full localization when new)."""
    global VERSION_STRING
    VERSION_STRING = s.opt("version") or pubspec_version()
    log(f"== release {VERSION_STRING}")
    existing = s.version()
    if existing and version_state(existing) not in EDITABLE_VERSION_STATES:
        sys.exit(f"appStoreVersion {VERSION_STRING} is {version_state(existing)} and can no longer be changed; "
                 "bump the version in pubspec.yaml or pass --version")
    whats_new = read_whats_new(s.opt("whats_new_file"))
    version, whats_new_result = sync_version_metadata(s, whats_new, only_whats_new=True)
    vid = version["id"]

    # MANUAL: an approved version waits for a human to press "Release this version".
    release_type = "AFTER_APPROVAL" if s.opt("auto_release") else "MANUAL"
    if attr(version, "releaseType") == release_type:
        log(f"  releaseType: {release_type}, up to date")
    else:
        log(f"  releaseType: {attr(version, 'releaseType')} -> {release_type}")
        s.c.update("appStoreVersions", vid, {"releaseType": release_type})

    number = s.opt("build") or os.environ.get("ASC_BUILD_NUMBER", "").strip() or None
    if number:
        build = s.build_by_number(str(number))
        if build is None:
            sys.exit(f"build {number} is not in App Store Connect (run `testflight --build {number}` to wait for it)")
        if attr(build, "processingState") != "VALID":
            sys.exit(f"build {number} is {attr(build, 'processingState')}, not VALID; cannot attach it")
    else:
        build = s.latest_valid_build(VERSION_STRING)
        if build is None:
            sys.exit("no processed build to attach; upload one first")
    attached = s.c.get_one(f"/v1/appStoreVersions/{vid}/build")
    if attached and attached["id"] == build["id"]:
        log(f"  build {attr(build, 'version')}: already attached")
    else:
        log(f"  build: attaching {attr(build, 'version')}" + (f" (replacing {attr(attached, 'version')})" if attached else ""))
        s.c.request("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", rel("builds", build["id"]))

    log(f"  summary: appStoreVersion {VERSION_STRING} ({version_state(version) or 'new'}) id={vid}, build {attr(build, 'version')}, "
        f"releaseType {release_type}, what's new {whats_new_result}")
    log("  next: `submit` (preview) then `submit --yes` to send it to App Review")


ITEM_RELATIONSHIPS = ("appStoreVersion", "inAppPurchaseVersion", "subscriptionVersion", "subscriptionGroupVersion", "appEvent")


def submission_items(s: Store, submission: dict) -> dict[str, list[str]]:
    """relationship name -> ids already in the submission."""
    out: dict[str, list[str]] = {k: [] for k in ITEM_RELATIONSHIPS}
    for item in s.c.get_list(f"/v1/reviewSubmissions/{submission['id']}/items", {"include": ",".join(ITEM_RELATIONSHIPS)}):
        for name in ITEM_RELATIONSHIPS:
            id_ = related_id(item, name)
            if id_:
                out[name].append(id_)
    return out


def cmd_submit(s: Store) -> int:
    """Send the editable version (with its in-app purchases) to App Review.

    App Store Connect keeps one open review submission per app. Products that
    were pressed "Submit for Review" in App Store Connect are already items in
    it; the API only exposes the link from an item to its product, not the
    other way round, so products still missing are reported for the console."""
    global VERSION_STRING
    log("== submit")
    version = s.editable_version()
    if version is None:
        if not s.c.dry_run:
            sys.exit("no editable appStoreVersion; run `release` first")
        version = s.version(create=True)
    VERSION_STRING = attr(version, "versionString")
    vid = version["id"]
    attached = s.c.get_one(f"/v1/appStoreVersions/{vid}/build")
    log(f"  appStoreVersion {VERSION_STRING} ({version_state(version)}), build {attr(attached, 'version') if attached else 'NONE'}, "
        f"releaseType {attr(version, 'releaseType')}")

    missing = [what for state, what, _d, section in audit_rows(s) if state == "MISSING" and section == "store"]
    if missing:
        for what in missing:
            log(f"  MISSING: {what.strip()}")
        if s.c.dry_run:
            log("  (dry run: a real run would stop here)")
        else:
            sys.exit(f"refusing to submit: {len(missing)} required item(s) missing; see `audit`")
    else:
        log("  audit: every required item is present")

    submissions = s.c.get_list(f"/v1/apps/{APP_ID}/reviewSubmissions")
    active = [r for r in submissions if attr(r, "state") in ACTIVE_SUBMISSION_STATES]
    if active:
        r = active[0]
        log(f"  review submission {r['id']} is already {attr(r, 'state')} (submitted {attr(r, 'submittedDate')}); nothing to do")
        return 0
    pending = [r for r in submissions if attr(r, "state") in PENDING_SUBMISSION_STATES]
    submission = pending[0] if pending else None
    items = submission_items(s, submission) if submission else {k: [] for k in ITEM_RELATIONSHIPS}
    if submission:
        log(f"  open review submission {submission['id']} ({attr(submission, 'state')}) with "
            f"{sum(len(v) for v in items.values())} item(s)")
    else:
        log("  no open review submission; one will be created")

    # Products that should go to review with this version.
    iap_by_id = {p["id"]: attr(p, "productId") for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2") if attr(p, "state") == "READY_TO_SUBMIT"}
    sub_by_id: dict[str, str] = {}
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups"):
        for sub in s.c.get_list(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            if attr(sub, "state") == "READY_TO_SUBMIT":
                sub_by_id[sub["id"]] = attr(sub, "productId")
    covered_iaps = {related_id(s.c.get_one(f"/v1/inAppPurchaseVersions/{v}", {"include": "inAppPurchase"}), "inAppPurchase")
                    for v in items["inAppPurchaseVersion"]}
    covered_subs = {related_id(s.c.get_one(f"/v1/subscriptionVersions/{v}", {"include": "subscription"}), "subscription")
                    for v in items["subscriptionVersion"]}
    version_in = vid in items["appStoreVersion"]
    log(f"  item appStoreVersion {VERSION_STRING}: {'already in the submission' if version_in else 'will be added'}")
    for id_, pid in iap_by_id.items():
        log(f"  item in-app purchase {pid}: {'in the submission' if id_ in covered_iaps else 'NOT in the submission'}")
    for id_, pid in sub_by_id.items():
        log(f"  item subscription {pid}: {'in the submission' if id_ in covered_subs else 'NOT in the submission'}")
    if items["subscriptionGroupVersion"]:
        log(f"  item subscription group: in the submission ({len(items['subscriptionGroupVersion'])})")
    absent = [pid for id_, pid in {**iap_by_id, **sub_by_id}.items() if id_ not in covered_iaps | covered_subs]
    if absent:
        log(f"  {len(absent)} product(s) are READY_TO_SUBMIT but not in the submission: {', '.join(absent)}")
        log("  run `draft` first: it adds every READY_TO_SUBMIT product to the open submission")
        if not s.opt("without_iap") and not s.c.dry_run:
            sys.exit("refusing to submit without them; pass --without-iap to submit the app alone")

    if not s.opt("yes"):
        log("  preview only: rerun with --yes to create the item(s) above and submit for review")
        return 0

    if submission is None:
        log("  reviewSubmission: creating")
        try:
            submission = s.c.create("reviewSubmissions", {"platform": PLATFORM}, {"app": rel("apps", APP_ID)})
        except ApiError as err:
            if err.status != 409:
                raise
            log(f"  Apple refused a new submission (409: {err}); looking for the open one again")
            pending = [r for r in s.c.get_list(f"/v1/apps/{APP_ID}/reviewSubmissions") if attr(r, "state") in PENDING_SUBMISSION_STATES]
            if not pending:
                raise
            submission = pending[0]
    sid = submission["id"]
    if not version_in:
        log(f"  reviewSubmissionItem: adding appStoreVersion {VERSION_STRING}")
        try:
            s.c.create("reviewSubmissionItems", None,
                       {"reviewSubmission": rel("reviewSubmissions", sid), "appStoreVersion": rel("appStoreVersions", vid)})
        except ApiError as err:
            if err.status != 409:
                raise
            log(f"  Apple says the version is already part of the submission (409: {err})")
    log(f"  reviewSubmission {sid}: submitting")
    result = s.c.update("reviewSubmissions", sid, {"submitted": True})
    log(f"  submitted: state {attr(result, 'state') or 'unknown'}; follow it in App Store Connect > App Review")
    log("  after approval the version waits for a manual release (releaseType MANUAL) unless `release --auto-release` was used")
    return 0


def cmd_draft(s: Store) -> int:
    """Fill the open review draft without submitting it: the editable version (with its attached
    build), every in-app purchase, subscription and subscription group that is READY_TO_SUBMIT, and
    with --events the In-App Event drafts. Creates the draft when there is none. The owner reviews it
    in App Store Connect (Draft Submissions) and presses Submit there, or runs `submit --yes`."""
    global VERSION_STRING
    log("== draft")
    version = s.editable_version()
    if version is None:
        sys.exit("no editable appStoreVersion; run `release` first")
    VERSION_STRING = attr(version, "versionString")
    attached = s.c.get_one(f"/v1/appStoreVersions/{version['id']}/build")
    if attached is None or attr(attached, "version") is None:
        sys.exit("the version has no build; run `release --build N` first")
    log(f"  appStoreVersion {VERSION_STRING} ({version_state(version)}), build {attr(attached, 'version')}")
    submissions = s.c.get_list(f"/v1/apps/{APP_ID}/reviewSubmissions", {"filter[platform]": PLATFORM})
    if any(attr(r, "state") in ACTIVE_SUBMISSION_STATES for r in submissions):
        sys.exit("a review submission is already with Apple; nothing to draft")
    pending = [r for r in submissions if attr(r, "state") in PENDING_SUBMISSION_STATES]
    if pending:
        submission = pending[0]
        log(f"  open draft {submission['id']}")
    else:
        submission = s.c.create("reviewSubmissions", {"platform": PLATFORM}, {"app": rel("apps", APP_ID)})
        log(f"  draft created {submission['id']}")
    sid = submission["id"]
    items = submission_items(s, submission)

    def add(kind: str, type_: str, id_: str, label: str) -> None:
        if id_ in items[kind]:
            log(f"  {label}: in the draft")
            return
        try:
            s.c.create("reviewSubmissionItems", None, {"reviewSubmission": rel("reviewSubmissions", sid), kind: rel(type_, id_)})
            log(f"  {label}: added")
        except ApiError as err:
            log(f"  {label}: Apple refused ({err.status}: {str(err)[:160]})")

    def editable(versions: list[dict]) -> dict | None:
        # The version not yet sent: PREPARE_FOR_SUBMISSION, else the newest.
        return next((v for v in versions if attr(v, "state") in (None, "PREPARE_FOR_SUBMISSION", "READY_TO_SUBMIT")), versions[0] if versions else None)

    add("appStoreVersion", "appStoreVersions", version["id"], f"version {VERSION_STRING}")
    for p in s.c.get_list(f"/v1/apps/{APP_ID}/inAppPurchasesV2"):
        if attr(p, "state") != "READY_TO_SUBMIT":
            continue
        v = editable(s.c.get_list(f"/v2/inAppPurchases/{p['id']}/versions"))
        if v:
            add("inAppPurchaseVersion", "inAppPurchaseVersions", v["id"], f"in-app purchase {attr(p, 'productId')}")
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/subscriptionGroups"):
        for sub in s.c.get_list(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
            if attr(sub, "state") != "READY_TO_SUBMIT":
                continue
            v = editable(s.c.get_list(f"/v1/subscriptions/{sub['id']}/versions"))
            if v:
                add("subscriptionVersion", "subscriptionVersions", v["id"], f"subscription {attr(sub, 'productId')}")
        gv = editable(s.c.get_list(f"/v1/subscriptionGroups/{g['id']}/versions"))
        if gv:
            add("subscriptionGroupVersion", "subscriptionGroupVersions", gv["id"], f"subscription group {attr(g, 'referenceName')}")
    if s.opt("events"):
        for e in s.c.get_list(f"/v1/apps/{APP_ID}/appEvents"):
            if attr(e, "eventState") not in ("DRAFT", "READY_FOR_REVIEW"):
                continue
            add("appEvent", "appEvents", e["id"], f"In-App Event {attr(e, 'referenceName')}")
    total = len(s.c.request("GET", f"/v1/reviewSubmissions/{sid}/items").get("data") or [])
    log(f"  draft {sid}: {total} item(s); not submitted (App Store Connect > Draft Submissions, or `submit --yes`)")
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _utc(value: str) -> "dt.datetime":
    import datetime as dt
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def _iso(t: "dt.datetime") -> str:
    return t.astimezone(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _same_schedule(a: list | None, b: list) -> bool:
    if not a or len(a) != len(b):
        return False
    for x, y in zip(a, b):
        if set(x.get("territories") or []) != set(y.get("territories") or []):
            return False
        if any(_utc(x[k]) != _utc(y[k]) for k in ("publishStart", "eventStart", "eventEnd") if x.get(k) and y.get(k)):
            return False
    return True


def cmd_events(s: Store) -> int:
    """In-App Events for the next world-day events and the next major holidays after them, as drafts.
    Never submits: Apple reviews events with an app version (the first one must go with the first App
    Store submission) or on their own later, and the owner starts that. Events Apple has already accepted
    are left alone."""
    import datetime as dt
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from make_app_events import pick  # the same choice the media step makes
    log("== in-app events (drafts only, never submitted)")
    if not APP_EVENTS.exists():
        sys.exit(f"{APP_EVENTS.relative_to(ROOT)} is missing: run tools/store/make_app_events.py first")
    events = read_json(APP_EVENTS)["events"]
    window = EVENT_WINDOW if s.opt("window") is None else int(s.opt("window"))
    primary = EVENT_PRIMARY if s.opt("primary") is None else int(s.opt("primary"))
    now = dt.datetime.now(dt.timezone.utc)
    todo = pick(events, now, window, primary, EVENT_LEAD_DAYS)
    existing = {attr(x, "referenceName"): x for x in s.c.get_list(f"/v1/apps/{APP_ID}/appEvents")}
    territories = s.territories()
    missing_media = []
    for e in todo:
        ref = e["referenceName"]
        loc_cfg = e["localization"]
        for field, limit in (("name", 30), ("shortDescription", 50), ("longDescription", 120)):
            if len(loc_cfg[field]) > limit:
                sys.exit(f"{ref}: {field} is {len(loc_cfg[field])} characters (Apple allows {limit})")
        # Apple needs the publish date ahead of now: never earlier than the next full UTC day.
        tomorrow = (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        publish = max(_utc(e["publishStart"]), tomorrow)
        schedule = [{"territories": territories, "publishStart": _iso(publish),
                     "eventStart": e["eventStart"], "eventEnd": e["eventEnd"]}]
        attrs = {"referenceName": ref, "badge": e["badge"], "deepLink": e["deepLink"], "purpose": e["purpose"],
                 "priority": e["priority"], "purchaseRequirement": e["purchaseRequirement"], "primaryLocale": LOCALE,
                 "territorySchedules": schedule}
        ev = existing.get(ref)
        state = attr(ev, "eventState")
        log(f"  -- {ref} ({e['eventStart'][:10]}, {state or 'new'}{', major holiday' if e.get('primary') else ''})")
        if ev and state not in EVENT_EDITABLE_STATES:
            log(f"    {state}: left alone")
            continue
        if ev is None:
            ev = s.c.create("appEvents", attrs, {"app": rel("apps", APP_ID)})
        else:
            if _same_schedule(attr(ev, "territorySchedules"), schedule):
                attrs.pop("territorySchedules")
            attrs.pop("primaryLocale")
            ev = s.c.upsert("appEvents", ev, attrs, label="    event")
        eid = ev["id"]
        locs = s.c.get_list(f"/v1/appEvents/{eid}/localizations")
        loc = next((l for l in locs if attr(l, "locale") == LOCALE), None)
        loc = s.c.upsert("appEventLocalizations", loc, dict(loc_cfg) if loc else {**loc_cfg, "locale": LOCALE},
                         {"appEvent": rel("appEvents", eid)}, label=f"    localization {LOCALE}",
                         refetch=lambda: next((l for l in s.c.get_list(f"/v1/appEvents/{eid}/localizations") if attr(l, "locale") == LOCALE), None))
        shots = s.c.get_list(f"/v1/appEventLocalizations/{loc['id']}/appEventScreenshots")
        for kind, asset_type in (("card", "EVENT_CARD"), ("details", "EVENT_DETAILS_PAGE")):
            path = EVENT_MEDIA / e["media"][kind]
            if not path.exists():
                missing_media.append(e["eventId"])
                continue
            s.upload_asset("appEventScreenshots", {"appEventLocalization": rel("appEventLocalizations", loc["id"])},
                           path, [x for x in shots if attr(x, "appEventAssetType") == asset_type],
                           extra={"appEventAssetType": asset_type})
    if missing_media:
        ids = " ".join(sorted(set(missing_media)))
        log(f"  media missing for {len(set(missing_media))} event(s): tools/store/make_app_events.py --media {ids}")
    log(f"  {len(todo)} event(s): the next {window} starting {EVENT_LEAD_DAYS}+ days from now and the next {primary} "
        "major holidays after them; nothing was submitted")
    return 0


PLATFORM_STEPS = """  App Store availability on Macs and Apple Vision Pro is not in the App Store Connect API. Once, by hand
  (role Account Holder, Admin or App Manager): App Store Connect > Apps > Carden > Pricing and
  Availability >
    - "iPhone and iPad Apps on Apple Silicon Mac": tick "Make this app available", Save
    - "iPhone and iPad Apps on Apple Vision Pro": tick "Make this app available", Save
  Both apply to every version. The build already allows it (SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD and
  SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD are Xcode's default YES; no UIRequiredDeviceCapabilities)."""


def cmd_platforms(s: Store) -> int:
    """Macs with Apple silicon ("Designed for iPhone") and Apple Vision Pro: the TestFlight side (every beta
    group offers iOS builds on both) is set here; App Store availability has no API and is printed as steps."""
    log("== Mac and Apple Vision Pro")
    for g in s.c.get_list(f"/v1/apps/{APP_ID}/betaGroups"):
        want = {"iosBuildsAvailableForAppleSiliconMac": True, "iosBuildsAvailableForAppleVision": True}
        s.c.upsert("betaGroups", g, want, label=f"  TestFlight group {attr(g, 'name')}")
    log(PLATFORM_STEPS)
    return 0


COMMANDS: dict[str, Callable[[Store], Any]] = {
    "events": cmd_events,
    "platforms": cmd_platforms,
    "app-info": cmd_app_info,
    "version": cmd_version,
    "age-rating": cmd_age_rating,
    "price-free": cmd_price_free,
    "screenshots": cmd_screenshots,
    "iap": cmd_iap,
    "subscriptions": cmd_subscriptions,
    "review-info": cmd_review_info,
    "testflight": cmd_testflight,
    "build-notes": cmd_build_notes,
    "release": cmd_release,
    "submit": cmd_submit,
    "draft": cmd_draft,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=[*COMMANDS, "status", "audit", "feedback", "all"],
                        help="`all` runs: " + ", ".join(ALL_ORDER))
    parser.add_argument("--dry-run", action="store_true", help="print every request instead of sending it")
    parser.add_argument("--verbose", "-v", action="store_true", help="also print GET requests")
    parser.add_argument("--categories", action="store_true", help="with `status`: list App Store category ids")
    parser.add_argument("--build", metavar="N", help="build number: `testflight` waits for it, `release` attaches it "
                        "(default: env ASC_BUILD_NUMBER, else the latest build)")
    parser.add_argument("--timeout", type=float, default=40, metavar="MIN", help="with `testflight --build`: minutes to wait for processing (default 40)")
    parser.add_argument("--whats-new-file", metavar="PATH", help="text for what's new (default: testflight_build_notes.txt for `testflight`, release_notes.txt for `release`); an empty file leaves it untouched")
    parser.add_argument("--version", metavar="X.Y.Z", help="with `release`: the App Store version (default: pubspec.yaml)")
    parser.add_argument("--auto-release", action="store_true", help="with `release`: go live automatically after approval (default: manual release)")
    parser.add_argument("--yes", action="store_true", help="with `submit`: really submit (without it only a preview is printed)")
    parser.add_argument("--resolve", metavar="ID[,ID]", help="with `feedback`: resolve these items (deletes them on Apple, records them locally)")
    parser.add_argument("--note", metavar="TEXT", help="with `feedback --resolve`: what was done about it")
    parser.add_argument("--events", action="store_true", help="with `draft`: also add the In-App Event drafts")
    parser.add_argument("--without-iap", action="store_true", help="with `submit`: proceed even if ready products are not in the submission")
    parser.add_argument("--window", type=int, metavar="N", help=f"with `events`: how many upcoming events to draft (default {EVENT_WINDOW})")
    parser.add_argument("--primary", type=int, metavar="N", help=f"with `events`: how many major holidays after the window to draft too (default {EVENT_PRIMARY})")
    args = parser.parse_args(argv)

    client = Client(dry_run=args.dry_run, verbose=args.verbose)
    store = Store(client, args)
    if args.dry_run:
        log(f"dry run: nothing is sent. Issuer ID loaded, key {KEY_ID}, app {APP_ID} ({BUNDLE_ID})")
    global LOCALE
    try:
        app = store.app()
        if app and attr(app, "primaryLocale"):
            LOCALE = attr(app, "primaryLocale")
        elif not args.dry_run:
            sys.exit(f"could not read app {APP_ID}; check the key, the Issuer ID and the key's role")
        log(f"locale: {LOCALE} (metadata read from store/metadata/en-US)")
        if args.command == "status":
            cmd_status(store, categories=args.categories)
        elif args.command == "audit":
            return cmd_audit(store)
        elif args.command == "feedback":
            return cmd_feedback(store)
        elif args.command == "all":
            for name in ALL_ORDER:
                COMMANDS[name](store)
        else:
            rc = COMMANDS[args.command](store)
            return int(rc or 0)
    except ApiError as err:
        log(f"error: {err}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
