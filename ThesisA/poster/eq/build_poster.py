"""Fill the UNSW EET thesis poster template (A0 portrait) with the thesis content.
Numbers come from make_poster_figs.m outputs (poster_*.csv); figures are its PNGs."""
import csv, json, re, sys
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.dml import MSO_LINE_DASH_STYLE
from PIL import Image

HERE = sys.argv[1]
FIG = HERE + '/figs/'
prs = Presentation(HERE + '/in/template.pptx')
s = prs.slides[0]

# ---------------- header: use the master's UNSW banner (as in the example poster) ----------------
# The title layout puts a second banner image over the master's one, stretched
# from 4.2:1 to 5.4:1. Remove it, and the master's placeholder "BE Thesis" text.
for shp in list(s.slide_layout.shapes):
    if shp.shape_type == 13:                      # picture
        shp._element.getparent().remove(shp._element)
for shp in list(s.slide_layout.slide_master.shapes):
    if shp.name == 'TextBox 2':
        shp._element.getparent().remove(shp._element)

# ---------------- numbers from MATLAB ----------------
def rows(f):
    with open(FIG + f) as fh:
        return {r[next(iter(r))]: r for r in csv.DictReader(fh)}
S2, HW = rows('poster_stage2.csv'), rows('poster_hardware.csv')
crD, crL = float(S2['DRHE']['CR_Total']), float(S2['LPC']['CR_Total'])
FRAME_KB = 128 * 192 * 4 * 4 / 1000            # 393 KB
encD_ms = float(HW['DRHE']['EncCyclesPerFrame']) / 1e5
encL_ms = float(HW['LPC']['EncCyclesPerFrame']) / 1e5
lutD = 100 * (float(HW['DRHE']['Encoder_LUT_FF_BRAM_DSP_1']) + float(HW['DRHE']['Decoder_LUT_FF_BRAM_DSP_1'])) / 216960
lutL = 100 * (float(HW['LPC']['Encoder_LUT_FF_BRAM_DSP_1']) + float(HW['LPC']['Decoder_LUT_FF_BRAM_DSP_1'])) / 216960

# ---------------- clear the template's sample content ----------------
keep = {'TextBox 5', 'TextBox 29'}
for sh in list(s.shapes):
    if sh.name not in keep:
        sh._element.getparent().remove(sh._element)

def set_runs(shape, texts):
    for p, t in zip(shape.text_frame.paragraphs, texts):
        runs = p.runs
        runs[0].text = t
        for r in runs[1:]:
            r.text = ''
for sh in s.shapes:
    if sh.name == 'TextBox 5':
        set_runs(sh, ['Comparison and Implementation of Data Compression Methods for SoC-based Radar Systems',
                      'Author: Jordan Mohindra', 'Supervisor: A/Prof Beena Ahmed'])
    if sh.name == 'TextBox 29':                   # '2015 Thesis Project' style of the example
        set_runs(sh, ['2026 Thesis Project'])
        for r in sh.text_frame.paragraphs[0].runs:
            r.font.bold = False; r.font.size = Pt(72)
        sh.left, sh.top, sh.width = Emu(10491549), Emu(862280), Emu(13500000)
    if sh.name == 'TextBox 5':
        sh.top = Inches(4.45)

# ---------------- helpers ----------------
NAVY = RGBColor(0x1F, 0x3A, 0x5F)
BLUE = RGBColor(0xB9, 0xCD, 0xE5)      # template box colour
PALE = RGBColor(0xE4, 0xEC, 0xF6)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
BLACK = RGBColor(0, 0, 0)
YELLOW = RGBColor(0xFF, 0xE0, 0x66)
GREEN = RGBColor(0xD8, 0xEB, 0xC8)
FONT = 'Arial'

def box(x, y, w, h, fill=None, line=None, lw=10, radius=0.04, shape=MSO_SHAPE.ROUNDED_RECTANGLE, dash=False):
    b = s.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        b.adjustments[0] = radius
    if fill is None:
        b.fill.background()
    else:
        b.fill.solid(); b.fill.fore_color.rgb = fill
    if line is None:
        b.line.fill.background()
    else:
        b.line.color.rgb = line; b.line.width = Pt(lw)
        if dash:
            b.line.dash_style = MSO_LINE_DASH_STYLE.DASH
    b.shadow.inherit = False
    b.text_frame.text = ''
    return b

