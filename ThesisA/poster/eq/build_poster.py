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

EQS = json.load(open(HERE + '/eq/sizes.json'))

def eq(key, x, y, k=0.82):
    w, h = (v * k for v in EQS['sizes'][key])
    s.shapes.add_picture(HERE + f'/eq/{key}.png', Inches(x), Inches(y), Inches(w), Inches(h))
    return w, h

S1 = rows('poster_stage1.csv')
RED = RGBColor(0xB0, 0x1E, 0x1E)

# ================= ROW A: why compress (left) / background and aim (right) =================
yA, hA = 9.53, 6.0
wA2 = 12.6                                   # why compress (left)
wA1 = W - wA2 - GAP                          # background (right)
xA2 = X0
xBG = X0 + wA2 + GAP

box(xBG, yA, wA1, hA, fill=BLUE)
heading(xBG + 0.35, yA + 0.25, wA1 - 0.7, 'Background and aim')
text(xBG + 0.35, yA + 1.05, wA1 - 0.7, 3.4, [
    'There are many ways to compress radar data, and **no single best one**: each trades **compression** against **accuracy**, **speed** and **hardware cost**.',
    'In a car, lost detail can mean a **missed pedestrian**, so a method has to be judged on whether **targets survive**, not just on how small the data gets.',
    'Results **depend on the data**: a method that does well on simulated noise can behave differently on **real radar recordings**.',
    'And only **real hardware** shows whether a method is **fast and small enough** to run at the sensor.'],
    bullets=True, size=23, space=6)
aim = box(xBG + 0.35, yA + hA - 1.55, wA1 - 0.7, 1.25, fill=YELLOW, radius=0.12)
text(0, 0, 0, 0, [{'t': '**Aim:** compare compression methods side by side on **real radar data**, pick the best **lossless** ones, '
                       'and build the **encoder and decoder on an FPGA**.', 'size': 26}], anchor=MSO_ANCHOR.MIDDLE, shape=aim)
aim.text_frame.margin_left = aim.text_frame.margin_right = Inches(0.3)

box(xA2, yA, wA2, hA, fill=BLUE)
heading(xA2 + 0.35, yA + 0.25, wA2 - 0.7, 'Why compress radar data?')
text(xA2 + 0.35, yA + 1.05, wA2 - 0.7, 2.6, [
    'Cascaded MIMO radars (here **12 transmitters × 16 receivers**) produce **3.1 MB of raw data in every frame**, frame after frame.',
    'The link to the car\'s central computer (SoC) becomes the bottleneck: bandwidth, power and delay.',
    'So: **compress at the sensor, losslessly**. Less data on the link, **identical** data after decoding.'],
    bullets=True, size=22, space=6)
gy, gh = yA + 3.6, 1.6
bw = 2.55
xs = [xA2 + 0.35, xA2 + 0.35 + bw + 1.15, xA2 + 0.35 + 2 * (bw + 1.15)]
labels = [('Radar', f'{FRAME_KB:.0f} KB / frame'), ('FPGA', 'compress'), ('SoC', 'decompress')]
for (t1, t2), xx, fc in zip(labels, xs, [WHITE, YELLOW, WHITE]):
    b = box(xx, gy, bw, gh, fill=fc, line=NAVY, lw=3, radius=0.12)
    text(0, 0, 0, 0, [{'t': t1, 'bold': True, 'size': 28, 'align': PP_ALIGN.CENTER, 'space': 2},
                      {'t': t2, 'size': 22, 'align': PP_ALIGN.CENTER}], anchor=MSO_ANCHOR.MIDDLE, shape=b)
arrow(xs[0] + bw + 0.1, gy + gh / 2 - 0.45, 0.95, 0.9)                 # fat: raw data
arrow(xs[1] + bw + 0.1, gy + gh / 2 - 0.13, 0.95, 0.26)                # thin: compressed
text(xs[1] + bw + 0.575 - 0.85, gy + gh / 2 + 0.2, 1.7, 0.6, [{'t': f'{FRAME_KB / crD:.0f} KB', 'bold': True, 'size': 24, 'align': PP_ALIGN.CENTER}])
text(xs[2] - 0.2, gy + gh + 0.02, bw + 0.4, 0.45, [{'t': 'same data, bit for bit', 'italic': True, 'size': 22, 'align': PP_ALIGN.CENTER}])

