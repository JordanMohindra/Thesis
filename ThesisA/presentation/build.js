const pptxgen = require("pptxgenjs");
const D = require("./data.json");

const pres = new pptxgen();
pres.layout = "LAYOUT_16x9"; // 10 x 5.625
pres.author = "Jordan Mohindra";
pres.title = "Lossless radar compression on a TDM-MIMO cascade";

// ---------- palette ----------
const INK = "13212F", TEXT = "1F2A37", MUTED = "5B6675", RULE = "D5DCE3", TINT = "EEF4F7", WHITE = "FFFFFF";
const DRHE = "007FA3", LPC = "C96A12", KIEM = "A8324A", RED = "6A4BC4", REF = "8C95A3";
const DRHE_T = "8CC7D8", LPC_T = "E6B98B";
const HF = "Cambria", BF = "Calibri";

// ---------- helpers ----------
function kicker(s, text, color) {
  s.addText(text.toUpperCase(), { x: 0.5, y: 0.28, w: 9, h: 0.25, fontFace: BF, fontSize: 10.5, bold: true,
    color: color || DRHE, charSpacing: 2, margin: 0, isTextBox: true });
}
function title(s, text, opts = {}) {
  s.addText(text, { x: 0.5, y: 0.52, w: 9, h: 0.62, fontFace: HF, fontSize: opts.size || 26, bold: true,
    color: opts.color || TEXT, margin: 0, valign: "top", isTextBox: true });
}
function card(s, x, y, w, h, fill) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fill || TINT }, line: { color: fill || TINT } });
}
function para(s, runs, x, y, w, h, o = {}) {
  s.addText(runs, Object.assign({ x, y, w, h, fontFace: BF, fontSize: 13, color: TEXT, margin: 0.08,
    valign: "top", paraSpaceAfter: 4, isTextBox: true }, o));
}
function bullets(items, size) {
  return items.map((t, i) => {
    const runs = Array.isArray(t) ? t : [{ text: t }];
    return runs.map((r, j) => ({ text: r.text, options: Object.assign({ fontSize: size || 13,
      bullet: j === 0 ? { indent: 12 } : undefined, breakLine: j === runs.length - 1 && i < items.length - 1 }, r.options || {}) }));
  }).flat();
}
function source(s, text) {
  s.addText(text, { x: 0.5, y: 5.2, w: 9, h: 0.25, fontFace: BF, fontSize: 9, color: MUTED, margin: 0, isTextBox: true });
}
function pageNo(s, n) {
  s.addText(String(n), { x: 9.1, y: 5.2, w: 0.4, h: 0.25, fontFace: BF, fontSize: 9, color: MUTED, align: "right", margin: 0, isTextBox: true });
}
const axis = { catAxisLabelColor: MUTED, valAxisLabelColor: MUTED, catAxisLabelFontFace: BF, valAxisLabelFontFace: BF,
  catAxisLabelFontSize: 10, valAxisLabelFontSize: 10, valGridLine: { color: "E3E8ED", size: 0.5 }, catGridLine: { style: "none" },
  catAxisLineColor: RULE, valAxisLineShow: false, legendFontFace: BF, legendFontSize: 10, legendColor: TEXT };
function ax(extra) { return Object.assign({}, JSON.parse(JSON.stringify(axis)), extra); }

let n = 0;

// =====================================================================
// 1. Title
{
  const s = pres.addSlide(); n++;
  s.background = { color: INK };
  s.addText("Lossless radar compression\non a 12-transmitter cascade", { x: 0.6, y: 1.25, w: 8.8, h: 1.5, fontFace: HF,
    fontSize: 36, bold: true, color: WHITE, margin: 0, isTextBox: true });
  s.addText("DRHE vs LPC · the prediction-lag problem · the Huffman dictionary · comparison with Kiem",
    { x: 0.6, y: 2.9, w: 8.8, h: 0.4, fontFace: BF, fontSize: 15, color: "B9C6D3", margin: 0, isTextBox: true });
  // motif: three dots in the series colours
  [[DRHE, "DRHE"], [LPC, "LPC"], [KIEM, "Kiem"]].forEach(([c, t], i) => {
    s.addShape(pres.shapes.OVAL, { x: 0.6 + i * 1.35, y: 3.75, w: 0.16, h: 0.16, fill: { color: c }, line: { color: c } });
    s.addText(t, { x: 0.82 + i * 1.35, y: 3.67, w: 1.0, h: 0.32, fontFace: BF, fontSize: 12, color: "DCE4EC", margin: 0, isTextBox: true });
  });
  s.addText("Jordan Mohindra  ·  UNSW Sydney  ·  September 2026", { x: 0.6, y: 4.75, w: 8.8, h: 0.3,
    fontFace: BF, fontSize: 12, color: "8FA0B2", margin: 0, isTextBox: true });
  s.addNotes("Thesis results in four parts: (1) the prediction-lag problem both algorithms had on a TDM-MIMO radar, (2) the DRHE vs LPC comparison once corrected, (3) the Huffman dictionary and how re-deriving it helps LPC most, (4) how all of this compares with Kiem's thesis, which this work builds on.");
}

