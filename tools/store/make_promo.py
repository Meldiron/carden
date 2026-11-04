#!/usr/bin/env python3
"""Build the App Store Connect side assets:

  store/promo/app-icon-1024.png                  1024x1024 icon, RGB (no alpha)
  store/promo/vip-monthly-promotional-1024.png   VIP Monthly promotional image
  store/promo/vip-yearly-promotional-1024.png    VIP Yearly promotional image
  store/review/subscription-review.png           store screen showing the VIP card
  store/review/iap-review-boosters.png           store scrolled to Tickets and Boosters (ticket and booster products)

The promotional images (owner's pick, 2026-11-04) are drawn by tools/brand/vip-promo.js: a ring of six
glass segments in the icon's material around a picture, one image per plan and no text at all. App Review
rejected 2.0.0 under Guideline 2.3.2 for one image shared by both plans, small text and a price reference
("7 days free"); the apple-release skill has the rules. The pictures are catalogue pictures (CC0), cropped
to a square in store/promo/sources/ (PICTURES below).

Usage (repo root; Pillow, node and a Chromium as for tools/brand/export_icon.py):  python tools/store/make_promo.py
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/brand"))
from export_icon import render  # noqa: E402  (headless Chromium, drawn at 2048 px)

ICON_SRC = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
RAW_STORE_VIP = ROOT / "store/raw/12_store_vip.png"
RAW_STORE_BOOSTERS = ROOT / "store/raw/35_store_boosters_light.png"
PROMO = ROOT / "store/promo"
REVIEW = ROOT / "store/review"
VIP_PROMO_JS = ROOT / "tools/brand/vip-promo.js"

# The picture in each plan's ring: a square crop of a catalogue picture (puzzle id, its licence).
PICTURES = {
    "monthly": ("sources/vip-monthly-iceberg.jpg", "p-3fa6fc2a393c, Iceberg wall, Travel Photographer, stocksnap, CC0"),
    "yearly": ("sources/vip-yearly-balloon.jpg", "evpack-happiness-2027-14, Hot air balloon, rawpixel, CC0"),
}


def app_icon_no_alpha() -> Image.Image:
    icon = Image.open(ICON_SRC).convert("RGBA")
    flat = Image.new("RGB", icon.size, (255, 255, 255))
    flat.paste(icon, mask=icon.getchannel("A"))
    return flat


def vip_promo(variant: str) -> Image.Image:
    picture, _credit = PICTURES[variant]
    svg = subprocess.run(["node", str(VIP_PROMO_JS), variant, str(PROMO / picture)], check=True, capture_output=True,
                         text=True).stdout
    with tempfile.TemporaryDirectory() as d:
        drawn = render(svg, Path(d) / "promo.png")
    # Apple wants 1024 x 1024, RGB, flattened (no alpha).
    return drawn.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    PROMO.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)

    icon = app_icon_no_alpha()
    icon.save(PROMO / "app-icon-1024.png", "PNG", optimize=True)
    print("wrote store/promo/app-icon-1024.png", icon.size, icon.mode)

    for variant in PICTURES:
        promo = vip_promo(variant)
        out = PROMO / f"vip-{variant}-promotional-1024.png"
        promo.save(out, "PNG", optimize=True)
        print(f"wrote {out.relative_to(ROOT)}", promo.size, promo.mode)

    if RAW_STORE_VIP.exists():
        shot = Image.open(RAW_STORE_VIP).convert("RGB")
        shot.save(REVIEW / "subscription-review.png", "PNG", optimize=True)
        print("wrote store/review/subscription-review.png", shot.size, shot.mode)
    else:
        print("skipped subscription-review.png: store/raw/12_store_vip.png missing")

    # The App Review screenshot of the ticket and booster products (consumables.json names it).
    if RAW_STORE_BOOSTERS.exists():
        shot = Image.open(RAW_STORE_BOOSTERS).convert("RGB")
        shot.save(REVIEW / "iap-review-boosters.png", "PNG", optimize=True)
        print("wrote store/review/iap-review-boosters.png", shot.size, shot.mode)
    else:
        print("skipped iap-review-boosters.png: store/raw/35_store_boosters_light.png missing")


if __name__ == "__main__":
    main()