def runs_of(text):
    """'**bold** plain' -> [(text, bold)]"""
    out = []
    for part in re.split(r'(\*\*[^*]+\*\*)', text):
        if not part:
            continue
        out.append((part[2:-2], True) if part.startswith('**') else (part, False))
    return out

def text(x, y, w, h, paras, size=24, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, color=BLACK, bullets=False, space=10, shape=None):
    tb = shape if shape is not None else s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    for side in ('margin_left', 'margin_right', 'margin_top', 'margin_bottom'):
        setattr(tf, side, Inches(0.08))
    for i, para in enumerate(paras):
        if isinstance(para, str):
            para = {'t': para}
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = para.get('align', align)
        p.space_after = Pt(para.get('space', space))
        if bullets and para.get('bullet', True):
            pPr = p._p.get_or_add_pPr()
            pPr.set('marL', str(Emu(Inches(0.35)))); pPr.set('indent', str(-Emu(Inches(0.35))))
            from pptx.oxml.ns import qn
            bu = pPr.makeelement(qn('a:buChar'), {'char': '•'})
            pPr.append(bu)
        for t, b in runs_of(para['t']):
            r = p.add_run(); r.text = t
            f = r.font; f.name = FONT; f.size = Pt(para.get('size', size)); f.bold = b or para.get('bold', False)
            f.italic = para.get('italic', False)
            f.color.rgb = para.get('color', color)
    return tb

def heading(x, y, w, t, size=36):
    return text(x, y, w, 0.7, [{'t': t, 'bold': True, 'size': size}], size=size)

def picture(name, x, y, h=None, w=None):
    im = Image.open(FIG + name); ar = im.width / im.height
    if h is not None:
        w = h * ar
    else:
        h = w / ar
    s.shapes.add_picture(FIG + name, Inches(x), Inches(y), Inches(w), Inches(h))
    return w, h

def arrow(x, y, w, h, color=NAVY):
    a = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW, Inches(x), Inches(y), Inches(w), Inches(h))
    a.fill.solid(); a.fill.fore_color.rgb = color; a.line.fill.background(); a.shadow.inherit = False
    return a

def circle_num(x, y, d, n):
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x), Inches(y), Inches(d), Inches(d))
    c.fill.solid(); c.fill.fore_color.rgb = NAVY; c.line.fill.background(); c.shadow.inherit = False
    text(0, 0, 0, 0, [{'t': str(n), 'bold': True, 'size': 36, 'color': WHITE}], align=PP_ALIGN.CENTER,
         anchor=MSO_ANCHOR.MIDDLE, shape=c)

X0, X1 = 0.85, 32.26
W = X1 - X0
GAP = 0.45

# ================= ROW A: why compress / what are the algorithms / hardware photo =================
yA, hA = 9.53, 6.6
wA1, wA3 = 12.6, 6.0
wA2 = W - wA1 - wA3 - 2 * GAP
xA2, xA3 = X0 + wA1 + GAP, X0 + wA1 + wA2 + 2 * GAP

box(X0, yA, wA1, hA, fill=BLUE)
heading(X0 + 0.35, yA + 0.25, wA1 - 0.7, 'Why compress radar data?')
text(X0 + 0.35, yA + 1.05, wA1 - 0.7, 2.6, [
    'Cascaded MIMO radars (here **12 transmitters × 16 receivers**) produce **3.1 MB of raw data in every frame**, frame after frame.',
    'The link to the car\'s central computer (SoC) becomes the bottleneck: bandwidth, power and delay.',
    'So: **compress at the sensor, losslessly**. Less data on the link, **identical** data after decoding, so target detection is unchanged.'],
    bullets=True)