// =====================================================================
// 2. What the compressor does
{
  const s = pres.addSlide(); n++;
  kicker(s, "Background");
  title(s, "Two stages: predict, then entropy-code the residual");
  const steps = [
    ["Raw ADC", "256 samples/ramp\n16 RX, 192 ramps", "F3F5F7", TEXT],
    ["Range FFT", "128 bins kept", "F3F5F7", TEXT],
    ["FX16", "round to int16\n(what gets compressed)", "F3F5F7", TEXT],
    ["Predictor", "DRHE or LPC\nresidual = x − x̂", "DDEFF5", DRHE],
    ["Entropy coder", "S4 category +\nfixed Huffman code", "F6E6D6", LPC],
  ];
  const w = 1.62, gap = 0.2, y = 1.55;
  steps.forEach(([h, sub, fill, col], i) => {
    const x = 0.5 + i * (w + gap);
    card(s, x, y, w, 1.15, fill);
    s.addText(h, { x, y: y + 0.1, w, h: 0.35, fontFace: HF, fontSize: 15, bold: true, color: col, align: "center", margin: 0, isTextBox: true });
    s.addText(sub, { x: x + 0.05, y: y + 0.48, w: w - 0.1, h: 0.6, fontFace: BF, fontSize: 11, color: MUTED, align: "center", margin: 0, isTextBox: true });
    if (i < steps.length - 1)
      s.addShape(pres.shapes.LINE, { x: x + w + 0.02, y: y + 0.575, w: gap - 0.04, h: 0, line: { color: REF, width: 1.5, endArrowType: "triangle" } });
  });
  card(s, 0.5, 3.1, 4.3, 1.85, WHITE);
  para(s, bullets([
    [{ text: "Lossless: ", options: { bold: true } }, { text: "the decoder rebuilds every FX16 code exactly, so detection is untouched." }],
    [{ text: "CR ", options: { bold: true } }, { text: "= uncompressed bits ÷ compressed bits (incl. side info, 256-bit padding)." }],
    [{ text: "Data: ", options: { bold: true } }, { text: "50 ColoRadar frames, 4 RX to the HLS path, Vitis HLS → Vivado on xcku5p." }],
  ]), 0.5, 3.1, 4.4, 1.9);
  card(s, 5.2, 3.1, 4.3, 1.55, TINT);
  s.addText([{ text: "DRHE", options: { bold: true, color: DRHE } }, { text: "  fixed polar filters: predicts magnitude and phase from previous ramps of the same bin (Kiem's algorithm).", options: { color: TEXT, breakLine: true } },
    { text: "LPC", options: { bold: true, color: LPC } }, { text: "  2nd-order autoregressive model on I and Q, coefficients fitted per bin per frame (Yule–Walker), sent as side info.", options: { color: TEXT } }],
    { x: 5.3, y: 3.2, w: 4.1, h: 1.7, fontFace: BF, fontSize: 12.5, margin: 0, valign: "top", paraSpaceAfter: 8, isTextBox: true });
  pageNo(s, n);
  s.addNotes("Both compressors share the entropy coder exactly: S4 category, APPEND bits and Kiem's fixed Huffman dictionary. So any difference in ratio between them is the predictor. The predictor turns each FX16 sample into a small residual; the coder spends few bits on small residuals.");
}

// =====================================================================
// 3. The TDM ramp axis
{
  const s = pres.addSlide(); n++;
  kicker(s, "1 · The prediction-lag problem");
  title(s, "Twelve transmitters share the ramp axis");
  const N = 26, bw = 0.3, g = 0.035, x0 = 0.5 + (9 - (N * bw + (N - 1) * g)) / 2, y0 = 1.72;
  const m = 24; // current ramp
  s.addText("ramp index →", { x: 0.5, y: y0 - 0.33, w: 2, h: 0.25, fontFace: BF, fontSize: 10, color: MUTED, margin: 0, isTextBox: true });
  for (let i = 0; i < N; i++) {
    const tx = i % 12, x = x0 + i * (bw + g);
    const isCur = i === m, isSame = i === m - 12 || i === 0, isPrev = i === m - 1;
    const fill = isCur ? DRHE : isSame ? DRHE_T : isPrev ? "E8C2CA" : "E6EBF0";
    s.addShape(pres.shapes.RECTANGLE, { x, y: y0, w: bw, h: 0.42, fill: { color: fill }, line: { color: WHITE, width: 1 } });
    s.addText(String(tx), { x, y: y0, w: bw, h: 0.42, fontFace: BF, fontSize: 10, bold: isCur, color: isCur ? WHITE : TEXT, align: "center", valign: "middle", margin: 0, isTextBox: true });
  }
  s.addText("number = transmitter (TX) that sent the ramp", { x: 5.5, y: y0 - 0.33, w: 4, h: 0.25, fontFace: BF, fontSize: 10, color: MUTED, align: "right", margin: 0, isTextBox: true });
  const cx = (i) => x0 + i * (bw + g) + bw / 2;
  // lag-1 bracket (below, crimson)
  const yb1 = y0 + 0.42;
  s.addShape(pres.shapes.LINE, { x: cx(m), y: yb1, w: 0, h: 0.22, line: { color: KIEM, width: 1.5 } });
  s.addShape(pres.shapes.LINE, { x: cx(m - 1), y: yb1 + 0.22, w: cx(m) - cx(m - 1), h: 0, line: { color: KIEM, width: 1.5 } });
  s.addShape(pres.shapes.LINE, { x: cx(m - 1), y: yb1 + 0.02, w: 0, h: 0.2, flipV: true, line: { color: KIEM, width: 1.5, endArrowType: "triangle" } });
  s.addText("lag 1", { x: cx(m - 1) - 1.25, y: yb1 + 0.1, w: 1.15, h: 0.25, fontFace: BF, fontSize: 11, bold: true, color: KIEM, align: "right", margin: 0, isTextBox: true });
  // lag-12 bracket (below, deeper, teal)
  s.addShape(pres.shapes.LINE, { x: cx(m), y: yb1 + 0.22, w: 0, h: 0.38, line: { color: DRHE, width: 1.5 } });
  s.addShape(pres.shapes.LINE, { x: cx(m - 12), y: yb1 + 0.6, w: cx(m) - cx(m - 12), h: 0, line: { color: DRHE, width: 1.5 } });
  s.addShape(pres.shapes.LINE, { x: cx(m - 12), y: yb1 + 0.02, w: 0, h: 0.58, flipV: true, line: { color: DRHE, width: 1.5, endArrowType: "triangle" } });
  s.addText("lag 12 = nTx", { x: cx(m - 12) + 0.1, y: yb1 + 0.33, w: 1.4, h: 0.25, fontFace: BF, fontSize: 11, bold: true, color: DRHE, margin: 0, isTextBox: true });

  card(s, 0.5, 3.2, 4.35, 1.55, "F7EDEF");
  s.addText([{ text: "Lag 1 — as first built", options: { bold: true, color: KIEM, fontSize: 14, breakLine: true } },
    { text: "Ramp m−1 came from a different antenna 11 times in 12. The phase change between them is the array steering phase (where the target is), not Doppler (how it moves), so a slow-time predictor has nothing smooth to track.", options: { color: TEXT, fontSize: 12.5 } }],
    { x: 0.62, y: 3.28, w: 4.1, h: 1.65, fontFace: BF, margin: 0, valign: "top", paraSpaceAfter: 6, isTextBox: true });
  card(s, 5.15, 3.2, 4.35, 1.55, "E4F1F6");
  s.addText([{ text: "Lag nTx — corrected", options: { bold: true, color: DRHE, fontSize: 14, breakLine: true } },
    { text: "Ramp m−12 is the same transmitter, one TDM cycle earlier. That is the true slow-time neighbour: only Doppler changes between them, which is exactly what DRHE and LPC were designed to predict.", options: { color: TEXT, fontSize: 12.5 } }],
    { x: 5.27, y: 3.28, w: 4.1, h: 1.65, fontFace: BF, margin: 0, valign: "top", paraSpaceAfter: 6, isTextBox: true });
  pageNo(s, n);
  s.addNotes("ColoRadar's cascade transmits TX0, TX1, ... TX11, then TX0 again, so ramp index m is transmitted by TX (m mod 12). Kiem's radar has one transmitter, so on his radar the previous ramp IS the slow-time neighbour and lag 1 is correct. On this radar it is wrong. The fix: index the predictor state by transmitter and predict from m-12 (DRHE) or m-12 and m-24 (LPC).");
}

