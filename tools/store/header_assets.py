#!/usr/bin/env python3
"""Header and search-result art for Carden's product pages (App Store "Header and Search Results", iOS 27+).

    .venv/bin/python tools/store/header_assets.py compose [PAGE ...]    # art -> store/custom/header/<page>/
    .venv/bin/python tools/store/header_assets.py preview [PAGE ...]    # safe areas and real-size checks -> .../preview/
    .venv/bin/python tools/store/header_assets.py list [PAGE ...]       # what is placed on Apple now
    .venv/bin/python tools/store/header_assets.py plan [PAGE ...]       # what `upload` would do (reads Apple only)
    .venv/bin/python tools/store/header_assets.py upload [PAGE ...] --yes [--header 16x9|21x9]

PAGE is `default` (the editable App Store version's product page) or a custom page slug
(store/metadata/custom_pages/<slug>.json). Files per page, all PNG without alpha:

    header-5244x2950.png   16:9  Apple's "universal" size: the header (and it could also serve as the search result)
    header-3840x1646.png   21:9  the header-only size, an alternative to the 16:9 (a page holds one header)
    search-3840x2560.png   3:2   the search result (the largest size Apple takes)

The header is brand key art: the lotus mark and one short line in Apple's art safe area, framed by real pack
pictures as cards, real joined groups lifted from a board and the lotus-glass panes of the store slides. The
21:9 header is the same scene rendered for its own safe area (never scaled from another file). The search
result shows the app: a real capture in the slides' phone frame and the page's headline, as Apple advises
("state the obvious, show the experience"). What each page shows: store/metadata/custom_pages/header_assets.json.
Safe areas come from Apple's templates (developer.apple.com/app-store/asset-best-practices, "Art Safe Area").

`upload` uses the App Asset Library (App Store Connect API 4.5): it uploads each image (category
CREATIVE_ASSETS) and places one PRODUCT_PAGE_HEADER_ASSET and one APP_STORE_SEARCH_RESULTS_ASSET on the page's
en-GB localization: the default page on the editable App Store version, a custom page on its draft version.
A placement whose file is unchanged is kept; a changed one is replaced. It never submits anything for review
and does nothing without --yes. Research and specs: tools/store/custom-product-pages.md.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compose_glass as cg  # noqa: E402  (glass tones, covers, captures, board boxes, Chrome, fonts)
import compose_screenshots as cs  # noqa: E402  (phone frame and status bar)

ROOT = cg.ROOT
CFG = ROOT / "store" / "metadata" / "custom_pages" / "header_assets.json"
OUT = ROOT / "store" / "custom" / "header"
BUILD = ROOT / "build" / "store-header"
TEMPLATE = Path(__file__).resolve().parent / "glass" / "header.html"
MARK = ROOT / "tools" / "brand" / "out" / "carden-icon-light-1024.png"
FONT_FILE, WEIGHT, TRACK = cg.FONTS["rounded"]

# Apple's art safe areas (x0, y0, x1, y1), measured from the "Art Safe Area" layer of Apple's Photoshop
# templates (creative_assets-*_template-static.psd, October 2026). Only this part is sure to show everywhere.
SAFE = {
    "header-5244x2950": (1921, 660, 3323, 1622),
    "header-3840x1646": (1097, 493, 2743, 1154),
    "search-3840x2560": (836, 765, 3004, 1795),
}
SIZES = {"header-5244x2950": (5244, 2950), "header-3840x1646": (3840, 1646), "search-3840x2560": (3840, 2560)}
PLACEMENT = {"header-5244x2950": "PRODUCT_PAGE_HEADER_ASSET", "header-3840x1646": "PRODUCT_PAGE_HEADER_ASSET",
             "search-3840x2560": "APP_STORE_SEARCH_RESULTS_ASSET"}
SPEC = {"header-5244x2950": "c8f4e2b1-7a3d-5c9e-8b6f-2d1a0e9c8b7a", "header-3840x1646": "1eb43b80-e0b7-4d96-bd32-47a42a8c5fed",
        "search-3840x2560": "d2ffa3b7-6c55-5cdf-8512-229d92791333"}
MW, MH = SIZES["header-5244x2950"]
SAFE_CX = (SAFE["header-5244x2950"][0] + SAFE["header-5244x2950"][2]) / 2
SAFE_CY = (SAFE["header-5244x2950"][1] + SAFE["header-5244x2950"][3]) / 2
INK = (0x11, 0x11, 0x18)
MIN_CONTRAST = 4.5


def log(msg: str) -> None:
    print(msg, flush=True)


def load_cfg() -> dict:
    return json.loads(CFG.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------------------------

def head_font(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT_FILE, size)
    try:
        f.set_variation_by_axes([400, WEIGHT])
    except Exception:
        pass
    return f


def text_width(line: str, size: int) -> float:
    return head_font(size).getlength(line) * (1 + TRACK)


def fit_size(lines: list[str], max_w: float, max_size: int) -> int:
    widest = max(text_width(l, 100) for l in lines) / 100
    return min(max_size, int(max_w / widest))


def phone_png(parts: Path, capture: str, width: int) -> tuple[str, int]:
    n = cg.capture(capture, False)
    f = f"phone-{n}-{width}.png"
    if not (parts / f).exists():
        cs.phone(cs.load_raw(n), width, (240, 240, 244)).save(parts / f)
    return f, Image.open(parts / f).height


def screen_map(width: int) -> tuple[float, float]:
    """Where a capture sits inside a phone frame of this width: offset, scale (as compose_glass.phone_screen)."""
    band, bezel = round(width * 0.011), round(width * 0.026)
    return band + bezel, (width - 2 * (band + bezel)) / cs.RAW_W


def crop_png(parts: Path, capture: str, box, name: str) -> tuple[str, tuple]:
    n = cg.capture(capture, False)
    if box == "board":
        box = cg.board(n)
    elif isinstance(box, dict):
        box = cg.cell(capture, *box["cell"]) if "cell" in box else cg.board_part(capture, *box["part"])
    box = tuple(box)
    cs.load_raw(n).crop(box).save(parts / name)
    return name, box


def picture_srcs(page: dict, parts: Path, width: int) -> list[str]:
    srcs = []  # crops from captures first (they take the inner places), then pack covers
    for m, (cap, box) in enumerate(page.get("crops", [])):
        f, _ = crop_png(parts, cap, box, f"pic-{m}.png")
        srcs.append(str(parts / f))
    return srcs + [cg.cover(pid, width) for pid in page.get("covers", [])]


def glass_panes(spec: list[tuple]) -> list[dict]:
    return [{"x": x, "y": y, "w": w, "h": h, "rx": rx, "r": r, "c": c} for x, y, w, h, rx, r, c in spec]


def base_scene(w: int, h: int, unit: float, parts: Path) -> dict:
    return {"W": w, "H": h, "unit": unit, "parts": str(parts), "glass": cg.glass_tones(), "body": cg.BODY_OPACITY,
            "shadow": cg.SHADOW_OPACITY, "pics": [], "phones": [], "cards": [], "panes": [], "mark": None, "text": None,
            "font": {"weight": WEIGHT, "track": TRACK}}


# ---------------------------------------------------------------------------------------------
# The header: brand key art (master at 5244 x 2950)
# ---------------------------------------------------------------------------------------------

def header_scene(page: dict, parts: Path) -> dict:
    """The lotus mark and one short line in the middle of Apple's safe area, real pictures fanned on both sides
    like two hands of cards rising towards it, a real joined group of cards lifted on each side, big glass panes
    behind. The middle stays white so the mark and the line read on it."""
    s = base_scene(MW, MH, 1.6, parts)
    s["panes"] = glass_panes([
        (-560, -380, 2050, 1700, 210, 10, "blue"),
        (-420, 1500, 1750, 1800, 200, -9, "gold"),
        (1500, 2050, 1150, 1100, 160, 8, "teal"),
        (2700, -760, 1200, 1050, 160, -12, "gold"),
        (3700, -420, 2100, 1750, 210, -10, "pink"),
        (3900, 1580, 1800, 1700, 200, 9, "teal"),
    ])
    srcs = picture_srcs(page, parts, 1400)
    pw, ph = page.get("pic", [700, 930])
    radius = round(30 * 1.6)
    # Four cards a side, from the outer edge in: each a little higher, larger and straighter than the last.
    left = [(260, 1880, -16, .94), (900, 1530, -11, 1.0), (1450, 1290, -6, .9)]
    right = [(MW - x, y, -r, k) for x, y, r, k in left]
    spots = [*left, *right]
    order = [0, 1, 2, 5, 4, 3]  # left outer..inner, right inner..outer (pictures fill in that order)
    pics = []
    for i, si in enumerate(order):
        x, y, r, k = spots[si]
        src = srcs[i % len(srcs)]
        w, h = round(pw * k), round(ph * k)
        pics.append({"src": src, "x": round(x - w / 2), "y": round(y - h / 2), "w": w, "h": h, "r": r, "radius": radius})
    # Two more along the top edge and two along the bottom, so the art runs to every edge on wide screens.
    extra = [(1760, 140, 7, .8), (MW - 1760, 140, -7, .8), (2050, 2700, -5, .86), (MW - 2050, 2700, 5, .86)]
    for j, (x, y, r, k) in enumerate(extra):
        src = srcs[(len(order) + j) % len(srcs)]
        w, h = round(pw * k), round(ph * k)
        pics.append({"src": src, "x": round(x - w / 2), "y": round(y - h / 2), "w": w, "h": h, "r": r, "radius": radius})
    s["pics"] = pics
    # Real cards from a board, lifted: a joined group on each side, cut exactly at the group's edges.
    for j, o in enumerate(page.get("lift", [])):
        cap, bx = page["_groups"][o["group"]] if "group" in o else (o["capture"], o["box"])
        f, box = crop_png(parts, cap, bx, f"lift-{j}.png")
        s["cards"].append({"img": f, "x": o["x"], "y": o["y"], "w": o["w"], "rot": o.get("rot", 0),
                           "radius": round(o.get("radius", 26) * o["w"] / (box[2] - box[0]))})
    # The mark and the line, centred in the safe area.
    line = page.get("headerLine", "Your calm picture puzzle")
    size = fit_size([line], (SAFE["header-5244x2950"][2] - SAFE["header-5244x2950"][0]) - 120, 132)
    mark_w = 560
    block = mark_w * .86 + 70 + size * 1.06  # the lotus fills about 86% of its square
    top = SAFE_CY - block / 2
    s["mark"] = {"src": str(MARK), "x": round(SAFE_CX - mark_w / 2), "y": round(top - mark_w * .07), "w": mark_w}
    s["text"] = {"lines": [line], "x": SAFE_CX, "y": round(top + mark_w * .86 + 70), "size": size, "align": "center"}
    return s


# ---------------------------------------------------------------------------------------------
# The search result: the app, stated plainly (3840 x 2560)
# ---------------------------------------------------------------------------------------------

def search_scene(page: dict, parts: Path) -> dict:
    """The page's headline on the left of the safe area, the real app on the right (a phone with a board or
    screen mid-use, its top in the safe area), one lifted card, a few real pictures behind, glass panes."""
    W, H = SIZES["search-3840x2560"]
    x0, y0, x1, y1 = SAFE["search-3840x2560"]
    s = base_scene(W, H, 1.15, parts)
    s["panes"] = glass_panes([
        (-420, -300, 1500, 1250, 170, 9, "blue"),
        (-300, 1650, 1450, 1300, 160, -8, "gold"),
        (2900, -380, 1300, 1250, 170, -10, "pink"),
        (3000, 1700, 1200, 1150, 160, 9, "teal"),
        (1500, 2200, 900, 700, 120, -6, "pink"),
    ])
    pw = 1150
    img, ph = phone_png(parts, page["phone"], pw)
    off, k = screen_map(pw)
    focus = page.get("focusY", 499)  # capture y that should sit at the top of the safe area (the board's top)
    py = round(y0 - 60 - (off + focus * k))
    # The headline as big as the room allows (about 22 px tall in a 384 px wide check): the phone moves right
    # to make room, but never further than 2500 (its frame stays on the card).
    lines = page["searchLine"].split("\n")
    want = max(text_width(l, 230) for l in lines)
    px = round(min(2500, max(x1 - pw + 260, x0 + want + 110)))
    srcs = picture_srcs(page, parts, 1000)
    pics = []
    if srcs:  # two pictures peeking out behind the phone on the right
        for i, (dx, dy, r) in enumerate([(860, 380, 9), (980, 1350, -7)]):
            pics.append({"src": srcs[(i + 1) % len(srcs)], "x": px + dx, "y": dy, "w": 640, "h": 850, "r": r, "radius": 34})
    s["pics"] = pics
    outs = []
    for j, o in enumerate(page.get("searchLift", [])):
        cap, bx = page["_groups"][o["group"]] if "group" in o else (o["capture"], o["box"])
        f, box = crop_png(parts, cap, bx, f"slift-{j}.png")
        w = o["w"]
        outs.append({"img": f, "x": o.get("x", round(off + (box[0] + box[2]) / 2 * k - w / 2)),
                     "y": o.get("y", round(off + (box[1] + box[3]) / 2 * k - w * (box[3] - box[1]) / (box[2] - box[0]) / 2)),
                     "w": w, "rot": o.get("rot", 0), "radius": round(o.get("radius", 26) * w / (box[2] - box[0]))})
    s["phones"] = [{"img": img, "x": px, "y": py, "w": pw, "h": ph, "rot": page.get("rot", 4), "out": outs}]
    room = (px - 90) - x0  # from the safe area's left edge to the phone
    size = fit_size(lines, room, 230)
    block = len(lines) * size * 1.06
    s["text"] = {"lines": lines, "x": x0, "y": round((y0 + y1) / 2 - block / 2), "size": size, "align": "left"}
    return s


# ---------------------------------------------------------------------------------------------
# Rendering and checks
# ---------------------------------------------------------------------------------------------

def write_page(scene: dict, path: Path, view: tuple | None = None) -> None:
    """The template filled with the scene. A view (x, y, scale) moves and scales the canvas so the window
    shows exactly that part at the output's own resolution."""
    html = TEMPLATE.read_text().replace("__DATA__", json.dumps(scene)).replace("__FONT__", FONT_FILE)
    if view:
        x, y, sc = view
        html = html.replace('<div id="root"></div>', f'<div id="root" style="transform-origin:0 0;transform:scale({sc}) translate({-x}px,{-y}px)"></div>')
    path.write_text(html)