# compression graphic: radar -> FPGA compress -> thin link -> SoC decompress
gy, gh = yA + 3.95, 1.85
bw = 2.55
xs = [X0 + 0.35, X0 + 0.35 + bw + 1.15, X0 + 0.35 + 2 * (bw + 1.15)]
labels = [('Radar', f'{FRAME_KB:.0f} KB / frame'), ('FPGA', 'compress'), ('SoC', 'decompress')]
fills = [WHITE, YELLOW, WHITE]
for (t1, t2), xx, fc in zip(labels, xs, fills):
    b = box(xx, gy, bw, gh, fill=fc, line=NAVY, lw=3, radius=0.12)
    text(0, 0, 0, 0, [{'t': t1, 'bold': True, 'size': 28, 'align': PP_ALIGN.CENTER, 'space': 2},
                      {'t': t2, 'size': 22, 'align': PP_ALIGN.CENTER}], anchor=MSO_ANCHOR.MIDDLE, shape=b)
arrow(xs[0] + bw + 0.1, gy + gh / 2 - 0.45, 0.95, 0.9)                 # fat: raw data
arrow(xs[1] + bw + 0.1, gy + gh / 2 - 0.13, 0.95, 0.26)                # thin: compressed
text(xs[1] + bw + 0.575 - 0.85, gy + gh / 2 + 0.2, 1.7, 0.6, [{'t': f'{FRAME_KB / crD:.0f} KB', 'bold': True, 'size': 24, 'align': PP_ALIGN.CENTER}])
text(xs[2] - 0.2, gy + gh + 0.05, bw + 0.4, 0.5, [{'t': 'same data, bit for bit', 'italic': True, 'size': 22, 'align': PP_ALIGN.CENTER}])

box(xA2, yA, wA2, hA, fill=BLUE)
heading(xA2 + 0.35, yA + 0.25, wA2 - 0.7, 'What are DRHE and LPC?')
EQS = json.load(open(HERE + '/eq/sizes.json'))
EQK = 0.82                                          # every equation at 0.82 x 30 pt ~ 25 pt

def eq(key, x, y, k=EQK):
    w, h = (v * k for v in EQS['sizes'][key])
    s.shapes.add_picture(HERE + f'/eq/{key}.png', Inches(x), Inches(y), Inches(w), Inches(h))
    return w, h

ix, iw = xA2 + 0.4, wA2 - 0.8
text(ix - 0.08, yA + 1.0, iw, 0.8, [
    {'t': 'Both **predict** each sample xₘ from earlier ramps of the **same transmitter** (L = 12 ramps back). Only the small **prediction error** is Huffman-coded:', 'size': 22}])
eq('c1', ix + (iw - EQS['sizes']['c1'][0] * 0.95) / 2, yA + 1.9, k=0.95)
colW = (iw - 0.4) / 2
cxs = [ix, ix + colW + 0.4]
yh = yA + 2.55
s.shapes.add_connector(1, Inches(cxs[1] - 0.2), Inches(yh + 0.05), Inches(cxs[1] - 0.2), Inches(yA + hA - 0.3)).line.color.rgb = NAVY
text(cxs[0] - 0.08, yh, colW, 0.55, [{'t': '**DRHE**', 'size': 28}])
text(cxs[1] - 0.08, yh, colW, 0.55, [{'t': '**LPC**', 'size': 28}])
# DRHE: words + the two key equations
yd = yh + 0.6
text(cxs[0] - 0.08, yd, colW, 0.8, [{'t': 'Predicts **magnitude A** and **phase φ** separately, with **fixed** filters:', 'size': 22}])
yd += 1.0
_, h = eq('d0', cxs[0] + 0.2, yd, k=0.9); yd += h + 0.15
eq('d1', cxs[0] + 0.2, yd, k=0.9)
# LPC: words + the predictor
yl = yh + 0.6
text(cxs[1] - 0.08, yl, colW, 0.8, [{'t': 'A **weighted sum** of the same range bin’s previous two ramps:', 'size': 22}])
yl += 1.0
_, h = eq('l1', cxs[1] + 0.2, yl, k=0.9); yl += h + 0.15
text(cxs[1] - 0.08, yl, colW, 1.0, [{'t': 'a₁, a₂ are **fitted to the whole frame**, per range bin.', 'size': 22}])
yn = yA + hA - 0.72
text(cxs[0] - 0.08, yn, colW, 0.5, [{'t': 'Past ramps only → **streams**', 'size': 22, 'color': NAVY}])
text(cxs[1] - 0.08, yn, colW, 0.5, [{'t': 'Needs **the whole frame** → waits', 'size': 22, 'color': NAVY}])