// =====================================================================
// 4. CR vs lag (line chart)
{
  const s = pres.addSlide(); n++;
  kicker(s, "1 · The prediction-lag problem");
  title(s, "Compression ratio against prediction lag");
  const labels = D.lag.lags.map((L) => (L === 1 || L % 6 === 0 ? String(L) : " "));
  s.addChart(pres.charts.LINE, [
    { name: "DRHE (predict from m−L)", labels, values: D.lag.drhe },
    { name: "LPC (predict from m−L, m−2L)", labels, values: D.lag.lpc },
    { name: "No prediction", labels, values: labels.map(() => D.lag.nopred) },
  ], ax({ x: 0.35, y: 1.15, w: 6.05, h: 3.95, chartColors: [DRHE, LPC, REF], lineSize: 2, lineDataSymbol: "circle", lineDataSymbolSize: 5,
    valAxisMinVal: 3.2, valAxisMaxVal: 3.8, valAxisMajorUnit: 0.1, valAxisLabelFormatCode: "0.0",
    showLegend: true, legendPos: "b", catAxisTitle: "prediction lag L (ramps)", showCatAxisTitle: true, catAxisTitleColor: MUTED, catAxisTitleFontSize: 10,
    valAxisTitle: "compression ratio", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10, catAxisLabelFrequency: 1 }));
  const cx = 6.65, cw = 2.85;
  card(s, cx, 1.2, cw, 1.12, "F7EDEF");
  para(s, [{ text: "L = 1 (as built)", options: { bold: true, color: KIEM, breakLine: true } },
    { text: "DRHE 3.310 · LPC 3.385", options: { bold: true, breakLine: true } },
    { text: "both below no prediction, 3.479", options: { color: MUTED, fontSize: 11.5 } }], cx + 0.05, 1.25, cw - 0.1, 1.05, { fontSize: 13, paraSpaceAfter: 2 });
  card(s, cx, 2.45, cw, 1.12, "E4F1F6");
  para(s, [{ text: "L = 12 = nTx (corrected)", options: { bold: true, color: DRHE, breakLine: true } },
    { text: "DRHE 3.751 · LPC 3.697", options: { bold: true, breakLine: true } },
    { text: "+7.8 % and +6.3 % over no prediction", options: { color: MUTED, fontSize: 11.5 } }], cx + 0.05, 2.5, cw - 0.1, 1.05, { fontSize: 13, paraSpaceAfter: 2 });
  card(s, cx, 3.7, cw, 1.35, TINT);
  para(s, [{ text: "Only multiples of 12 help. ", options: { bold: true } },
    { text: "LPC also rises at L = 6, 18, 30 because its second tap, 2L, lands on a multiple of 12. Any other lag is no better than doing nothing.", options: {} }], cx + 0.05, 3.75, cw - 0.1, 1.28, { fontSize: 11.5 });
  source(s, "Per-frame CR with 256-bit padding, mean of 50 frames, 4 RX, Kiem's fixed dictionary. L = 1 and 12 reproduce the HLS C-simulation to 5 decimals.");
  s.addNotes("This is the lag graph. For every lag from 1 to 36 we compress all 50 frames with each predictor. The spikes sit exactly at multiples of the transmitter count: 12, 24, 36. Lag 1, which is what both designs used as first built, is in the flat floor, below the grey no-prediction line. The values at L=1 and L=12 are the same numbers the hardware C-simulation measured (3.30987, 3.38497, 3.75082, 3.69681).");
}

// =====================================================================
// 5. Against no prediction (bars)
{
  const s = pres.addSlide(); n++;
  kicker(s, "1 · The prediction-lag problem");
  title(s, "As first built, both predictors lost to doing nothing");
  const labels = ["As built (lag 1)", "Corrected (lag nTx)"];
  s.addChart(pres.charts.BAR, [
    { name: "No prediction", labels, values: [3.479, 3.479] },
    { name: "DRHE", labels, values: [3.310, 3.751] },
    { name: "LPC", labels, values: [3.385, 3.697] },
  ], ax({ x: 0.35, y: 1.15, w: 5.3, h: 3.95, barDir: "col", barGrouping: "clustered", barGapWidthPct: 60, barOverlapPct: -8,
    chartColors: [REF, DRHE, LPC], valAxisMinVal: 0, valAxisMaxVal: 4, valAxisMajorUnit: 1, showValue: true, dataLabelPosition: "outEnd",
    dataLabelFormatCode: "0.000", dataLabelFontSize: 10, dataLabelColor: TEXT, dataLabelFontFace: BF, showLegend: true, legendPos: "b",
    valAxisTitle: "compression ratio (50 frames)", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10, catAxisLabelFontSize: 11 }));
  const rows = [
    [{ text: "vs no prediction", options: { bold: true, color: MUTED } }, { text: "lag 1", options: { bold: true, color: MUTED, align: "right" } }, { text: "lag nTx", options: { bold: true, color: MUTED, align: "right" } }],
    [{ text: "DRHE", options: { bold: true, color: DRHE } }, { text: "−4.9 %", options: { align: "right" } }, { text: "+7.8 %", options: { align: "right", bold: true } }],
    [{ text: "LPC", options: { bold: true, color: LPC } }, { text: "−2.7 %", options: { align: "right" } }, { text: "+6.3 %", options: { align: "right", bold: true } }],
  ];
  s.addTable(rows, { x: 6.0, y: 1.3, w: 3.5, colW: [1.5, 1.0, 1.0], fontFace: BF, fontSize: 13, color: TEXT, rowH: 0.36,
    border: { type: "solid", pt: 0.5, color: RULE }, fill: { color: WHITE } });
  card(s, 6.0, 2.75, 3.5, 2.3, TINT);
  para(s, bullets([
    "Coding the FX16 values with no predictor at all gave CR 3.479.",
    "The benchmark ratios (3.30, 3.37) looked right because most of the ratio is not prediction: 1.64× is unused int16 headroom and 2.13× is spectral sparsity.",
    "Every sample is still reconstructed exactly in all four designs (MaxDiff = 0).",
  ], 12), 6.05, 2.82, 3.4, 2.2);
  pageNo(s, n);
  s.addNotes("The audit that found this: take the predictor out and code the raw FX16 values through the same coder. That did better than both predictors. Corrected, DRHE gains 7.8% and LPC 6.3% over no prediction — modest but real, and only on the right axis. Most of the 3.3 ratio is the capture using only ~9.8 of 16 bits, plus a sparse range spectrum.");
}

