// Carden app icon: the drawing and its coloured-glass material (owner's final pick, 2026-10-15: id "FV1",
// the dawn lotus with the deep-gold petal). Every drawing sits on a 100 x 100 artboard; iOS rounds the corners.
// tools/brand/export_icon.py renders it into every icon file the app ships. The other ids are the design
// rounds' alternatives, kept so the review page can be rebuilt.
// Every drawing sits on a 100 x 100 artboard; iOS rounds the corners itself.
(function () {
const hexRgb = h => { h = h.replace("#", ""); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)); };
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
const rgb = (c, a = 1) => a >= 1 ? `rgb(${c.join(",")})` : `rgba(${c.join(",")},${(+a).toFixed(3)})`;
const WHITE = [255, 255, 255], BLACK = [0, 0, 0];
const DARKISH = new Set(["dark", "clearD", "tintD"]);
let UID = 0; const uid = () => "x" + (++UID).toString(36);
const f2 = v => (+v).toFixed(2);

// ---- geometry helpers
// A rounded polygon: corners rounded with radius r[i], edges optionally bowed by bulge[i] (positive = outward).
function roundPoly(pts, r, bulge) {
  const n = pts.length, R = Array.isArray(r) ? r : pts.map(() => r), B = bulge || pts.map(() => 0);
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]], len = v => Math.hypot(v[0], v[1]), add = (a, b) => [a[0] + b[0], a[1] + b[1]], mul = (v, k) => [v[0] * k, v[1] * k];
  const unit = v => mul(v, 1 / len(v));
  const corner = i => { const P = pts[i], A = pts[(i - 1 + n) % n], Cc = pts[(i + 1) % n];
    const v1 = unit(sub(A, P)), v2 = unit(sub(Cc, P)), ri = Math.min(R[i], len(sub(A, P)) / 2.2, len(sub(Cc, P)) / 2.2);
    return { a: add(P, mul(v1, ri)), b: add(P, mul(v2, ri)), P }; };
  const cs = pts.map((_, i) => corner(i));
  let d = `M${f2(cs[0].b[0])} ${f2(cs[0].b[1])}`;
  for (let k = 1; k <= n; k++) {
    const i = k % n, prev = cs[k - 1], cur = cs[i], bul = B[k - 1];
    if (bul) { const m = mul(add(prev.b, cur.a), .5), e = sub(cur.a, prev.b), nrm = unit([e[1], -e[0]]), ctrl = add(m, mul(nrm, bul * 2));
      d += ` Q${f2(ctrl[0])} ${f2(ctrl[1])} ${f2(cur.a[0])} ${f2(cur.a[1])}`; }
    else d += ` L${f2(cur.a[0])} ${f2(cur.a[1])}`;
    const c1 = add(cur.a, mul(sub(cur.P, cur.a), .58)), c2 = add(cur.b, mul(sub(cur.P, cur.b), .58));
    d += ` C${f2(c1[0])} ${f2(c1[1])} ${f2(c2[0])} ${f2(c2[1])} ${f2(cur.b[0])} ${f2(cur.b[1])}`;
  }
  return d + " Z";
}
const circ = (cx, cy, r) => `M${f2(cx - r)} ${f2(cy)} A${r} ${r} 0 1 0 ${f2(cx + r)} ${f2(cy)} A${r} ${r} 0 1 0 ${f2(cx - r)} ${f2(cy)} Z`;
const mirror = s => `<g transform="translate(100 0) scale(-1 1)">${s}</g>`;
const rot = (s, a, cx = 50, cy = 50) => `<g transform="rotate(${a} ${cx} ${cy})">${s}</g>`;