pb = box(xA3, yA, wA3, hA, fill=PALE, line=NAVY, lw=4, radius=0.06, dash=True)
text(0, 0, 0, 0, [{'t': '[Photo: KCU116 FPGA board and laptop running the test]', 'italic': True, 'size': 24, 'align': PP_ALIGN.CENTER}],
     anchor=MSO_ANCHOR.MIDDLE, shape=pb)

# ================= ROW B: method -> results =================
yB = yA + hA + 0.5
hB = 24.4
box(X0, yB, W, hB, fill=None, line=BLUE, lw=10, radius=0.025)
text(X0, yB + 0.2, W, 0.8, [{'t': 'Method → Results', 'bold': True, 'size': 44, 'align': PP_ALIGN.CENTER}])

stepX, stepW = X0 + 0.5, 7.9
arrX, arrW = stepX + stepW + 0.25, 1.0
figX = arrX + arrW + 0.3
rowH, figH = 4.52, 4.25
y0 = yB + 1.2

steps = [
    ('Real radar data', 'ColoRadar recordings [1] from a **TI AWR2243 cascade** (12 TX). Range FFT in MATLAB, then **16-bit frames**.'),
    ('Screen 8 algorithms', 'MATLAB: **compression ratio** and **target detection** for every method on **50 frames**.'),
    ('DRHE vs LPC', 'Where does the compression come from? **Huffman coding**, **prediction**, and a **dictionary re-derived** for this data. **The dictionary helps more than the predictor.**'),
    ('Build it in hardware', 'C++ in **Vitis HLS** → **Vivado** → AMD **KCU116** FPGA. Encoder and decoder on the chip.'),
    ('Measure on the board', 'Stream 50 frames through the FPGA, **check every frame is bit-exact**, and time it.'),
]
for i, (title, body) in enumerate(steps):
    y = y0 + i * (rowH + 0.08)
    card = box(stepX, y, stepW, figH, fill=BLUE, radius=0.08)
    circle_num(stepX + 0.3, y + 0.3, 0.95, i + 1)
    text(stepX + 1.45, y + 0.38, stepW - 1.6, 0.8, [{'t': title, 'bold': True, 'size': 32}])
    text(stepX + 0.3, y + 1.35, stepW - 0.5, figH - 1.4, [{'t': body, 'size': 24}])
    arrow(arrX, y + figH / 2 - 0.4, arrW, 0.8)

def row_y(i):
    return y0 + i * (rowH + 0.08)

def callout(x, y, w, h, paras, fill=PALE):
    b = box(x, y, w, h, fill=fill, radius=0.06)
    text(0, 0, 0, 0, paras, anchor=MSO_ANCHOR.MIDDLE, shape=b, size=24)
    b.text_frame.margin_left = b.text_frame.margin_right = Inches(0.3)
    return b

endX = X1 - 0.5
# 1: input
y = row_y(0); w, _ = picture('fig_input.png', figX, y, h=figH)
cx = figX + w + 0.4
cb = callout(cx, y, endX - cx, figH, [
    {'t': f'**Input:** one frame = 128 range bins × 192 ramps × 4 RX, 16-bit I/Q = **{FRAME_KB:.0f} KB**', 'space': 14},
    {'t': f'**Output:** a compressed bitstream of about **{FRAME_KB / crD:.0f} KB** (DRHE). Decompressing it gives back **exactly the same frame**.'}])