// =====================================================================
// 6. Residual tails
{
  const s = pres.addSlide(); n++;
  kicker(s, "1 · The prediction-lag problem");
  title(s, "The residual tail, before and after the fix");
  const labels = ["No prediction", "DRHE, lag 1", "LPC, lags 1, 2", "DRHE, lag 12", "LPC, lags 12, 24"];
  s.addChart(pres.charts.BAR, [{ name: "99th percentile |residual|", labels, values: [80.6, 102.4, 63.4, 15.8, 8.2] }],
    ax({ x: 0.35, y: 1.2, w: 5.6, h: 3.85, barDir: "bar", chartColors: ["3D5A73"], barGapWidthPct: 55, showValue: true, dataLabelPosition: "outEnd",
      dataLabelFormatCode: "0.0", dataLabelFontSize: 11, dataLabelColor: TEXT, valAxisMinVal: 0, valAxisMaxVal: 120, valAxisMajorUnit: 20,
      catAxisOrientation: "maxMin", showLegend: false, showTitle: true, title: "99th percentile of |residual| (FX16 codes, smaller is better)",
      titleFontFace: BF, titleFontSize: 11, titleColor: MUTED, catAxisLabelFontSize: 11 }));
  const rows = [
    [{ text: "Share of values in categories 0–2 (cost ≤ 4 bits)", options: { bold: true, color: MUTED, colspan: 2 } }],
    ["No prediction", "76.1 %"], ["DRHE, lag 1", "64.5 %"], ["DRHE, lag 12", "84.6 %"], ["LPC, lags 12, 24", "92.9 %"],
  ].map((r, i) => i === 0 ? r : [{ text: r[0] }, { text: r[1], options: { align: "right", bold: i >= 3 } }]);
  s.addTable(rows, { x: 6.25, y: 1.3, w: 3.25, colW: [2.15, 1.1], fontFace: BF, fontSize: 12, color: TEXT, rowH: 0.32,
    border: { type: "solid", pt: 0.5, color: RULE } });
  card(s, 6.25, 3.45, 3.25, 1.6, TINT);
  para(s, [{ text: "Why a few big residuals matter: ", options: { bold: true } },
    { text: "a residual of 16–31 costs 10 bits, 128–255 costs 16. At lag 1, one value in eighteen was eating one bit in seven." }],
    6.3, 3.5, 3.15, 1.5, { fontSize: 12 });
  source(s, "Five audit frames, 4 RX. Category shares from the independent Python implementation.");
  pageNo(s, n);
  s.addNotes("Lag-1 DRHE produces a heavier tail than not predicting at all (p99 102 vs 81). Predicting at lag 12 cuts it to 16, and the corrected LPC to 8. In the currency the coder charges, the corrected LPC puts 93% of values in categories 0-2.");
}

// =====================================================================
// 7. Why LPC failed more gracefully (stacked bar)
{
  const s = pres.addSlide(); n++;
  kicker(s, "2 · DRHE vs LPC", LPC);
  title(s, "Why LPC lost less on the wrong axis");
  const labels = ["No pred.", "DRHE lag 1", "LPC 1,2", "DRHE lag 12", "LPC 12,24"];
  s.addChart(pres.charts.BAR, [
    { name: "Residual bits", labels, values: [4.586, 4.821, 4.543, 4.240, 4.102] },
    { name: "LPC coefficient table (0.167)", labels, values: [0, 0, 0.167, 0, 0.167] },
  ], ax({ x: 0.35, y: 1.15, w: 5.5, h: 3.95, barDir: "col", barGrouping: "stacked", chartColors: ["566B80", LPC], barGapWidthPct: 55,
    showValue: true, dataLabelPosition: "inEnd", dataLabelFormatCode: '[<0.2]"";0.000', dataLabelFontSize: 10, dataLabelColor: WHITE,
    valAxisMinVal: 0, valAxisMaxVal: 5.5, valAxisMajorUnit: 1, showLegend: true, legendPos: "b",
    valAxisTitle: "bits per value (lower is better)", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10, catAxisLabelFontSize: 10.5 }));
  // two stat columns
  const col = (x, head, color, a1, e, note) => {
    card(s, x, 1.2, 1.7, 2.6, TINT);
    s.addText(head, { x, y: 1.28, w: 1.7, h: 0.3, fontFace: BF, fontSize: 12, bold: true, color, align: "center", margin: 0, isTextBox: true });
    s.addText(a1, { x, y: 1.62, w: 1.7, h: 0.55, fontFace: HF, fontSize: 28, bold: true, color: TEXT, align: "center", margin: 0, isTextBox: true });
    s.addText("median fitted a₁", { x, y: 2.15, w: 1.7, h: 0.25, fontFace: BF, fontSize: 10.5, color: MUTED, align: "center", margin: 0, isTextBox: true });
    s.addText(e, { x, y: 2.5, w: 1.7, h: 0.55, fontFace: HF, fontSize: 28, bold: true, color: TEXT, align: "center", margin: 0, isTextBox: true });
    s.addText(note, { x: x + 0.05, y: 3.03, w: 1.6, h: 0.7, fontFace: BF, fontSize: 10.5, color: MUTED, align: "center", margin: 0, isTextBox: true });
  };
  col(6.05, "lags 1, 2", KIEM, "−0.02", "97.7 %", "of the raw energy left in the residual");
  col(7.8, "lags 12, 24", DRHE, "0.40", "63 %", "of the raw energy left in the residual");
  card(s, 6.05, 3.95, 3.45, 1.1, WHITE);
  para(s, [{ text: "A fitted model's worst case is “predict nothing”; a fixed model's is “predict wrongly”. ", options: { bold: true } },
    { text: "On the right axis LPC's residuals are the smaller of the two (4.102 vs 4.240)." }], 6.05, 3.97, 3.45, 1.08, { fontSize: 11.5 });
  source(s, "Five audit frames; coefficient statistics over all 51,200 fitted sets (50 frames × 128 bins × 4 RX × I/Q).");
  pageNo(s, n);
  s.addNotes("With lags 1,2 Yule-Walker finds almost no correlation, so it picks coefficients near zero - which IS no prediction. LPC's residuals (4.543 bits) are actually slightly better than raw (4.586); it only loses because it pays 0.167 bits/value to send its coefficient table. DRHE's filters are fixed, so it keeps extrapolating a phase trend that is not there. On the right axis LPC's residuals beat DRHE's; DRHE only wins on ratio because it has no side information.");
}