def render(page_html: Path, w: int, h: int, out: Path, notext: bool = False) -> None:
    with tempfile.TemporaryDirectory() as d:
        shot = Path(d) / "shot.png"
        args = [cg.chrome(), "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                f"--window-size={w},{h + 200}", "--force-device-scale-factor=1", "--virtual-time-budget=15000",
                f"--screenshot={shot}", f"file://{page_html}" + ("#notext" if notext else "")]
        if "headless-shell" not in args[0]:
            args.insert(1, "--headless=new")
        subprocess.run(args, check=True, capture_output=True)
        Image.open(shot).convert("RGB").crop((0, 0, w, h)).save(out, "PNG", optimize=True)


def text_boxes(scene: dict, view: tuple | None) -> list[tuple]:
    """Output-pixel boxes of each headline line (for the contrast check)."""
    T = scene.get("text")
    if not T:
        return []
    vx, vy, sc = view or (0, 0, 1)
    out = []
    for i, line in enumerate(T["lines"]):
        w = text_width(line, T["size"])
        x = T["x"] - w / 2 if T["align"] == "center" else T["x"] if T["align"] == "left" else T["x"] - w
        y = T["y"] + i * T["size"] * 1.06 + T["size"] * .12
        out.append(((x - vx) * sc, (y - vy) * sc, (x + w - vx) * sc, (y + T["size"] * .86 - vy) * sc))
    return out