# ================= ROW B: method -> results =================
ROWS = [4.0, 6.6, 4.7, 3.8, 4.2]            # height of each step row
RGAP = 0.12
yB = yA + hA + 0.5
hB = 1.2 + sum(ROWS) + RGAP * (len(ROWS) - 1) + 0.3
box(X0, yB, W, hB, fill=None, line=BLUE, lw=10, radius=0.025)
text(X0, yB + 0.2, W, 0.8, [{'t': 'Method → Results', 'bold': True, 'size': 44, 'align': PP_ALIGN.CENTER}])

stepX, stepW = X0 + 0.5, 6.6
arrX, arrW = stepX + stepW + 0.2, 0.8
figX = arrX + arrW + 0.25
endX = X1 - 0.5
y0 = yB + 1.2
RY = [y0 + sum(ROWS[:i]) + RGAP * i for i in range(len(ROWS))]

steps = [
    ('Real radar data', 'ColoRadar recordings [1] from a **TI AWR2243 cascade** (12 TX × 16 RX). Range FFT, then **16-bit** frames.'),
    ('Screen 8 methods', 'MATLAB: **compression ratio** and **missed targets** for every method, on **50 frames**.\n\nThe lossy methods **lose targets**. Only **DRHE and LPC** are lossless **and** compress more than 3×, so they go on to hardware.'),
    ('DRHE vs LPC', 'Where does the compression come from? **Huffman coding**, **prediction**, and a **re-derived dictionary**. **The dictionary helps most.**'),
    ('Build it in hardware', 'C++ in **Vitis HLS** → **Vivado** → AMD **KCU116** FPGA. Encoder and decoder on the chip.'),
    ('Measure on the board', 'Stream 50 frames through the FPGA, **check every frame is bit-exact**, time it and measure chip use.'),
]
for i, ((title, body), y, hR) in enumerate(zip(steps, RY, ROWS)):
    box(stepX, y, stepW, hR, fill=BLUE, radius=0.08)
    circle_num(stepX + 0.3, y + 0.3, 0.95, i + 1)
    text(stepX + 1.4, y + 0.38, stepW - 1.5, 0.8, [{'t': title, 'bold': True, 'size': 30}])
    text(stepX + 0.3, y + 1.35, stepW - 0.5, hR - 1.4, [{'t': part, 'size': 22, 'space': 14} for part in body.split('\n\n')])
    arrow(arrX, y + hR / 2 - 0.4, arrW, 0.8)

def callout(x, y, w, h, paras, fill=PALE, size=24, anchor=MSO_ANCHOR.MIDDLE):
    b = box(x, y, w, h, fill=fill, radius=0.06)
    text(0, 0, 0, 0, paras, anchor=anchor, shape=b, size=size)
    b.text_frame.margin_left = b.text_frame.margin_right = Inches(0.3)
    return b

def make_table(x, y, colw, rowh, data, size=20, head_size=20, fills=None, aligns=None):
    """data[0] is the header row. Cell text may use **bold**. fills[i] = row fill."""
    t = s.shapes.add_table(len(data), len(colw), Inches(x), Inches(y), Inches(sum(colw)), Inches(rowh * len(data))).table
    for j, cw in enumerate(colw):
        t.columns[j].width = Inches(cw)
    for i, row in enumerate(data):
        t.rows[i].height = Inches(rowh)
        for j, txt in enumerate(row):
            c = t.cell(i, j)
            head = i == 0
            c.fill.solid(); c.fill.fore_color.rgb = NAVY if head else (fills[i] if fills and fills[i] else WHITE)
            c.margin_left = c.margin_right = Inches(0.12); c.margin_top = c.margin_bottom = Inches(0.02)
            c.vertical_anchor = MSO_ANCHOR.MIDDLE
            c.text_frame.word_wrap = True
            pp = c.text_frame.paragraphs[0]
            pp.alignment = (aligns[j] if aligns else PP_ALIGN.LEFT)
            for tt, bb in runs_of(txt):
                r = pp.add_run(); r.text = tt
                r.font.name = FONT; r.font.size = Pt(head_size if head else size)
                r.font.bold = head or bb or j == 0
                r.font.color.rgb = WHITE if head else BLACK
    return t