// =====================================================================
// 8. Per-frame
{
  const s = pres.addSlide(); n++;
  kicker(s, "2 · DRHE vs LPC", LPC);
  title(s, "The correction holds on every one of the 50 frames");
  const labels = D.perframe[0].map((_, i) => (i % 5 === 0 ? String(i) : " "));
  s.addChart(pres.charts.LINE, [
    { name: "DRHE, lag 12", labels, values: D.perframe[2] },
    { name: "LPC, lags 12, 24", labels, values: D.perframe[3] },
    { name: "LPC, lags 1, 2", labels, values: D.perframe[1] },
    { name: "DRHE, lag 1", labels, values: D.perframe[0] },
  ], ax({ x: 0.35, y: 1.15, w: 9.3, h: 3.55, chartColors: [DRHE, LPC, LPC_T, DRHE_T], lineSize: 2, lineDataSymbol: "none",
    valAxisMinVal: 2.9, valAxisMaxVal: 3.9, valAxisMajorUnit: 0.1, valAxisLabelFormatCode: "0.0", showLegend: true, legendPos: "r",
    catAxisTitle: "frame", showCatAxisTitle: true, catAxisTitleColor: MUTED, catAxisTitleFontSize: 10,
    valAxisTitle: "compression ratio", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10 }));
  s.addText([{ text: "Means: ", options: { bold: true } }, { text: "DRHE 3.310 → 3.751 (+13.3 %)   ·   LPC 3.385 → 3.697 (+9.2 %)   ·   MaxDiff = 0 on every frame" }],
    { x: 0.5, y: 4.78, w: 9, h: 0.35, fontFace: BF, fontSize: 12.5, color: TEXT, margin: 0, isTextBox: true });
  source(s, "Vitis HLS C-simulation, 4 RX. Light lines: as built; dark lines: corrected.");
  pageNo(s, n);
  s.addNotes("The corrected designs sit above their baselines on every frame, not only on average, and the shape of the frame-to-frame variation (scene content) is preserved - consistent with better prediction rather than a constant shift.");
}

// =====================================================================
// 9. Head to head
{
  const s = pres.addSlide(); n++;
  kicker(s, "2 · DRHE vs LPC", LPC);
  title(s, "Level on ratio; DRHE wins on structure");
  const H = (t, c) => ({ text: t, options: { bold: true, color: c || MUTED } });
  const B = (t) => ({ text: t, options: { bold: true } });
  const P = (t) => ({ text: t });
  const rows = [
    [H(""), H("DRHE, lag 12", DRHE), H("LPC, lags 12, 24", LPC)],
    [P("Compression ratio (Kiem's dictionary)"), B("3.751"), P("3.697")],
    [P("Lossless (50 frames, csim + cosim)"), P("yes"), P("yes")],
    [P("LUT / FF (post-route)"), P("34,804 / 23,514"), B("34,503 / 20,186")],
    [P("BRAM_18K / DSP"), B("80 / 132"), P("216 / 158")],
    [P("Fmax (MHz)"), B("131.0"), P("106.3")],
    [P("Frame latency (cycles)"), B("61,253"), P("325,166")],
    [P("Frame buffer"), B("none"), P("3.0 Mibit")],
    [P("First output"), B("immediately"), P("after a full frame")],
    [P("Side information"), B("none"), P("1.04 %")],
  ];
  s.addTable(rows, { x: 0.5, y: 1.2, w: 5.9, colW: [2.7, 1.6, 1.6], fontFace: BF, fontSize: 12, color: TEXT, rowH: 0.36,
    border: { type: "solid", pt: 0.5, color: RULE }, align: "left" });
  card(s, 6.7, 1.2, 2.8, 3.8, TINT);
  para(s, [{ text: "Verdict", options: { bold: true, fontSize: 15, color: DRHE, breakLine: true } },
    { text: "Logic is almost level once implemented — the HLS estimate that made LPC look 30 % cheaper did not survive routing.", options: { breakLine: true } },
    { text: "LPC's real costs are memory and a frame of latency: it cannot emit a bit until the whole frame is in.", options: { breakLine: true } },
    { text: "For a streaming sensor-edge IP, DRHE is the better design.", options: { bold: true } }], 6.78, 1.3, 2.65, 3.65, { fontSize: 12.5, paraSpaceAfter: 8 });
  source(s, "xcku5p-ffvb676-2-e, 100 MHz target, Vivado out-of-context place and route. Bold = better of the two.");
  pageNo(s, n);
  s.addNotes("Both close timing at 100 MHz. LPC's division runs only 1024 times a frame, so it was never the expensive part - the float atan2 and sin/cos in DRHE are. LPC needs the whole frame because its coefficients are computed from autocorrelations over all ramps.");
}

// =====================================================================
// 10. Dictionary explained
{
  const s = pres.addSlide(); n++;
  kicker(s, "3 · The Huffman dictionary", RED);
  title(s, "Kiem's dictionary charges at least 4 bits");
  const cats = ["0", "1", "2", "3", "4", "5", "6", "7", "8"];
  s.addChart(pres.charts.BAR, [{ name: "LPC lags 12,24 residuals", labels: cats, values: [23.77, 38.50, 30.67, 5.81, 0.91, 0.19, 0.07, 0.07, 0.01] }],
    ax({ x: 0.35, y: 1.2, w: 4.5, h: 3.3, barDir: "col", chartColors: [LPC], barGapWidthPct: 45, showValue: true, dataLabelPosition: "outEnd",
      dataLabelFormatCode: "0.0", dataLabelFontSize: 9.5, dataLabelColor: TEXT, valAxisMinVal: 0, valAxisMaxVal: 45, valAxisMajorUnit: 10,
      showLegend: false, showTitle: true, title: "Where corrected-LPC residuals fall (% of values)", titleFontFace: BF, titleFontSize: 11, titleColor: MUTED,
      catAxisTitle: "S4 category (bits needed for |residual|)", showCatAxisTitle: true, catAxisTitleColor: MUTED, catAxisTitleFontSize: 10 }));
  s.addChart(pres.charts.BAR, [
    { name: "Kiem's fixed dictionary", labels: cats, values: [4, 4, 4, 5, 6, 10, 12, 14, 16] },
    { name: "Re-derived for LPC", labels: cats, values: [3, 2, 4, 7, 9, 11, 13, 15, 17] },
  ], ax({ x: 5.0, y: 1.2, w: 4.65, h: 3.3, barDir: "col", barGrouping: "clustered", chartColors: [KIEM, RED], barGapWidthPct: 45,
    valAxisMinVal: 0, valAxisMaxVal: 18, valAxisMajorUnit: 4, showLegend: true, legendPos: "t", showValue: false,
    showTitle: true, title: "Bits to code one value in each category", titleFontFace: BF, titleFontSize: 11, titleColor: MUTED,
    catAxisTitle: "S4 category", showCatAxisTitle: true, catAxisTitleColor: MUTED, catAxisTitleFontSize: 10 }));
  card(s, 0.5, 4.6, 9.0, 0.55, TINT);
  s.addText([{ text: "Cost = Huffman codeword for the category + one payload bit per category level. ", options: { bold: true } },
    { text: "Kiem's short codes sit on categories 2–4 (his residuals were 6–8 LSB). 93 % of corrected-LPC residuals are in 0–2, all charged 4 bits, so CR can never exceed 4.0." }],
    { x: 0.6, y: 4.62, w: 8.8, h: 0.5, fontFace: BF, fontSize: 11.5, color: TEXT, margin: 0, valign: "middle", isTextBox: true });
  pageNo(s, n);
  s.addNotes("Each residual is coded as a category S4 (how many bits its magnitude needs) plus that many raw bits. Kiem's dictionary gives two-bit codes to categories 2, 3 and 4, which is right for residuals of 6-8 LSB - the size his single-transmitter recordings produced. After the lag fix the residuals are much smaller: category 0 (exactly zero) and category 1 hold 62% of LPC's values but still cost 4 bits each. A dictionary built for these residuals gives category 1 a one-bit code: 2 bits total.");
}