def contrast(bg: Image.Image, boxes: list[tuple]) -> float:
    import numpy as np
    arr = np.asarray(bg.convert("RGB"))
    li = cg.luminance(INK) + .05
    worst = 99.0
    for x0, y0, x1, y1 in boxes:
        part = arr[max(0, int(y0)):int(y1), max(0, int(x0)):int(x1)]
        lum = cg.luminance(part).ravel()
        worst = min(worst, (float(np.percentile(lum, 2)) + .05) / li)
    return round(worst, 2)


def compose(slug: str, page: dict) -> dict:
    build = BUILD / slug
    parts = build / "parts"
    parts.mkdir(parents=True, exist_ok=True)
    for f in parts.glob("*.png"):
        f.unlink()
    out_dir = OUT / slug
    out_dir.mkdir(parents=True, exist_ok=True)
    head = header_scene(page, parts)
    search = search_scene(page, parts)
    # The 21:9 header: the master moved so the master's safe-area centre lands on the 21:9 safe-area centre.
    hx0, hy0, hx1, hy1 = SAFE["header-3840x1646"]
    sc21 = 3840 / MW
    view21 = (0, SAFE_CY - (hy0 + hy1) / 2 / sc21, sc21)
    jobs = [("header-5244x2950", head, None), ("header-3840x1646", head, view21), ("search-3840x2560", search, None)]
    report = {}
    for name, scene, view in jobs:
        w, h = SIZES[name]
        html = build / f"{name}.html"
        write_page(scene, html, view)
        out = out_dir / f"{name}.png"
        render(html, w, h, out)
        im = Image.open(out)
        assert im.size == (w, h) and im.mode == "RGB", (out, im.size, im.mode)
        c = None
        if scene.get("text"):
            with tempfile.TemporaryDirectory() as d:
                bare = Path(d) / "bare.png"
                render(html, w, h, bare, notext=True)
                c = contrast(Image.open(bare), text_boxes(scene, view))
        report[name] = c
        flag = "" if c is None else f"  contrast {c:.2f} {'ok' if c >= MIN_CONTRAST else 'LOW'}"
        log(f"  {out.relative_to(ROOT)}  {w}x{h}  {out.stat().st_size // 1024} KB{flag}")
    return report