# ---- 1: input ----
y, hR = RY[0], ROWS[0]
w, _ = picture('fig_input.png', figX, y, h=hR)
cx = figX + w + 0.4
C, L_ = PP_ALIGN.CENTER, PP_ALIGN.LEFT
make_table(cx, y, [3.1, 5.7, 1.9], hR / 6, [
    ['Data', 'What it is', 'Size'],
    ['Test set', '**50 frames** of real radar data, each compressed on its own', f'{50 * FRAME_KB / 1000:.1f} MB'],
    ['Input frame', '128 range bins × 192 ramps × 4 RX, 16-bit I/Q', f'**{FRAME_KB:.0f} KB**'],
    ['Compressed, DRHE', 'Huffman-coded prediction errors', f'**{FRAME_KB / crD:.0f} KB**'],
    ['Compressed, LPC', 'The same, plus 2 coefficients per range bin', f'**{FRAME_KB / crL:.0f} KB**'],
    ['Decompressed', '**Identical** to the input, bit for bit', f'**{FRAME_KB:.0f} KB**'],
], fills=[None, None, None, PALE, PALE, GREEN], aligns=[L_, L_, C])
jx = cx + 10.7 + 0.35
jw = endX - jx
box(jx, y, jw, hR, fill=PALE, radius=0.06)
text(jx + 0.2, y + 0.15, jw - 0.4, 0.55, [{'t': 'Each method is judged on:', 'bold': True, 'size': 24}])
ew, eh = (v * 0.8 for v in EQS['sizes']['cr'])
eq('cr', jx + (jw - ew) / 2, y + 0.8, k=0.8)
text(jx + 0.2, y + 0.9 + eh, jw - 0.4, hR - 1.0 - eh, [
    {'t': f'DRHE **{crD:.2f}×**,  LPC **{crL:.2f}×**', 'size': 22, 'align': PP_ALIGN.CENTER, 'space': 8},
    {'t': '**Missed targets:** targets found in the original data but **not** after compression.', 'size': 20}])

# ---- 2: screen all methods: figure | table of methods | what are DRHE and LPC ----
y, hR = RY[1], ROWS[1]
fh = 6.0
w, _ = picture('fig_stage1.png', figX, y + (hR - fh) / 2, h=fh)
tX = figX + w + 0.35
tW = 6.9
methods = [   # (csv key, name, idea, selected)
    ('FP16', 'FP16', '16-bit float, uncompressed', False),
    ('FX16', 'FX16', '16-bit integer, uncompressed', False),
    ('BAQ', 'BAQ', 'Block adaptive quantisation (lossy)', False),
    ('RDVLE', 'RDVLE', 'Vector quantisation (lossy)', False),
    ('RDVLE_UDRE', 'RDVLE UDRE', 'Vector quantisation variant (lossy)', False),
    ('DRHEfp16', 'DRHE fp16', 'DRHE on float data', False),
    ('DRHE', 'DRHE', 'Predict magnitude & phase, Huffman', True),
    ('LPC_Huffman', 'LPC', 'Linear prediction, Huffman', True),
]
tH = 5.15
tbl = s.shapes.add_table(len(methods) + 1, 4, Inches(tX), Inches(y), Inches(tW), Inches(tH)).table
for j, cw in enumerate([1.55, 3.25, 0.95, 1.15]):
    tbl.columns[j].width = Inches(cw)
tbl.rows[0].height = Inches(0.55)
for i in range(1, len(methods) + 1):
    tbl.rows[i].height = Inches((tH - 0.55) / len(methods))