// =====================================================================
// 11. Re-derived dictionary results
{
  const s = pres.addSlide(); n++;
  kicker(s, "3 · The Huffman dictionary", RED);
  title(s, "A matched dictionary puts LPC ahead");
  const labels = ["No pred.", "DRHE lag 1", "LPC 1,2", "DRHE lag 12", "LPC 12,24"];
  s.addChart(pres.charts.BAR, [
    { name: "Kiem's fixed dictionary", labels, values: [3.478, 3.309, 3.384, 3.748, 3.691] },
    { name: "Dictionary re-derived on frames 0–4", labels, values: [3.720, 3.419, 3.640, 4.207, 4.371] },
  ], ax({ x: 0.35, y: 1.15, w: 6.0, h: 3.95, barDir: "col", barGrouping: "clustered", chartColors: [KIEM, RED], barGapWidthPct: 50,
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.000", dataLabelFontSize: 9, dataLabelColor: TEXT,
    valAxisMinVal: 0, valAxisMaxVal: 5, valAxisMajorUnit: 1, showLegend: true, legendPos: "b",
    valAxisTitle: "CR on held-out frames 5–49", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10, catAxisLabelFontSize: 10.5 }));
  const stat = (y, big, color, label) => {
    s.addText(big, { x: 6.6, y, w: 2.9, h: 0.6, fontFace: HF, fontSize: 32, bold: true, color, margin: 0, isTextBox: true });
    s.addText(label, { x: 6.6, y: y + 0.58, w: 2.9, h: 0.3, fontFace: BF, fontSize: 11.5, color: MUTED, margin: 0, isTextBox: true });
  };
  stat(1.2, "+18.4 %", LPC, "LPC, lags 12, 24: 3.691 → 4.371");
  stat(2.15, "+12.2 %", DRHE, "DRHE, lag 12: 3.748 → 4.207");
  card(s, 6.6, 3.2, 2.9, 1.85, TINT);
  para(s, bullets([
    "Largest gain where residuals are smallest; 3–8 % for the uncorrected designs.",
    "Trained on 5 frames, tested on the other 45; every category keeps a code, so it stays lossless.",
    "Hardware change: a 16-entry ROM (not yet synthesised).",
  ], 11.5), 6.62, 3.25, 2.85, 1.8);
  pageNo(s, n);
  s.addNotes("The dictionary is a design-time constant, so the fair test is: build it on frames 0-4, freeze it, and measure on the held-out 45 frames. LPC benefits most because its residuals are the smallest and it can now spend 2 bits on its commonest symbol. With Kiem's dictionary DRHE led by 1.5%; with matched dictionaries LPC leads by 3.9%. So the ratio ranking between the two depends on the coder - but DRHE is still the recommended design for streaming, memory and latency reasons.");
}

// =====================================================================
// 12. How close to the limit
{
  const s = pres.addSlide(); n++;
  kicker(s, "3 · The Huffman dictionary", RED);
  title(s, "The gap is the dictionary, not the scheme");
  const labels = ["DRHE, lag 12", "LPC, lags 12, 24"];
  s.addChart(pres.charts.BAR, [
    { name: "Kiem's fixed dictionary", labels, values: [4.240, 4.102] },
    { name: "Ideal S4 dictionary", labels, values: [3.711, 3.242] },
    { name: "Order-0 entropy (floor)", labels, values: [3.516, 3.040] },
  ], ax({ x: 0.35, y: 1.15, w: 5.4, h: 3.95, barDir: "col", barGrouping: "clustered", chartColors: [KIEM, RED, REF], barGapWidthPct: 60,
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.000", dataLabelFontSize: 10, dataLabelColor: TEXT,
    valAxisMinVal: 0, valAxisMaxVal: 5, valAxisMajorUnit: 1, showLegend: true, legendPos: "b",
    valAxisTitle: "bits per value, residuals only (lower is better)", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10 }));
  const rows = [
    [{ text: "Fixed coder above entropy", options: { bold: true, color: MUTED, colspan: 2 } }],
    [{ text: "Raw FX16 codes" }, { text: "12.0 %", options: { align: "right" } }],
    [{ text: "DRHE lag 1 (as built)" }, { text: "6.2 %", options: { align: "right" } }],
    [{ text: "DRHE lag 12" }, { text: "20.6 %", options: { align: "right", bold: true } }],
    [{ text: "LPC lags 12, 24" }, { text: "34.9 %", options: { align: "right", bold: true } }],
  ];
  s.addTable(rows, { x: 6.1, y: 1.25, w: 3.4, colW: [2.3, 1.1], fontFace: BF, fontSize: 12, color: TEXT, rowH: 0.33, border: { type: "solid", pt: 0.5, color: RULE } });
  card(s, 6.1, 3.15, 3.4, 1.9, TINT);
  para(s, [{ text: "An S4 code matched to the data sits only 2–7 % above entropy. ", options: { bold: true } },
    { text: "The coder looked near-optimal before the fix (6.2 %) because the residuals it saw were the size it was built for. Fixing the predictor moved the bottleneck into the dictionary." }],
    6.15, 3.2, 3.3, 1.8, { fontSize: 11.5 });
  source(s, "Five audit frames, 4 RX, residual bits only (LPC coefficient table excluded).");
  pageNo(s, n);
  s.addNotes("Order-0 entropy is the least any coder that treats values independently can spend. The ideal S4 column is a Huffman code built on the design's own category counts - still the same hardware-friendly S4 + APPEND scheme. It is within 2-7% of entropy, so the scheme is fine; the fixed dictionary is what costs 20-35% on the corrected residuals.");
}

