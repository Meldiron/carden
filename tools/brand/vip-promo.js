// VIP promotional images for the App Store (owner's pick, 2026-11-04, after the 2.0.0 rejection under
// Guideline 2.3.2): no text, one image per plan. A ring of six glass segments in the icon's material
// (tools/brand/icon-glass.js) around a picture under a glass dome, on the VIP ink.
//   Monthly: one segment in colour (the bud's pink), five clear; a silver glass rim.
//   Yearly:  all six segments in the icon's colours, a gold glass rim, a faint gold light behind.
// Usage: node tools/brand/vip-promo.js <monthly|yearly> <picture.jpg>   -> SVG (1024 x 1024) on stdout.
// tools/store/make_promo.py renders it to PNG.
const fs = require("fs");
const path = require("path");
const G = require(path.join(__dirname, "icon-glass.js"));

const [variant, picture] = process.argv.slice(2);
if (!["monthly", "yearly"].includes(variant) || !picture) {
  process.stderr.write("usage: node vip-promo.js <monthly|yearly> <picture.jpg>\n");
  process.exit(2);
}
const yearly = variant === "yearly";

const f2 = v => (+v).toFixed(2);
const rad = d => d * Math.PI / 180;
const at = (r, a) => [50 + r * Math.cos(rad(a)), 50 + r * Math.sin(rad(a))];

// An annular sector from angle a0 to a1 (degrees, clockwise, 0 = 3 o'clock), corners rounded by rc.
function sector(a0, a1, Ro, Ri, rc) {
  const dO = rc / Ro * 180 / Math.PI, dI = rc / Ri * 180 / Math.PI;
  const p = (r, a) => at(r, a).map(f2).join(" ");
  return `M${p(Ro - rc, a0)} Q${p(Ro, a0)} ${p(Ro, a0 + dO)} A${Ro} ${Ro} 0 0 1 ${p(Ro, a1 - dO)} ` +
    `Q${p(Ro, a1)} ${p(Ro - rc, a1)} L${p(Ri + rc, a1)} Q${p(Ri, a1)} ${p(Ri, a1 - dI)} ` +
    `A${Ri} ${Ri} 0 0 0 ${p(Ri, a0 + dI)} Q${p(Ri, a0)} ${p(Ri + rc, a0)} Z`;
}
// A ring: the outer circle clockwise, the inner one counter-clockwise, so the middle stays open.
const annulus = (ro, ri) => `M${f2(50 + ro)} 50 A${ro} ${ro} 0 1 1 ${f2(50 - ro)} 50 A${ro} ${ro} 0 1 1 ${f2(50 + ro)} 50 Z ` +
  `M${f2(50 + ri)} 50 A${ri} ${ri} 0 1 0 ${f2(50 - ri)} 50 A${ri} ${ri} 0 1 0 ${f2(50 + ri)} 50 Z`;

// The icon's palette, clockwise from 12 o'clock: pink (the bud), coral, gold (the left petal), green
// (the leaves), blue (the right petal), violet.
const COLOURS = [
  ["#FF9CC0", "#F0447C"],
  ["#FFB08A", "#F2643F"],
  ["#FFD45A", "#E39A00"],
  ["#7FE3C4", "#16A386"],
  ["#8CCBFF", "#2F86F2"],
  ["#B99BFF", "#6A50EE"],
];
const SILVER = ["#F7F8FB", "#8F98A6"];
const GOLD = ["#FFE38A", "#D98E00"];
const INK = "#16161C"; // Vip.ink, the VIP card

const C = G.makeCtx("dark");
const clear = G.makeCtx("clearD");
const parts = [];

// Six segments; the first starts at 12 o'clock.
const N = 6, gap = 7, Ro = 41, Ri = 28.5, rc = 3.2;
for (let k = 0; k < N; k++) {
  const d = sector(-90 + k * 360 / N + gap / 2, -90 + (k + 1) * 360 / N - gap / 2, Ro, Ri, rc);
  if (yearly || k === 0) parts.push(C.piece(d, COLOURS[k], { zone: 2.4, lift: 1.1, blur: 1.4 }));
  else parts.push(clear.piece(d, "#FFFFFF", { m: 0.13, zone: 2.0, lift: 0.5, blur: 1 }));
}

// The picture under a clear glass dome, in a silver or gold glass rim.
const Rp = 21;
const b64 = fs.readFileSync(picture).toString("base64");
parts.push(`<image href="data:image/jpeg;base64,${b64}" x="${50 - Rp}" y="${50 - Rp}" width="${2 * Rp}" height="${2 * Rp}" ` +
  `clip-path="url(#picture)" preserveAspectRatio="xMidYMid slice"/>`);
parts.push(clear.piece(G.circ(50, 50, Rp), "#FFFFFF", { m: 0.05, zone: 1.4, rim: 0.7, band: 0.6, lift: 0, blur: 0.1, grain: false, edge: 0.2 }));
parts.push(C.piece(annulus(Rp + 3.4, Rp - 0.2), yearly ? GOLD : SILVER, { zone: 1.6, rim: 0.9, lift: 0.9, blur: 1.2 }));

const glow = yearly
  ? `<radialGradient id="glow" cx="50" cy="50" r="50" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD45A" stop-opacity="0.16"/>` +
    `<stop offset="1" stop-color="#FFD45A" stop-opacity="0"/></radialGradient>`
  : "";
const defs = C.defs.join("") + clear.defs.join("") + glow + `<clipPath id="picture"><circle cx="50" cy="50" r="${Rp}"/></clipPath>`;
process.stdout.write(
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 100 100"><defs>${defs}</defs>` +
  `<rect width="100" height="100" fill="${INK}"/>` + (glow ? `<rect width="100" height="100" fill="url(#glow)"/>` : "") +
  // 90%: the App Store frames and rounds the image; the lower-left corner stays clear for the app icon it adds in search.
  `<g transform="translate(50 50) scale(0.9) translate(-50 -50)">${parts.join("")}</g></svg>`);