def cell(i, j, t, bold=False, fill=WHITE, color=BLACK, align=PP_ALIGN.LEFT, size=18):
    c = tbl.cell(i, j)
    c.fill.solid(); c.fill.fore_color.rgb = fill
    c.margin_left = c.margin_right = Inches(0.08); c.margin_top = c.margin_bottom = Inches(0.02)
    c.vertical_anchor = MSO_ANCHOR.MIDDLE
    tf = c.text_frame; tf.word_wrap = True
    p = tf.paragraphs[0]; p.alignment = align
    for tt, bb in runs_of(t):
        r = p.add_run(); r.text = tt
        r.font.name = FONT; r.font.size = Pt(size); r.font.bold = bold or bb; r.font.color.rgb = color

for j, hd in enumerate(['Method', 'How it works', 'CR', 'Missed']):
    cell(0, j, hd, bold=True, fill=NAVY, color=WHITE, align=PP_ALIGN.LEFT if j < 2 else PP_ALIGN.CENTER, size=20)
for i, (key, name, idea, sel) in enumerate(methods, start=1):
    cr_, fn = float(S1[key]['CR']), float(S1[key]['FN_pct'])
    fill = GREEN if sel else WHITE
    lossy = fn > 5
    cell(i, 0, name, bold=True, fill=fill)
    cell(i, 1, idea, fill=fill, size=17)
    cell(i, 2, f'{cr_:.2f}', bold=sel, fill=fill, align=PP_ALIGN.CENTER)
    cell(i, 3, f'{fn:.1f} %', bold=sel or lossy, fill=fill, color=RED if lossy else BLACK, align=PP_ALIGN.CENTER)
text(tX - 0.08, y + tH + 0.08, tW + 0.16, hR - tH - 0.08, [
    {'t': '**Green = selected:** high CR **and** no extra missed targets. The 3.8 % comes from 16-bit rounding, not compression.', 'size': 17}])

bX = tX + tW + 0.3
bW = endX - bX
box(bX, y, bW, hR, fill=PALE, radius=0.05)
ix, iw = bX + 0.3, bW - 0.6
text(ix - 0.08, y + 0.15, iw, 0.6, [{'t': 'What are DRHE and LPC?', 'bold': True, 'size': 28}])
text(ix - 0.08, y + 0.8, iw, 1.0, [{'t': 'Both **predict** each sample xₘ from earlier ramps of the **same transmitter** (L = 12 back) and **Huffman-code the error**:', 'size': 20}])
eq('c1', ix + (iw - EQS['sizes']['c1'][0] * 0.85) / 2, y + 1.92, k=0.85)
yy = y + 2.45
text(ix - 0.08, yy, iw, 0.75, [{'t': '**DRHE** predicts **magnitude A** and **phase φ** with **fixed** filters:', 'size': 20}])
yy += 0.78
w0, _ = eq('d0', ix + 0.1, yy, k=0.78)
eq('d1', ix + 0.1 + w0 + 0.45, yy + 0.02, k=0.78)
yy += 0.55
text(ix - 0.08, yy, iw, 0.4, [{'t': 'Past ramps only → **streams**', 'size': 20, 'color': NAVY}])
yy += 0.6
text(ix - 0.08, yy, iw, 0.75, [{'t': '**LPC** takes a **weighted sum** of the previous two ramps:', 'size': 20}])
yy += 0.78
eq('l1', ix + 0.1, yy, k=0.82)
yy += 0.5
text(ix - 0.08, yy, iw, 0.4, [{'t': 'a₁, a₂ **fitted to the whole frame** → waits', 'size': 20, 'color': NAVY}])

# ---- 3: DRHE vs LPC (three figures across the full width) ----
y, hR = RY[2], ROWS[2]
figs3 = ['fig_residual.png', 'fig_cr_bars.png', 'fig_cr_frames.png']
ws = []
for f in figs3:
    im = Image.open(FIG + f); ws.append(hR * im.width / im.height)