// =====================================================================
// 13. Kiem baseline
{
  const s = pres.addSlide(); n++;
  kicker(s, "4 · Comparison with Kiem", KIEM);
  title(s, "The baseline: Kiem's thesis, and how this work differs");
  const colBox = (x, head, color, fill, items) => {
    card(s, x, 1.2, 4.35, 3.3, fill);
    s.addText(head, { x: x + 0.15, y: 1.3, w: 4.05, h: 0.4, fontFace: HF, fontSize: 16, bold: true, color, margin: 0, isTextBox: true });
    para(s, bullets(items, 13), x + 0.1, 1.8, 4.15, 2.65, { paraSpaceAfter: 6 });
  };
  colBox(0.5, "Kiem (TU Graz, 2025)", KIEM, "F7EDEF", [
    "One MMIC, one transmitter, 4 RX, 512 × 512, 14-bit ADC.",
    "All compression results from his own recordings (not public); a synthetic scene only for illustration.",
    "Design-space study → DRHE: CR 3.25 in simulation, 3.17 on hardware.",
    "LPC-Huffman (raw ADC, fast time) ruled out without being run.",
    "Fixed-point HLS on a Zynq XCZU3CG at 100 MHz.",
  ]);
  colBox(5.15, "This thesis", DRHE, "E4F1F6", [
    "Public ColoRadar cascade: 12 TX in TDM, 16 RX, 4 RX to hardware.",
    "DRHE exactly as Kiem specified, plus a slow-time LPC sharing his coder.",
    "Both with decoders, bit-exact over 50 frames, placed and routed on xcku5p.",
    "Kiem's MATLAB simulation rebuilt from his text alone and run with every coder.",
    "Every Kiem result set against ours, one by one.",
  ]);
  pageNo(s, n);
  s.addNotes("Earlier project documents said Kiem tested on synthetic data. That was wrong: every compression number he publishes is from his CTRX recordings. Because the data is private, the replication uses his synthetic Table 3.2 scene and calibrates the noise level.");
}

// =====================================================================
// 14. Replication sweep
{
  const s = pres.addSlide(); n++;
  kicker(s, "4 · Comparison with Kiem", KIEM);
  title(s, "Kiem's 3.25 depends on the noise level");
  const labels = D.kr.NF_target_dBFS.map((v) => String(v));
  s.addChart(pres.charts.LINE, [
    { name: "DRHE, Kiem's coder (R4S4 + RLE)", labels, values: D.kr.DRHE_RLE },
    { name: "Slow-time LPC (this thesis)", labels, values: D.kr.LPC_FFT },
    { name: "LPC-Huffman on raw ADC (Kiem's LPC)", labels, values: D.kr.LPC_raw },
    { name: "Kiem's reported CR, 3.25", labels, values: labels.map(() => 3.25) },
  ], ax({ x: 0.35, y: 1.15, w: 5.9, h: 3.95, chartColors: [DRHE, LPC, KIEM, REF], lineSize: 2, lineDataSymbol: "circle", lineDataSymbolSize: 5,
    valAxisMinVal: 1, valAxisMaxVal: 5.5, valAxisMajorUnit: 0.5, valAxisLabelFormatCode: "0.0", showLegend: true, legendPos: "b",
    catAxisTitle: "noise floor after NCI (dBFS) — Kiem's scene, 1 TX", showCatAxisTitle: true, catAxisTitleColor: MUTED, catAxisTitleFontSize: 10,
    valAxisTitle: "compression ratio", showValAxisTitle: true, valAxisTitleColor: MUTED, valAxisTitleFontSize: 10 }));
  const c = (y, h, head, body, fill, col) => {
    card(s, 6.5, y, 3.0, h, fill);
    para(s, [{ text: head, options: { bold: true, color: col, breakLine: true } }, { text: body }], 6.55, y + 0.04, 2.9, h - 0.06, { fontSize: 11.5, paraSpaceAfter: 2 });
  };
  c(1.2, 1.2, "Reproduced at −87.9 dBFS", "3.25 with run-length coding, 3.24 without — his exact pattern. FX16 noise there: 4.6 LSB.", "E4F1F6", DRHE);
  c(2.5, 1.15, "His scene at −75 dBFS gives 2.28", "His 3.25 comes from recordings whose residuals matched his dictionary (6–8 LSB).", "F7EDEF", KIEM);
  c(3.75, 1.3, "Our early 1.1, explained", "A 4× FX16 scaling difference plus a noise floor ~17 dB higher than the level that gives 3.25.", TINT, TEXT);
  source(s, "kiem_replication/results/noise_sweep.csv. Slow-time LPC uses Kiem's fixed dictionary; DRHE uses his R4S4 + RLE coder with an ideal dictionary.");
  pageNo(s, n);
  s.addNotes("On a white-noise scene the CR depends almost only on the noise size in FX16 LSBs. Bisection finds 3.25 at -87.9 dBFS. That operating point was chosen, not predicted - it shows the chain is understood, not that his data behaves the same. His LPC-Huffman stays at 1.2-1.75 everywhere because it codes the raw ADC noise that the FX16 step throws away; our slow-time LPC tracks DRHE.");
}

// =====================================================================
// 15. Result-by-result table
{
  const s = pres.addSlide(); n++;
  kicker(s, "4 · Comparison with Kiem", KIEM);
  title(s, "Kiem's results against ours, one by one");
  const H = (t) => ({ text: t, options: { bold: true, color: MUTED, fill: { color: "F3F5F7" } } });
  const V = (t, c) => ({ text: t, options: { bold: true, color: c } });
  const rows = [
    [H("Result"), H("Kiem"), H("This thesis"), H("Verdict")],
    ["DRHE algorithm (his §3.5.3)", "specified", "identical residuals and bits, two independent implementations", V("same", DRHE)],
    ["Run-length coding adds little", "3.25 vs 3.24", "3.25 vs 3.24 (replica); 3.466 vs 3.457 on ColoRadar", V("agrees", DRHE)],
    ["DRHE compression ratio", "3.25 sim · 3.17 HW", "3.310 (lag 1) · 3.751 (lag 12) on ColoRadar", V("not comparable", MUTED)],
    ["Fixed dictionary costs little", "yes, on his data", "0.3 % on his scene; 12–18 % on corrected ColoRadar", V("data-dependent", LPC)],
    ["LPC is less promising", "not run", "his LPC-Huffman 1.32–1.54 on his scene; our LPC 3.697 vs DRHE 3.751", V("true for his LPC", LPC)],
    ["DRHE best of his design space", "yes", "yes among lossless; BAQ 3.76 but 10.4 % missed detections", V("agrees", DRHE)],
  ].map((r, i) => i === 0 ? r : r.map((c) => (typeof c === "string" ? { text: c } : c)));
  s.addTable(rows, { x: 0.5, y: 1.2, w: 9.0, colW: [2.35, 1.5, 3.65, 1.5], fontFace: BF, fontSize: 11.5, color: TEXT,
    rowH: [0.32, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], valign: "middle", border: { type: "solid", pt: 0.5, color: RULE } });
  card(s, 0.5, 4.72, 9.0, 0.45, TINT);
  s.addText([{ text: "3.30 ≈ 3.25 is a coincidence of two mechanisms: ", options: { bold: true } },
    { text: "ours is mostly unused int16 headroom (1.64×) and sparsity (2.13×); his is a dictionary matched to his residual size." }],
    { x: 0.6, y: 4.72, w: 8.8, h: 0.45, fontFace: BF, fontSize: 11, color: TEXT, margin: 0, valign: "middle", isTextBox: true });
  pageNo(s, n);
  s.addNotes("'Not comparable' means different data and different radar, so neither number tells you which implementation is better. The closeness of 3.30 to 3.25 was taken early on as confirmation; the implementation is correct, but for other reasons. Two different algorithms share the name LPC: Kiem's judgement of his fast-time raw-ADC version is borne out; it does not apply to the slow-time LPC built here.");
}