def preview(slug: str) -> list[Path]:
    """For each file: Apple's safe area drawn on it, and the file at the size people see it (the search card
    about 365 pt wide on an iPhone, the 384 px check; the header across an iPhone and an iPad)."""
    src = OUT / slug
    pdir = src / "preview"
    pdir.mkdir(parents=True, exist_ok=True)
    made = []
    for name in SIZES:
        f = src / f"{name}.png"
        if not f.exists():
            continue
        im = Image.open(f).convert("RGB")
        ov = im.copy()
        d = ImageDraw.Draw(ov, "RGBA")
        x0, y0, x1, y1 = SAFE[name]
        d.rectangle((0, 0, im.width, y0), fill=(0, 0, 0, 70))
        d.rectangle((0, y1, im.width, im.height), fill=(0, 0, 0, 70))
        d.rectangle((0, y0, x0, y1), fill=(0, 0, 0, 70))
        d.rectangle((x1, y0, im.width, y1), fill=(0, 0, 0, 70))
        d.rectangle((x0, y0, x1, y1), outline=(0, 200, 80, 255), width=max(4, im.width // 600))
        ov.thumbnail((1600, 1600))
        p = pdir / f"{name}-safe-area.png"
        ov.save(p)
        made.append(p)
        if name.startswith("search"):
            for wpt, label in ((1095, "iphone-365pt@3x"), (384, "384px")):
                t = im.resize((wpt, round(wpt * im.height / im.width)), Image.LANCZOS)
                p = pdir / f"{name}-{label}.png"
                t.save(p)
                made.append(p)
        else:
            for wpx, label in ((1320, "iphone-440pt@3x"), (2064, "ipad-13in-1032pt@2x")):
                t = im.resize((wpx, round(wpx * im.height / im.width)), Image.LANCZOS)
                p = pdir / f"{name}-{label}.png"
                t.save(p)
                made.append(p)
            # The safe area alone, as wide as an iPhone screen: the part that shows on every device.
            sa = im.crop(SAFE[name])
            sa = sa.resize((1320, round(1320 * sa.height / sa.width)), Image.LANCZOS)
            p = pdir / f"{name}-safe-area-only-iphone.png"
            sa.save(p)
            made.append(p)
    return made


# ---------------------------------------------------------------------------------------------
# App Store Connect (App Asset Library)
# ---------------------------------------------------------------------------------------------

def asc():
    import asc_publish as ap
    return ap


class Placer:
    """Finds each page's localization and its header / search placements; uploads and places images."""

    def __init__(self, client, store, dry: bool):
        self.ap = asc()
        self.c, self.s, self.dry = client, store, dry

    def localization(self, slug: str) -> tuple[str, str] | None:
        """(relationship type, localization id) of the page's editable en-GB localization."""
        ap = self.ap
        if slug == "default":
            version = self.s.editable_version()
            if version is None:
                log("  no editable App Store version: a live version's art is changed in App Store Connect (Browse Assets)")
                return None
            loc = self.s.version_localization(version)
            if loc is None:
                log(f"  version {ap.attr(version, 'versionString')} has no {ap.LOCALE} localization")
                return None
            log(f"  App Store version {ap.attr(version, 'versionString')} ({ap.version_state(version)}), {ap.LOCALE}")
            return "appStoreVersionLocalizations", loc["id"]
        apple = json.loads((ROOT / "store" / "metadata" / "custom_pages" / "apple.json").read_text())
        page = apple.get(slug)
        if not page:
            log(f"  custom page {slug} is not on Apple yet (run custom_pages.py sync)")
            return None
        versions = self.c.get_list(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions", limit=50)
        versions.sort(key=lambda v: int(ap.attr(v, "version") or 0))
        draft = versions[-1] if versions else None
        if ap.attr(draft, "state") not in ("PREPARE_FOR_SUBMISSION", "REJECTED"):
            log(f"  custom page {slug}: latest version is {ap.attr(draft, 'state')}; art goes on a draft version only")
            return None
        locs = self.c.get_list(f"/v1/appCustomProductPageVersions/{draft['id']}/appCustomProductPageLocalizations", limit=50)
        loc = next((l for l in locs if ap.attr(l, "locale") == ap.LOCALE), None)
        if loc is None:
            log(f"  custom page {slug} has no {ap.LOCALE} localization")
            return None
        log(f"  custom page {page['name']} (version {ap.attr(draft, 'version')}, draft), {ap.LOCALE}")
        return "appCustomProductPageLocalizations", loc["id"]

    def placements(self, rel_type: str, loc_id: str) -> dict[str, tuple[dict, dict | None]]:
        """placement type -> (placement, its image) for the header and search slots."""
        resp = self.c.request("GET", f"/v1/{rel_type}/{loc_id}/placements",
                              params={"include": "image", "limit": 50,
                                      "filter[placementType]": "PRODUCT_PAGE_HEADER_ASSET,APP_STORE_SEARCH_RESULTS_ASSET"}) or {}
        images = {i["id"]: i for i in resp.get("included") or [] if i.get("type") == "appAssetLibraryImages"}
        out = {}
        for p in resp.get("data") or []:
            img_id = ((((p.get("relationships") or {}).get("image") or {}).get("data")) or {}).get("id")
            out[self.ap.attr(p, "placementType")] = (p, images.get(img_id))
        return out

    def upload_image(self, path: Path, reference: str, file_name: str) -> dict:
        ap = self.ap
        lib = self.c.get_one(f"/v1/apps/{ap.APP_ID}/assetLibrary")
        lib_id = (lib or {}).get("id", ap.APP_ID)
        size = path.stat().st_size
        log(f"    uploading {path.relative_to(ROOT)} ({size // 1024} KB) as {reference}")
        img = self.c.create("appAssetLibraryImages", {"fileName": file_name, "fileSize": size,
                                                      "category": "CREATIVE_ASSETS", "referenceName": reference},
                            {"assetLibrary": ap.rel("appAssetLibraries", lib_id)})
        if self.dry:
            return img
        data = path.read_bytes()
        for op in ap.attr(img, "uploadOperations") or []:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            self.c.request(op.get("method", "PUT"), op["url"], raw=chunk, headers=headers)
        self.c.update("appAssetLibraryImages", img["id"], {"uploaded": True})
        for _ in range(60):  # Apple checks the file; wait until it can be placed
            cur = self.c.get_one(f"/v1/appAssetLibraryImages/{img['id']}") or {}
            state = ap.attr(cur, "state")
            if state == "FAILED":
                raise RuntimeError(f"{path.name}: Apple refused the file: {ap.attr(cur, 'stateDetails')}")
            if state not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE", "PROCESSING", None):
                log(f"    {path.name}: {state}, spec {ap.attr(cur, 'specId')}")
                return cur
            time.sleep(5)
        raise RuntimeError(f"{path.name}: still processing after 5 minutes; run upload again later")

    def place(self, slug: str, header: str) -> None:
        ap = self.ap
        target = self.localization(slug)
        if target is None:
            return
        rel_type, loc_id = target
        existing = self.placements(rel_type, loc_id)
        files = {"PRODUCT_PAGE_HEADER_ASSET": {"16x9": "header-5244x2950", "21x9": "header-3840x1646"}[header],
                 "APP_STORE_SEARCH_RESULTS_ASSET": "search-3840x2560"}
        for ptype, name in files.items():
            path = OUT / slug / f"{name}.png"
            if not path.exists():
                log(f"  {ptype}: {path.relative_to(ROOT)} is missing; run compose first")
                continue
            # The asset library refuses a reference name it already holds, so each file's name carries a
            # short hash of its content: a changed file is a new image, an unchanged one is recognised.
            reference = f"Carden {slug} {name} {ap.md5_of(path)[:8]}"
            placement, image = existing.get(ptype) or (None, None)
            if image and (ap.attr(image, "referenceName") == reference or (  # names from before the hash
                    ap.attr(image, "referenceName") == f"Carden {slug} {name}" and ap.attr(image, "fileSize") == path.stat().st_size)):
                log(f"  {ptype}: {ap.attr(image, 'referenceName')} already placed ({ap.attr(placement, 'state')})")
                continue
            # Upload first: a file Apple refuses never leaves the page without art.
            img = self.upload_image(path, reference, f"carden-{slug}-{path.name}")
            if placement:
                log(f"  {ptype}: replacing {ap.attr(image, 'referenceName') if image else 'an image'}")
                self.c.request("DELETE", f"/v1/appAssetLibraryPlacements/{placement['id']}")
                if image and not self.dry:
                    try:  # the old image is placed nowhere now; keep the library tidy
                        self.c.request("DELETE", f"/v1/appAssetLibraryImages/{image['id']}")
                    except ap.ApiError as err:
                        log(f"    old image {ap.attr(image, 'referenceName')} kept in the library ({err.status})")
            log(f"  {ptype}: placing {reference}")
            self.c.create("appAssetLibraryPlacements", {"placementType": ptype, "placementGroup": "DEFAULT_PROFILE"},
                          {"image": ap.rel("appAssetLibraryImages", img.get("id", "DRY-image")),
                           rel_type[:-1]: ap.rel(rel_type, loc_id)})

    def describe(self, slug: str) -> None:
        ap = self.ap
        target = self.localization(slug)
        if target is None:
            return
        found = self.placements(*target)
        for ptype in ("PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"):
            p, img = found.get(ptype, (None, None))
            if p is None:
                log(f"    {ptype}: none")
            else:
                size = (ap.attr(img, "imageAsset") or {})
                log(f"    {ptype}: {ap.attr(img, 'referenceName')} {size.get('width')}x{size.get('height')} "
                    f"(placement {ap.attr(p, 'state')}, image {ap.attr(img, 'state')})")


class PlanClient:
    """Wraps asc_publish.Client: reads go to Apple, writes are printed."""

    def __init__(self, client):
        self.inner = client
        self.n = 0

    def __getattr__(self, name):
        return getattr(self.inner, name)

    def request(self, method, path, body=None, params=None, raw=None, headers=None, allow_404=False):
        if method == "GET":
            return self.inner.request(method, path, body, params, raw, headers, allow_404)
        self.n += 1
        log(f"    [plan] {method} {path if raw is None else '<upload>'}" + (f"  {json.dumps(body)[:300]}" if body else ""))
        data = dict((body or {}).get("data") or {})
        data.setdefault("id", f"DRY-{self.n}")
        return {"data": data}

    def get_list(self, path, params=None, limit=200):
        return self.inner.get_list(path, params, limit)

    def get_one(self, path, params=None):
        return self.inner.get_one(path, params)

    def create(self, type_, attributes=None, relationships=None, included=None, path=None):
        body = {"data": {"type": type_, **({"attributes": attributes} if attributes else {}),
                         **({"relationships": relationships} if relationships else {})}}
        return (self.request("POST", path or f"/v1/{type_}", body) or {}).get("data") or {}

    def update(self, type_, id_, attributes=None, relationships=None, path=None):
        return (self.request("PATCH", path or f"/v1/{type_}/{id_}", {"data": {"type": type_, "id": id_, "attributes": attributes}}) or {}).get("data") or {}


def main(argv: list[str] | None = None) -> int:
    ap_ = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap_.add_argument("command", choices=["compose", "preview", "list", "plan", "upload"])
    ap_.add_argument("pages", nargs="*")
    ap_.add_argument("--header", choices=["16x9", "21x9"], default="16x9", help="which header file to place (default: the 16:9 universal)")
    ap_.add_argument("--yes", action="store_true", help="with upload: really upload and place")
    args = ap_.parse_args(argv)
    cfg = load_cfg()
    pages = args.pages or list(cfg["pages"])
    unknown = [p for p in pages if p not in cfg["pages"]]
    if unknown:
        sys.exit(f"no art defined for: {', '.join(unknown)} ({CFG.relative_to(ROOT)})")

    if args.command == "compose":
        low = 0
        for slug in pages:
            log(f"== {slug}")
            rep = compose(slug, {**cfg["pages"][slug], "_groups": cfg.get("groups", {})})
            low += sum(1 for c in rep.values() if c is not None and c < MIN_CONTRAST)
        return 1 if low else 0
    if args.command == "preview":
        for slug in pages:
            for p in preview(slug):
                log(f"  {p.relative_to(ROOT)}")
        return 0

    ap = asc()
    if args.command == "upload" and not args.yes:
        sys.exit("upload changes App Store Connect: run `plan` first, then `upload --yes` (nothing is ever submitted for review)")
    client = ap.Client(dry_run=False, verbose=False)
    store = ap.Store(client, args)
    app = store.app()
    ap.LOCALE = ap.attr(app, "primaryLocale") or ap.LOCALE
    dry = args.command in ("plan", "list")
    placer = Placer(PlanClient(client) if dry else client, store, dry)
    try:
        for slug in pages:
            log(f"== {slug}")
            if args.command == "list":
                placer.describe(slug)
            else:
                placer.place(slug, args.header)
    except ap.ApiError as err:
        log(f"error: {err}")
        return 1
    if args.command == "upload":
        log("Placed as drafts on the page versions. Nothing was submitted for review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