// ---- the glass material for one icon in one look
function makeCtx(mode, tint) {
  const mono = !(mode === "light" || mode === "dark"), dark = DARKISH.has(mode), clear = mode.startsWith("clear");
  const t = hexRgb(tint || "#5B78E6");
  const bg = mode === "light" ? "#FFFFFF" : mode === "dark" ? "#0E0E11" : mode === "tintL" ? rgb(mix(t, WHITE, .86)) : mode === "tintD" ? "#111216" : null;
  const monoBase = clear ? WHITE : mode === "tintD" ? mix(t, WHITE, .08) : mix(t, BLACK, .16);
  const defs = [];
  const C = { mode, mono, dark, clear, bg, defs };
  // one fine grain shared by every piece of this icon
  const grain = uid();
  defs.push(`<filter id="${grain}" x="0" y="0" width="100" height="100" filterUnits="userSpaceOnUse"><feTurbulence type="fractalNoise" baseFrequency="1.15" numOctaves="2" seed="7"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 ${dark ? .1 : .11} -.048"/></filter>`);
  const soft = uid();
  defs.push(`<filter id="${soft}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation=".28"/></filter>`);
  // A colour turned into the four tones a glass piece needs: light, body, deep, and its shadow.
  C.tones = (hex, m = .8) => {
    if (!mono) { const two = Array.isArray(hex), c0 = hexRgb(two ? hex[0] : hex), c1 = hexRgb(two ? hex[1] : hex); let c = two ? mix(c0, c1, .5) : c0; if (dark) c = mix(c, WHITE, .06);
      if (two) return { hi: mix(dark ? mix(c0, WHITE, .06) : c0, WHITE, .22), mid: c, lo: mix(dark ? mix(c1, WHITE, .06) : c1, BLACK, .12), edge: mix(c0, WHITE, .7), line: dark ? mix(c, WHITE, .35) : mix(c1, BLACK, .3), shadow: mix(c1, BLACK, .45), op: dark ? .9 : .86 };
      return { hi: mix(c, WHITE, .3), mid: c, lo: mix(c, BLACK, .2), edge: mix(c, WHITE, .7), line: dark ? mix(c, WHITE, .35) : mix(c, BLACK, .3), shadow: mix(c, BLACK, .45), op: dark ? .9 : .86 }; }
    const a = clear ? (mode === "clearL" ? .9 : .76) : 1;
    return { hi: monoBase, mid: monoBase, lo: monoBase, edge: WHITE, line: monoBase, shadow: BLACK, op: a, mono: [m * .72, m, Math.min(1, m + .1)] };
  };
  // One glass piece: tinted body, top sheen, a light edge zone for thickness, a hairline rim of light, a crisp edge.
  C.piece = (d, hex, o = {}) => {
    const T = C.tones(hex, o.m ?? .8), id = uid(), gb = uid(), gs = uid(), gr = uid(), sh = uid(), tf = o.tf ? ` transform="${o.tf}"` : "";
    const ang = o.angle ?? [0.2, 0, 0.8, 1];
    const stops = mono ? [[0, T.mono[0]], [.5, T.mono[1]], [1, T.mono[2]]].map(([off, a]) => `<stop offset="${off}" stop-color="${rgb(T.mid)}" stop-opacity="${(a * T.op).toFixed(3)}"/>`).join("")
      : `<stop offset="0" stop-color="${rgb(T.hi)}"/><stop offset=".5" stop-color="${rgb(T.mid)}"/><stop offset="1" stop-color="${rgb(T.lo)}"/>`;
    defs.push(`<linearGradient id="${gb}" x1="${ang[0]}" y1="${ang[1]}" x2="${ang[2]}" y2="${ang[3]}">${stops}</linearGradient>`);
    defs.push(`<linearGradient id="${gs}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="${mono ? (clear ? .3 : .14) : dark ? .12 : .2}"/><stop offset=".4" stop-color="#fff" stop-opacity="0"/></linearGradient>`);
    defs.push(`<linearGradient id="${gr}" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="${dark ? .9 : 1}"/><stop offset=".35" stop-color="#fff" stop-opacity=".45"/><stop offset=".6" stop-color="#fff" stop-opacity=".1"/><stop offset="1" stop-color="#fff" stop-opacity="${dark ? .42 : .55}"/></linearGradient>`);
    defs.push(`<clipPath id="${id}"><path d="${d}"${tf}/></clipPath>`);
    const shadowOp = mono ? (clear ? .12 : .28) : (dark ? .5 : .24);
    defs.push(`<filter id="${sh}" x="-25%" y="-25%" width="150%" height="160%"><feDropShadow dx="0" dy="${o.lift ?? .9}" stdDeviation="${o.blur ?? 1.1}" flood-color="${rgb(dark && !mono ? BLACK : T.shadow)}" flood-opacity="${shadowOp}"/></filter>`);
    const edgeZone = mono ? rgb(WHITE, clear ? .5 : .3) : rgb(T.edge, dark ? .4 : .5);
    const crisp = mono ? rgb(T.line, clear ? .5 : .9) : rgb(T.line, dark ? .55 : .45);
    return `<path d="${d}"${tf} fill="url(#${gb})"${mono ? "" : ` fill-opacity="${T.op}"`} filter="url(#${sh})"/>` +
      `<g clip-path="url(#${id})">` +
        `<path d="${d}"${tf} fill="url(#${gs})"/>` +
        `<path d="${d}"${tf} fill="none" stroke="${edgeZone}" stroke-width="${o.zone ?? 2.6}" filter="url(#${soft})" opacity="${o.band ?? .9}"/>` +
        (o.grain === false ? "" : `<rect width="100" height="100" filter="url(#${grain})" opacity="${mono ? .5 : 1}"/>`) +
        `<path d="${d}"${tf} fill="none" stroke="url(#${gr})" stroke-width="${o.rim ?? 1.05}"/>` +
      `</g>` +
      `<path d="${d}"${tf} fill="none" stroke="${crisp}" stroke-width="${o.edge ?? .42}"/>`;
  };
  C.line = (d, hex, hexDark, w, m = 1) => {
    const col = mono ? rgb(monoBase, (clear ? .85 : 1) * m) : (dark ? (hexDark || hex) : hex);
    return `<path d="${d}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
  };
  return C;
}

// ---- butterflies
const GRAPHITE = "#4A4556", GRAPHITE_D = "#A69FB5";
function body(C) {
  const g = C.dark ? GRAPHITE_D : GRAPHITE;
  return C.line("M48.7 32.4 C46.6 26.5 44 22.3 40.6 19.4", GRAPHITE, GRAPHITE_D, 1.45) + C.line("M51.3 32.4 C53.4 26.5 56 22.3 59.4 19.4", GRAPHITE, GRAPHITE_D, 1.45) +
    C.piece(circ(40.3, 19.1, 2.1), g, { m: 1, grain: false, rim: .8, band: .3, lift: .6, blur: .8 }) + C.piece(circ(59.7, 19.1, 2.1), g, { m: 1, grain: false, rim: .8, band: .3, lift: .6, blur: .8 }) +
    C.piece("M50 38.8 C52.5 38.8 52.8 46 52.6 56 C52.4 66 51.5 74 50 78.4 C48.5 74 47.6 66 47.4 56 C47.2 46 47.5 38.8 50 38.8 Z", g, { m: 1, rim: .9, band: .35, lift: 1, blur: 1.2 }) +
    C.piece(circ(50, 34.6, 3.9), g, { m: 1, rim: .9, band: .35, lift: .8, blur: 1 });
}
// card-like wings: rounded quadrilaterals, the leading and outer edges gently bowed
const rrect = (x, y, w, h, r) => `M${x + r} ${y} H${x + w - r} A${r} ${r} 0 0 1 ${x + w} ${y + r} V${y + h - r} A${r} ${r} 0 0 1 ${x + w - r} ${y + h} H${x + r} A${r} ${r} 0 0 1 ${x} ${y + h - r} V${y + r} A${r} ${r} 0 0 1 ${x + r} ${y} Z`;
const cardAt = (cx, cy, w, h, r) => rrect(cx - w / 2, cy - h / 2, w, h, r);
const CARD_FORE = { d: cardAt(68.5, 35.5, 31, 25, 9.5), tf: "rotate(-30 68.5 35.5)" };
const CARD_HIND = { d: cardAt(65, 61, 22, 21, 8), tf: "rotate(28 65 61)" };
// true wing curves (round 4's butterfly), for the comparison
const REAL_FORE_D = "M52.5 45 C57 33 66 23.5 79 19.5 C85 17.6 89.5 20.5 88.6 26.5 C87.3 35.5 83 44 76.5 49.5 C70 54.5 60.5 54.5 53.5 50.5 Z";
const REAL_HIND_D = "M53.5 51.5 C61 52.5 71.5 53.5 77.5 58.5 C82.5 62.8 81.5 71 75 76 C68.5 81 60.5 79 56.5 71.5 C54 66.5 52.8 58.5 53.5 51.5 Z";
const REAL_FORE = { d: REAL_FORE_D }, REAL_HIND = { d: REAL_HIND_D };
function butterfly(C, fore, hind, cols) {
  const side = (fc, hc, m1, m2) => C.piece(hind.d, hc, { m: m2, tf: hind.tf }) + C.piece(fore.d, fc, { m: m1, tf: fore.tf });
  return side(cols[2], cols[3], .9, .55) + mirror(side(cols[0], cols[1], 1, .72)) + body(C);
}

// ---- round 6 butterflies: card wings with wing-like proportions
const INDIGO = ["#4B4580", "#2A2650"], INDIGO_D = ["#C9C3EA", "#9A92C8"];
function body2(C) {
  const col = C.dark ? INDIGO_D : INDIGO;
  const tip = (x, y) => C.piece(circ(x, y, 1.65), col, { m: 1, grain: false, rim: .65, zone: 1, band: .4, lift: .4, blur: .6, edge: .25 });
  return C.line("M48.7 29.7 C47.4 24.7 44.7 20.5 41.2 17.8", "#3A3566", "#BEB7E0", 1.35) + C.line("M51.3 29.7 C52.6 24.7 55.3 20.5 58.8 17.8", "#3A3566", "#BEB7E0", 1.35) +
    tip(40.8, 17.4) + tip(59.2, 17.4) +
    C.piece("M50 44.5 C52.3 44.5 52.7 51 52.5 59 C52.3 67.5 51.4 74.5 50 79 C48.6 74.5 47.7 67.5 47.5 59 C47.3 51 47.7 44.5 50 44.5 Z", col, { m: 1, rim: .85, zone: 1.6, band: .5, lift: .9, blur: 1, grain: false }) +
    C.piece("M50 35.6 C53 35.6 53.9 39.4 53.9 42.4 C53.9 45.8 52.2 48.2 50 48.2 C47.8 48.2 46.1 45.8 46.1 42.4 C46.1 39.4 47 35.6 50 35.6 Z", col, { m: 1, rim: .85, zone: 1.6, band: .5, lift: .8, blur: 1, grain: false }) +
    C.piece(circ(50, 32.6, 3.15), col, { m: 1, rim: .8, zone: 1.3, band: .5, lift: .6, blur: .8, grain: false });
}
const shrink = (pts, k) => { const cx = pts.reduce((a, p) => a + p[0], 0) / pts.length, cy = pts.reduce((a, p) => a + p[1], 0) / pts.length; return pts.map(([x, y]) => [cx + (x - cx) * k, cy + (y - cy) * k]); };
const WING = {
  fore: [[53.4, 49.5], [55.4, 28.5], [83.6, 15.2], [86.8, 39.6]], foreR: [2.6, 6, 11, 11.5],
  hind: [[53.8, 45], [78.6, 49], [76, 77.4], [57.4, 72.6]], hindR: [2.6, 10, 11.5, 8.5],
  foreUp: [[53.4, 47.5], [54.6, 26.5], [79.6, 10.4], [85.4, 33.6]], hindUp: [[53.8, 44.5], [79.6, 51.6], [74.6, 76.4], [57, 70.2]],
};
function cardButterfly(C, cols, o = {}) {
  const fp = o.up ? WING.foreUp : WING.fore, hp = o.up ? WING.hindUp : WING.hind;
  const side = (fc, hc) => C.piece(roundPoly(hp, WING.hindR), hc, { m: .6 }) + (o.inner ? C.piece(roundPoly(shrink(hp, .58), WING.hindR.map(r => r * .6)), hc.map ? hc.map(h => rgbHexLite(h)) : rgbHexLite(hc), { m: .35, lift: .3, blur: .5, edge: .3, rim: .8 }) : "") +
    C.piece(roundPoly(fp, WING.foreR), fc, { m: .95 }) + (o.inner ? C.piece(roundPoly(shrink(fp, .58), WING.foreR.map(r => r * .6)), fc.map ? fc.map(h => rgbHexLite(h)) : rgbHexLite(fc), { m: .5, lift: .3, blur: .5, edge: .3, rim: .8 }) : "");
  return side(cols[2], cols[3]) + mirror(side(cols[0], cols[1])) + body2(C);
}
const rgbHexLite = h => "#" + mix(hexRgb(h), WHITE, .45).map(v => v.toString(16).padStart(2, "0")).join("");
const PINK = ["#FF9CC0", "#F0447C"], AMBER = ["#FFCB73", "#FF8A3D"], VIOLET = ["#B99BFF", "#6A50EE"], AZURE = ["#86CDFF", "#2E7DF0"], CORAL = ["#FFA38E", "#F2505F"];

// ---- flowers
const LOTUS = {
  side: "M47.5 62.5 C37 61.5 26.5 54 23 41 C22 37 24.4 34.2 28.4 35.4 C38.4 38.4 46 47.4 49.4 59.6 Z",
  bud: "M50 16.5 C56.8 24.8 64.2 33.5 64.2 45.6 C64.2 56.2 58 62.6 50 63.4 C42 62.6 35.8 56.2 35.8 45.6 C35.8 33.5 43.2 24.8 50 16.5 Z",
  leaf: "M19.5 59.5 C29.5 66.4 70.5 66.4 80.5 59.5 C79.4 72 66.2 80.2 50 80.2 C33.8 80.2 20.6 72 19.5 59.5 Z",
  base: "M28.5 75 C37.6 80.4 62.4 80.4 71.5 75 C68.4 84.4 60.2 88.6 50 88.6 C39.8 88.6 31.6 84.4 28.5 75 Z",
};
function lotus(C, c) {
  return `<g transform="translate(0 -2)">` + C.piece(LOTUS.side, c.sideL, { m: .5, ...(c.sideLopt || {}) }) + mirror(C.piece(LOTUS.side, c.sideR, { m: .5 })) +
    C.piece(LOTUS.bud, c.bud, { m: .95 }) + C.piece(LOTUS.leaf, c.leaf, { m: .7 }) + C.piece(LOTUS.base, c.base, { m: 1 }) + `</g>`;
}
// a lotus made of cards: five petal cards fanned from one point, resting on two card leaves
const cardRect = (cx, top, w, h, r) => `M${cx - w / 2 + r} ${top} H${cx + w / 2 - r} A${r} ${r} 0 0 1 ${cx + w / 2} ${top + r} V${top + h - r} A${r} ${r} 0 0 1 ${cx + w / 2 - r} ${top + h} H${cx - w / 2 + r} A${r} ${r} 0 0 1 ${cx - w / 2} ${top + h - r} V${top + r} A${r} ${r} 0 0 1 ${cx - w / 2 + r} ${top} Z`;
function cardLotus(C, c) {
  const fan = (w, h, top, a, col, m) => C.piece(cardRect(50, top, w, h, 6.5), col, { m, tf: `rotate(${a} 50 64)` });
  return `<g transform="translate(0 -2)">` +
    fan(17, 34, 33, -52, c.outerL, .45) + fan(17, 34, 33, 52, c.outerR, .45) +
    fan(19, 40, 27, -25, c.innerL, .62) + fan(19, 40, 27, 25, c.innerR, .62) +
    fan(21, 48, 19, 0, c.centre, .95) +
    C.piece(LOTUS.leaf, c.leaf, { m: .72 }) + C.piece(LOTUS.base, c.base, { m: 1 }) + `</g>`;
}
const PETAL = "M50 49.5 C42.6 45.6 36.6 37.6 37.2 28.2 C37.6 22 42.8 19.2 47 21.4 L50 24.8 L53 21.4 C57.2 19.2 62.4 22 62.8 28.2 C63.4 37.6 57.4 45.6 50 49.5 Z";
function blossom(C, cols, centre, simple) {
  const ms = [1, .78, .56, .88, .66];
  if (simple) return `<g transform="translate(50 50) scale(1.16) translate(-50 -50)">` + cols.map((c, i) => rot(C.piece(PETAL, c, { m: ms[i] }), i * 72)).join("") +
    C.piece(circ(50, 50, 5.4), centre, { m: .35, rim: .9, zone: 1.8, edge: .32 }) + `</g>`;
  return cols.map((c, i) => rot(C.piece(PETAL, c, { m: ms[i] }), i * 72)).join("") +
    [0, 1, 2, 3, 4].map(i => { const a = (i * 72 - 90) * Math.PI / 180, x = 50 + 9.2 * Math.cos(a), y = 50 + 9.2 * Math.sin(a);
      return C.line(`M50 50 L${f2(50 + 7.6 * Math.cos(a))} ${f2(50 + 7.6 * Math.sin(a))}`, "#E89A2C", "#F2B04A", .9, .8) + C.piece(circ(x, y, 1.6), "#F6B73C", { m: .95, grain: false, rim: .5, zone: 1, band: .5, lift: .3, blur: .4, edge: .25 }); }).join("") +
    C.piece(circ(50, 50, 4.6), centre, { m: .35, rim: .8, zone: 1.6, edge: .3 });
}

const ICONS = [
  { id: "B4n", name: "Card butterfly", idea: "B4 reworked: the card wings kept, now with wing proportions. Long forewings raised as if in flight, smaller hindwings tucked under them so the glass mixes where they overlap, each wing shifting between two related colours, on a slim indigo glass body.",
    draw: C => cardButterfly(C, [PINK, AMBER, VIOLET, AZURE], { up: true }) },
  { id: "B4g", name: "Double-glazed butterfly", idea: "The reworked butterfly with a lighter inner card of glass in every wing, two layers like a double-glazed window.",
    draw: C => cardButterfly(C, [PINK, AMBER, VIOLET, AZURE], { up: true, inner: true }) },
  { id: "F1c", name: "Card lotus", idea: "The dawn lotus with card petals instead of drops: five glass cards fanned from one point like a hand of cards, peach and violet outside, pink in the centre, resting on two green card leaves.",
    draw: C => cardLotus(C, { outerL: ["#FFC892", "#FF8A4C"], outerR: ["#CDB0FF", "#7C5CF0"], innerL: ["#FFB3C9", "#FF6E9C"], innerR: ["#E2B8FF", "#A86BF2"], centre: ["#FF9CC0", "#EF427B"], leaf: "#2EC4A0", base: "#16927E" }) },
  { id: "B4", name: "Card butterfly", idea: "Your pick, redrawn in glass: four card wings in four colours, each a slab of coloured glass with a rim of light, mixing where the wings overlap; a graphite glass body.",
    draw: C => butterfly(C, CARD_FORE, CARD_HIND, ["#FF5C93", "#FFA23A", "#8E6BFF", "#3E9BFF"]) },
  { id: "B4b", name: "Twin card butterfly", idea: "The same card wings with matching sides, as a real butterfly has: coral forewings over violet hindwings.",
    draw: C => butterfly(C, CARD_FORE, CARD_HIND, ["#FF6A6A", "#8E6BFF", "#FF6A6A", "#8E6BFF"]) },
  { id: "B5", name: "Glass butterfly", idea: "For comparison: the same glass on true butterfly wing curves instead of card shapes.",
    draw: C => butterfly(C, REAL_FORE, REAL_HIND, ["#FF5C93", "#FFA23A", "#8E6BFF", "#3E9BFF"]) },
  { id: "F1", name: "Lotus bud", idea: "Your pick in glass: a deep pink bud between two light petals, held in two green glass cups.",
    draw: C => lotus(C, { sideL: "#FF8DB2", sideR: "#FF8DB2", bud: "#F2467F", leaf: "#34C77A", base: "#14996A" }) },
  { id: "F1b", name: "Dawn lotus", idea: "The lotus with petals in three colours, peach, pink and violet, like the light at sunrise.",
    draw: C => lotus(C, { sideL: "#FFAA6E", sideR: "#A98BFF", bud: "#FF4F8B", leaf: "#2EC4A0", base: "#16927E" }) },
  { id: "B6", name: "Refined card butterfly", idea: "Card wings with wing proportions: long forewings angled up, smaller hindwings tucked under them, each wing shifting between two related colours, a slim glass body.",
    draw: C => cardButterfly(C, [PINK, AMBER, VIOLET, AZURE]) },
  { id: "B7", name: "Double-glazed butterfly", idea: "The refined card wings with a lighter inner card of glass in each wing, two layers like a double-glazed window.",
    draw: C => cardButterfly(C, [PINK, AMBER, VIOLET, AZURE], { inner: true }) },
  { id: "B8", name: "Matching card butterfly", idea: "The refined card wings with matching sides, coral forewings over violet hindwings.",
    draw: C => cardButterfly(C, [CORAL, VIOLET, CORAL, VIOLET]) },
  { id: "B9", name: "Lifted card butterfly", idea: "The refined card wings raised higher, as if caught mid-flight.",
    draw: C => cardButterfly(C, [PINK, AMBER, VIOLET, AZURE], { up: true }) },
  { id: "FINAL", name: "Carden", idea: "The dawn lotus with F4's colours: a pink bud between a yellow and a blue petal, held in two green glass cups.",
    draw: C => lotus(C, { sideL: ["#FFE27A", "#F6B60F"], sideR: ["#8CCBFF", "#2F86F2"], bud: "#FF4F8B", leaf: "#2EC4A0", base: "#16927E" }), scale: 1 },
  { id: "FINAL94", name: "Carden (94%)", draw: C => lotus(C, { sideL: ["#FFE27A", "#F6B60F"], sideR: ["#8CCBFF", "#2F86F2"], bud: "#FF4F8B", leaf: "#2EC4A0", base: "#16927E" }), scale: .94 },
  { id: "FINAL88", name: "Carden (88%)", draw: C => lotus(C, { sideL: ["#FFE27A", "#F6B60F"], sideR: ["#8CCBFF", "#2F86F2"], bud: "#FF4F8B", leaf: "#2EC4A0", base: "#16927E" }), scale: .88 },
  ...[
    ["FV1", "Deep gold", ["#FFB91F", "#C97400"], ["#8CCBFF", "#2F86F2"], null, "2.16 : 1", "2.20 : 1", "Recommended. The yellow deepened to gold until it carries the same weight as the blue."],
    ["FV2", "Golden and softer blue", ["#FFC531", "#DC8700"], ["#9AD2FF", "#4396F4"], null, "1.92 : 1", "2.00 : 1", "Both sides meet in the middle: a golden yellow and a slightly lighter sky blue."],
    ["FV3", "Marigold", ["#FFAE3D", "#EC6E00"], ["#8CCBFF", "#2F86F2"], null, "2.14 : 1", "2.20 : 1", "Warmer and more orange, the strongest warm colour next to the blue."],
    ["FV4", "Saffron", ["#FFBE2E", "#E58200"], ["#8CCBFF", "#2F86F2"], null, "1.96 : 1", "2.20 : 1", "Between golden and marigold."],
    ["FV5", "Sunflower with a gold edge", ["#FFD23A", "#D99400"], ["#8CCBFF", "#2F86F2"], { edge: .8 }, "1.79 : 1", "2.20 : 1", "Keeps a brighter yellow and gives it a fine gold outline so its shape holds when small."],
    ["FV0", "Current yellow", ["#FFE27A", "#F6B60F"], ["#8CCBFF", "#2F86F2"], null, "1.49 : 1", "2.20 : 1", "Today's version, for comparison: it fades into white at small sizes."],
  ].map(([id, name, sideL, sideR, opt, cy, cb, note]) => ({ id, name, note, cy, cb, scale: 1,
    draw: C => lotus(C, { sideL, sideR, sideLopt: opt, bud: "#FF4F8B", leaf: "#2EC4A0", base: "#16927E" }) })),
  { id: "F4", name: "Rainbow blossom", idea: "Your cherry blossom made colourful: five glass petals in five colours around a pale glass centre with golden stamens.",
    draw: C => blossom(C, ["#FF4F8B", "#FF9A3D", "#FFCF3A", "#34C77A", "#3E9BFF"], "#FFF6E8", true), scale: .92 },
  { id: "F4b", name: "Sunset blossom", idea: "The blossom in warmer glass only: rose, coral, peach, lilac and violet.",
    draw: C => blossom(C, ["#FF5C93", "#FF7A59", "#FFB25E", "#C77DFF", "#8E6BFF"], "#FFF6E8") },
];

function tile(icon, mode, size, tint) {
  const C = makeCtx(mode, tint);
  const art = icon.draw(C);
  return `<div class="ico m-${mode}" style="--s:${size}px"><svg viewBox="0 0 100 100" role="img" aria-label="${icon.name}"><defs>${C.defs.join("")}</defs>` +
    (C.bg ? `<rect width="100" height="100" fill="${C.bg}"/>` : "") + `<g transform="translate(50 50) scale(${icon.scale ?? .88}) translate(-50 -50)">${art}</g></svg></div>`;
}
// A standalone SVG of one icon in one look, for exports: no rounded corners (iOS masks the icon itself).
// opts.background: false leaves the ground transparent (Dark and Tinted assets); opts.scale overrides the artwork scale.
function svg(id, mode, opts = {}) {
  const icon = ICONS.find(i => i.id === id), C = makeCtx(mode, opts.tint || "#FFFFFF");
  const art = icon.draw(C), sc = opts.scale ?? icon.scale ?? .88, size = opts.size || 1024;
  const bg = opts.background === false ? "" : (C.bg ? `<rect width="100" height="100" fill="${C.bg}"/>` : "");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 100 100"><defs>${C.defs.join("")}</defs>${bg}` +
    `<g transform="translate(50 50) scale(${sc}) translate(-50 -50)">${art}</g></svg>`;
}
const FINAL = "FV1";
if (typeof window !== "undefined") window.CARDEN5 = { ICONS, tile, svg, FINAL, DARKISH, roundPoly };
// makeCtx, roundPoly and circ are shared with tools/brand/vip-promo.js (the VIP promotional images).
if (typeof module !== "undefined") module.exports = { ICONS, tile, svg, FINAL, makeCtx, roundPoly, circ };
})();