// =====================================================================
// 16. Hardware vs Kiem
{
  const s = pres.addSlide(); n++;
  kicker(s, "4 · Comparison with Kiem", KIEM);
  title(s, "Hardware: one cause for every difference");
  const H = (t, c) => ({ text: t, options: { bold: true, color: c || MUTED, fill: { color: "F3F5F7" } } });
  const P = (t, o) => ({ text: t, options: o || {} });
  const rows = [
    [H("Post-route"), H("Kiem (published)", KIEM), H("Replica of Kiem (our tools)"), H("DRHE-1 (ours)", DRHE)],
    [P("LUT"), P("45,892"), P("17,141"), P("35,343")],
    [P("FF"), P("9,243"), P("5,050"), P("23,546")],
    [P("DSP"), P("44"), P("48"), P("132")],
    [P("BRAM (36 Kb tiles)"), P("10"), P("10"), P("20")],
    [P("Initiation interval"), P("1"), P("1"), P("2")],
    [P("Clock"), P("100 MHz met"), P("129.5 MHz"), P("135.5 MHz")],
    [P("Throughput"), P("11.92 Gibit/s (theoretical)"), P("11.54 Gbit/s measured"), P("5.14 Gbit/s measured")],
  ];
  s.addTable(rows, { x: 0.5, y: 1.2, w: 5.9, colW: [1.55, 1.55, 1.45, 1.35], fontFace: BF, fontSize: 11, color: TEXT, rowH: 0.4,
    valign: "middle", border: { type: "solid", pt: 0.5, color: RULE } });
  card(s, 6.7, 1.2, 2.8, 3.25, TINT);
  para(s, bullets([
    [{ text: "Float datapath ", options: { bold: true } }, { text: "is most of the logic, every extra DSP and 2× the BRAM (32-bit state)." }],
    [{ text: "Fixed-point DRHE ", options: { bold: true } }, { text: "compresses within 0.07 % of the float design." }],
    [{ text: "II = 2 ", options: { bold: true } }, { text: "is one extra state-clearing write per cycle; the ladder reaches II = 1." }],
    [{ text: "Throughput gap is exactly 2× ", options: { bold: true } }, { text: "theoretical vs theoretical; his figure is in binary units." }],
  ], 11.5), 6.75, 1.28, 2.7, 3.1, { paraSpaceAfter: 6 });
  source(s, "Replica and DRHE-1 built with Vitis/Vivado 2026.1 on xcku5p; Kiem: Vitis 2022.2, XCZU3CG. A ladder of single-change variants links the replica to DRHE-1.");
  pageNo(s, n);
  s.addNotes("Early comparisons put HLS estimates against Kiem's post-route numbers and made our design look 2.5x bigger. Implemented, DRHE-1 uses fewer LUTs than his published IP. Against a faithful replica of his design built with our tools, the differences come from the floating-point datapath (chosen so HLS would match MATLAB exactly), 32-bit state words, and clearing state every frame. Recommendation: move DRHE to fixed point.");
}

// =====================================================================
// 17. Takeaways
{
  const s = pres.addSlide(); n++;
  s.background = { color: INK };
  s.addText("What to take away", { x: 0.6, y: 0.45, w: 8.8, h: 0.6, fontFace: HF, fontSize: 30, bold: true, color: WHITE, margin: 0, isTextBox: true });
  const items = [
    [DRHE, "Predict along the right axis.", "On a 12-TX TDM cascade the slow-time neighbour is ramp m − 12. At lag 1 both predictors lost to no prediction; at lag 12 they gain 7.8 % (DRHE) and 6.3 % (LPC), still bit-exact."],
    [LPC, "DRHE and LPC are level on ratio.", "LPC's residuals are smaller, DRHE has no side information. DRHE wins on structure: no frame buffer, first output immediately, a fifth of the latency."],
    [RED, "The dictionary is now the bottleneck.", "Kiem's 4-bit floor caps CR at 4. A matched dictionary gives DRHE 4.21 and LPC 4.37 on held-out frames."],
    [KIEM, "Kiem's results are reproduced and explained.", "His DRHE is ours to the bit; his 3.25 is reproduced at one noise level; our 3.30 ≈ 3.25 is a coincidence of different mechanisms."],
  ];
  items.forEach(([c, h, b], i) => {
    const y = 1.35 + i * 0.95;
    s.addShape(pres.shapes.OVAL, { x: 0.6, y: y + 0.05, w: 0.42, h: 0.42, fill: { color: c }, line: { color: c } });
    s.addText(String(i + 1), { x: 0.6, y: y + 0.05, w: 0.42, h: 0.42, fontFace: HF, fontSize: 15, bold: true, color: WHITE, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText([{ text: h, options: { bold: true, color: WHITE, fontSize: 15, breakLine: true } }, { text: b, options: { color: "C3CFDB", fontSize: 12 } }],
      { x: 1.2, y: y - 0.02, w: 8.3, h: 0.9, fontFace: BF, margin: 0, valign: "top", isTextBox: true });
  });
  s.addNotes("Recommendations for future work: adopt a matched dictionary (16-entry ROM), move DRHE to fixed point, report a no-prediction baseline alongside any compression ratio, and make the FX16 scale adaptive so the ratio reflects the algorithm rather than capture gain.");
}

pres.writeFile({ fileName: "thesis_results.pptx" }).then(() => console.log("written"));