cb.text_frame.vertical_anchor = MSO_ANCHOR.TOP; cb.text_frame.margin_top = Inches(0.3)
ew, eh = (v * 0.9 for v in EQS['sizes']['cr'])
ecx = cx + (endX - cx) / 2 - ew - 0.2
eq('cr', ecx, y + figH - eh - 0.3, k=0.9)
text(ecx + ew + 0.2, y + figH - eh - 0.3, 6.5, eh, [{'t': f'= {FRAME_KB:.0f} KB / {FRAME_KB / crD:.0f} KB ≈ **{crD:.1f}×** (DRHE)', 'size': 28}], anchor=MSO_ANCHOR.MIDDLE)
# 2: stage 1
y = row_y(1); w, _ = picture('fig_stage1.png', figX, y, h=figH)
cx = figX + w + 0.4
callout(cx, y, endX - cx, figH, [
    {'t': '**The green area is the goal:** high compression (right) **and** no extra missed targets (bottom).', 'space': 12},
    {'t': '**Lossy** methods (BAQ, RDVLE) shrink the data but **lose targets**. Only **DRHE and LPC** land in the green.', 'space': 12},
    {'t': 'The 3.77 % baseline comes from 16-bit rounding, not compression.', 'size': 20, 'italic': True}], fill=GREEN)
# 3: DRHE vs LPC
y = row_y(2); x = figX
for f in ('fig_residual.png', 'fig_cr_bars.png', 'fig_cr_frames.png'):
    w, _ = picture(f, x, y, h=figH); x += w + 0.35
# 4: hardware
y = row_y(3); w, _ = picture('fig_resources.png', figX, y, h=figH)
cx = figX + w + 0.4
callout(cx, y, endX - cx, figH, [
    {'t': f'**Encoder + decoder use under a quarter of the chip:** DRHE {lutD:.0f} %, LPC {lutL:.0f} % of the logic (LUTs).', 'space': 12},
    {'t': 'The same C++ that was simulated runs on the FPGA, so the hardware can be checked **bit for bit** against the simulation.'}])
# 5: timing
y = row_y(4); w, _ = picture('fig_timing.png', figX, y, h=figH)
cx = figX + w + 0.4
callout(cx, y, endX - cx, figH, [
    {'t': '**50 / 50 frames bit-exact** on the FPGA', 'size': 30, 'space': 12},
    {'t': f'**DRHE: {encD_ms:.2f} ms per frame.** Output streams out as the data comes in.', 'space': 10},
    {'t': f'**LPC: {encL_ms:.2f} ms per frame.** It must store the whole frame before it can output anything.', 'space': 10},
    {'t': 'Decode timing: board run pending.', 'size': 20, 'italic': True}])

# ================= ROW C: why FPGA / conclusion =================
yC = yB + hB + 0.5
hC = 46.15 - yC
wC1 = 12.6
box(X0, yC, wC1, hC, fill=BLUE)
heading(X0 + 0.35, yC + 0.25, wC1 - 0.7, 'Why an FPGA, not just simulation?')
text(X0 + 0.35, yC + 1.05, wC1 - 0.7, hC - 1.2, [
    'Compression has to run **at the sensor, in real time**, on small low-power hardware.',
    'Simulation cannot show **speed, latency or chip size**.',
    'Hardware proves the design reproduces the simulation **bit for bit**.'],
    bullets=True)

xC2 = X0 + wC1 + GAP
wC2 = X1 - xC2
box(xC2, yC, wC2, hC, fill=BLUE)
heading(xC2 + 0.35, yC + 0.25, wC2 - 0.7, 'Conclusion')
text(xC2 + 0.35, yC + 1.05, wC2 - 0.7, hC - 1.7, [
    '**Both DRHE and LPC are lossless on real radar data, on real hardware.**',
    f'**LPC compresses most: {crL:.2f}×** (DRHE {crD:.2f}×). Re-deriving the **Huffman dictionary** for this data helped **more than the predictor** did.',
    f'**DRHE streams** with no frame buffer; **LPC must buffer a whole frame** ({encL_ms:.2f} ms). Both meet the 15 ms limit here, but **DRHE scales better to bigger frames**.',
    'Next: a streaming LPC, all 16 receivers, fixed-point DRHE.'],
    bullets=True, size=24, space=6)
text(xC2 + 0.35, yC + hC - 0.5, wC2 - 0.7, 0.4, [
    {'t': '[1] A. Kramer et al., ColoRadar: the direct 3D millimeter wave radar dataset, IJRR, 2022.', 'size': 14}])

prs.save(HERE + '/Thesis_Poster.pptx')
print('saved', yC, hC)