g = (endX - figX - sum(ws)) / (len(figs3) - 1)
x = figX
for f, wf in zip(figs3, ws):
    picture(f, x, y, h=hR); x += wf + g

# ---- 4: build it in hardware: photo + design flow ----
y, hR = RY[3], ROWS[3]
pw = 7.2
pb = box(figX, y, pw, hR, fill=PALE, line=NAVY, lw=4, radius=0.06, dash=True)
text(0, 0, 0, 0, [{'t': '[Photo: KCU116 FPGA board and laptop running the test]', 'italic': True, 'size': 22, 'align': PP_ALIGN.CENTER}],
     anchor=MSO_ANCHOR.MIDDLE, shape=pb)
cx = figX + pw + 0.4
cW = endX - cx
box(cx, y, cW, hR, fill=PALE, radius=0.06)
flow = [('MATLAB', 'model'), ('C++', 'Vitis HLS'), ('Vivado', 'bitstream'), ('KCU116', 'FPGA board')]
fw, fgap = 2.6, (cW - 0.6 - 4 * 2.6) / 3
for k, (t1, t2) in enumerate(flow):
    fx = cx + 0.3 + k * (fw + fgap)
    b = box(fx, y + 0.3, fw, 1.35, fill=YELLOW if k == 3 else WHITE, line=NAVY, lw=3, radius=0.12)
    text(0, 0, 0, 0, [{'t': t1, 'bold': True, 'size': 24, 'align': PP_ALIGN.CENTER, 'space': 0},
                      {'t': t2, 'size': 18, 'align': PP_ALIGN.CENTER}], anchor=MSO_ANCHOR.MIDDLE, shape=b)
    if k < 3:
        arrow(fx + fw + 0.12, y + 0.3 + 0.675 - 0.25, fgap - 0.24, 0.5)
text(cx + 0.22, y + 1.85, cW - 0.44, hR - 1.95, [
    {'t': 'The **same C++** that was simulated is built for the chip, so the board\'s output can be checked **bit for bit** against the simulation. Encoder and decoder each run as their own core, fed by DMA from the board\'s memory.', 'size': 22}])

# ---- 5: measure on the board: timing + resources + numbers ----
y, hR = RY[4], ROWS[4]
w1, _ = picture('fig_timing.png', figX, y, h=hR)
w2, _ = picture('fig_resources.png', figX + w1 + 0.3, y, h=hR)
cx = figX + w1 + w2 + 0.7
def ms_txt(cyc):
    return 'pending' if cyc != cyc else f'{cyc / 1e5:.2f} ms'    # NaN -> pending
decD, decL = float(HW['DRHE']['DecCyclesPerFrame']), float(HW['LPC']['DecCyclesPerFrame'])
make_table(cx, y, [3.95, 2.9, 2.9], hR / 7, [
    ['On the FPGA', 'DRHE', 'LPC'],
    ['Frames bit-exact', '**50 / 50**', '**50 / 50**'],
    ['Compression ratio', f'{crD:.2f}×', f'**{crL:.2f}×**'],
    ['Encode time / frame', f'**{encD_ms:.2f} ms**', f'{encL_ms:.2f} ms'],
    ['Output starts', '**as data arrives**', 'after whole frame'],
    ['Chip logic (LUTs)', f'**{lutD:.0f} %**', f'{lutL:.0f} %'],
    ['Decode time / frame', ms_txt(decD), ms_txt(decL)],
], fills=[None, GREEN, None, PALE, None, PALE, None], aligns=[PP_ALIGN.LEFT, PP_ALIGN.CENTER, PP_ALIGN.CENTER])

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
    bullets=True, size=22, space=4)
text(xC2 + 0.35, yC + hC - 0.75, wC2 - 0.7, 0.65, [
    {'t': '[1] A. Kramer et al., ColoRadar: the direct 3D millimeter wave radar dataset, IJRR, 2022.', 'size': 14}])

prs.save(HERE + '/Thesis_Poster.pptx')
print('saved', yC, hC)
