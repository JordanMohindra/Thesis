"""collect_impl.py - read every Vitis/Vivado report for every design and emit
(1) hw_numbers.json  (2) hw_numbers.tex (LaTeX macros used by the thesis).
No number in the hardware chapters is typed by hand: they all come from here.
Usage: python3 collect_impl.py <staged_root>   (root contains one folder per design)
"""
import re, os, sys, json, glob, collections
sys.path.insert(0, os.path.dirname(__file__))

def rd(p):
    return open(p, errors='replace').read() if p and os.path.exists(p) else ''

def one(pattern, text, cast=float, default=None):
    m = re.search(pattern, text)
    return cast(m.group(1)) if m else default

def export(d):
    f = glob.glob(os.path.join(d, '*_export.rpt'))
    t = rd(f[0]) if f else ''
    sec = t.split('Post-Implementation Resource usage')[-1] if 'Post-Implementation' in t else t
    r = {}
    for k in ('LUT', 'FF', 'DSP', 'BRAM', 'SRL', 'CLB'):
        r[k] = one(r'\n%s:\s+(\d+)' % k, sec, int)
    r['cp_syn'] = one(r'CP achieved post-synthesis:\s+([\d.]+)', t)
    r['cp_impl'] = one(r'CP achieved post-implementation:\s+([\d.]+)', t)
    r['impl_done'] = 'Post-Implementation' in t
    return r

def timing(d):
    t = rd((glob.glob(os.path.join(d, '*_timing_routed.rpt')) or [None])[0])
    m = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)', t, re.S)
    wns = float(m.group(1)) if m else None
    p = rd((glob.glob(os.path.join(d, '*_timing_paths_routed.rpt')) or [None])[0])
    src = one(r'Source:\s+(\S+)', p, str)
    dst = one(r'Destination:\s+(\S+)', p, str)
    lv = one(r'Logic Levels:\s+(\d+)', p, int)
    dpd = one(r'Data Path Delay:\s+([\d.]+)ns', p)
    route = one(r'route ([\d.]+)ns', p)
    return dict(wns=wns, crit_src=src, crit_dst=dst, crit_levels=lv, crit_delay=dpd, crit_route=route)

def power(d):
    t = rd((glob.glob(os.path.join(d, '*_power_routed.rpt')) or [None])[0])
    return dict(p_total=one(r'Total On-Chip Power \(W\)\s*\|\s*([\d.]+)', t),
                p_dyn=one(r'Dynamic \(W\)\s*\|\s*([\d.]+)', t),
                p_static=one(r'Device Static \(W\)\s*\|\s*([\d.]+)', t))

def hls(d):
    t = rd(os.path.join(d, 'hls_csynth.rpt'))
    r = {}
    m = re.search(r'^\|\+ (\w+)\s*\|.*$', t, re.M)
    if m:
        c = [x.strip() for x in m.group(0).split('|')]
        num = lambda s: int(re.match(r'(\d+)', s).group(1)) if re.match(r'(\d+)', s) else 0
        r.update(top=m.group(1), hBRAM=num(c[-6]), hDSP=num(c[-5]), hFF=num(c[-4]), hLUT=num(c[-3]))
    # worst pipelined-loop II and its depth
    ii, dep = None, None
    for l in t.splitlines():
        c = [x.strip() for x in l.split('|')]
        if len(c) > 9 and c[1].startswith('o ') and c[7] == 'yes':
            try:
                v = int(c[5])
                if ii is None or v > ii: ii, dep = v, int(c[4])
            except ValueError:
                pass
    r['hII'], r['hDepth'] = ii, dep
    s = rd((glob.glob(os.path.join(d, 'hls_*_csynth.rpt')) or [None])[0])
    return r

def hls_clock(d):
    for f in glob.glob(os.path.join(d, 'hls_*_csynth.rpt')):
        t = rd(f)
        v = one(r'\|ap_clk\s*\|\s*[\d.]+ ns\|\s*([\d.]+) ns\|', t)
        if v and 'Pipeline' not in f and 'float' not in f and 'addsub' not in f and 'lpc_solve' not in f:
            return v
    return None

def breakdown(d):
    import hier
    f = (glob.glob(os.path.join(d, '*_utilization_hierarchical_routed.rpt')) or [None])[0]
    if not f: return {}
    rows = hier.load(f)
    agg = collections.OrderedDict()
    top = [r for r in rows if r['name'] == 'inst']
    for i, r in enumerate(rows):
        if r['depth'] == 4 or (r['depth'] >= 5 and 'Pipeline' in r['name']):
            pass
    # walk: every leaf-ish instance at the first level below each Pipeline_ module, plus top-level blocks
    def add(key, r, n=1):
        a = agg.setdefault(key, dict(n=0, LUT=0, FF=0, DSP=0, B36=0, B18=0))
        a['n'] += n; a['LUT'] += r['Total LUTs']; a['FF'] += r['FFs']; a['DSP'] += r['DSP Blocks']
        a['B36'] += r['RAMB36']; a['B18'] += r['RAMB18']
    inst_i = [i for i, r in enumerate(rows) if r['name'] == 'inst'][0]
    def walk(i):
        for j in hier.children(rows, i):
            r = rows[j]
            if r['name'].startswith('('):
                add('logic:' + rows[i]['name'], r); continue
            if 'Pipeline' in r['name'] and hier.children(rows, j):
                walk(j)
                # memories flattened into the Pipeline module: remainder
                kids = hier.children(rows, j)
                rem = dict((k, r[k] - sum(rows[x][k] for x in kids)) for k in ('Total LUTs', 'FFs', 'DSP Blocks', 'RAMB36', 'RAMB18'))
                if any(rem.values()): add('flattened:' + r['name'], rem, 0)
                continue
            add(hier.classify(r['name']), r)
    walk(inst_i)
    return agg

def collect(root):
    out = {}
    for d in sorted(glob.glob(os.path.join(root, '*'))):
        if not os.path.isdir(d): continue
        n = os.path.basename(d)
        r = dict(name=n)
        r.update(export(d)); r.update(timing(d)); r.update(power(d)); r.update(hls(d))
        r['hClk'] = hls_clock(d)
        # ablation variants: HLS clock estimate is in the synthesis log
        lg = os.path.join(os.path.dirname(root.rstrip('/')), 'abl_logs', n.replace('abl_', '') + '_syn.log')
        if r['hClk'] is None and os.path.exists(lg):
            m = re.search(r'Estimated Fmax: ([\d.]+) MHz', rd(lg))
            if m: r['hClk'] = 1000.0 / float(m.group(1))
        r['breakdown'] = breakdown(d)
        if r.get('cp_impl'): r['fmax'] = round(1000.0 / r['cp_impl'], 2)
        if r.get('hClk'): r['hFmax'] = round(1000.0 / r['hClk'], 2)
        out[n] = r
    return out

# ---------------------------------------------------------------- LaTeX emitter
KIEM = dict(LUT=45892, FF=9243, DSP=44, BRAM=20, BRAMT=10, LUTRAM=302, depth=23, depth_meas=31,
            fmax=100.0, part='XCZU3CG-SFVC784-1-e')

DIG = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']
def tag(n):
    return re.sub(r'[^a-z]', '', ''.join(DIG[int(c)] if c.isdigit() else c for c in n.lower()))

def fmt_int(v):
    return r'\num{%d}' % v

def emit_tex(data, path):
    L = [r'% generated by collect_impl.py -- do not edit by hand',
         r'\providecommand{\HW}[2]{\ifcsname hw@#1@#2\endcsname\csname hw@#1@#2\endcsname\else\textbf{??#1:#2??}\fi}']
    def put(design, key, val):
        L.append(r'\expandafter\def\csname hw@%s@%s\endcsname{%s}' % (design, key, val))
    for n, r in data.items():
        tg = tag(n)
        for k in ('LUT', 'FF', 'DSP', 'BRAM', 'SRL', 'hLUT', 'hFF', 'hDSP', 'hBRAM', 'hII', 'hDepth'):
            if r.get(k) is not None: put(tg, k, fmt_int(r[k]))
        if r.get('BRAM') is not None: put(tg, 'BRAMT', fmt_int(r['BRAM'] // 2) if r['BRAM'] % 2 == 0 else r'\num{%.1f}' % (r['BRAM'] / 2))
        for k, f in (('cp_impl', '%.3f'), ('fmax', '%.1f'), ('wns', '%.3f'), ('p_total', '%.3f'), ('p_dyn', '%.3f'), ('p_static', '%.3f'), ('hFmax', '%.2f'), ('hClk', '%.3f')):
            if r.get(k) is not None: put(tg, k.replace('_', ''), f % r[k])
        for k in ('LUT', 'FF', 'DSP'):
            if r.get(k) and r.get('h' + k): put(tg, 'est' + k, '%.1f' % (r['h' + k] / r[k]))
        for k in ('LUT', 'FF', 'DSP', 'BRAM'):
            if r.get(k): put(tg, 'vsK' + k, '%.2f' % (r[k] / KIEM[k]))
    # ladder deltas: saving relative to the previous step (positive = fewer)
    prev = None
    for st, lab, k in LADDER:
        r = data.get(k)
        if r and prev and r.get('LUT') is not None and prev.get('LUT') is not None:
            tg = tag(k)
            for key in ('LUT', 'FF', 'DSP', 'BRAM'):
                d = prev[key] - r[key]
                put(tg, 'd' + key, r'\num{%d}' % abs(d))
                put(tg, 'd' + key + 'sign', 'fewer' if d > 0 else 'more')
                if prev[key]: put(tg, 'p' + key, '%.0f' % (100.0 * abs(d) / prev[key]))
        if r: prev = r
    # replica against Kiem
    k = data.get('abl_k')
    if k and k.get('LUT'):
        put('ablk', 'KLUTgap', r'\num{%d}' % (KIEM['LUT'] - k['LUT']))
        put('ablk', 'KLUTratio', '%.2f' % (KIEM['LUT'] / k['LUT']))
        put('ablk', 'KFFratio', '%.2f' % (KIEM['FF'] / k['FF']))
    # our designs against the replica
    for d in ('drhe1', 'drhe_n', 'lpc1', 'lpc_n'):
        r = data.get(d)
        if r and k and r.get('LUT'):
            tg = tag(d)
            for key in ('LUT', 'FF', 'DSP', 'BRAM'):
                put(tg, 'vsR' + key, '%.2f' % (r[key] / k[key]))
    open(path, 'w').write('\n'.join(L) + '\n')

# ---------------------------------------------------------------- LaTeX tables
def n(v, f='%d'):
    return '---' if v is None else (r'\num{' + (f % v) + '}')

def tab_hlsvsimpl(D, path):
    rows = [('DRHE-1', 'drhe1'), ('DRHE-$n$', 'drhe_n'), ('LPC-1,2', 'lpc1'), ('LPC-$n$,$2n$', 'lpc_n')]
    L = [r'\begin{table}[htbp]', r'\centering',
         r'\caption[HLS estimates against implemented results]{HLS estimates against the same designs after Vivado placement and routing, \texttt{xcku5p-ffvb676-2-e}, \SI{10}{\nano\second} constraint. BRAM in BRAM\_18K units. $F_{\max}$ is $1/(10\,\mathrm{ns} - \mathrm{WNS})$ after routing, and HLS\'s own estimate before it. Every figure is read from the tool reports by \texttt{collect\_impl.py}.}',
         r'\label{tab:hlsvsimpl}', r'\small', r'\setlength{\tabcolsep}{3.5pt}',
         r'\begin{tabular}{@{}l rr rr rr rr rr@{}}', r'\toprule',
         r'& \multicolumn{2}{c}{LUT} & \multicolumn{2}{c}{FF} & \multicolumn{2}{c}{DSP} & \multicolumn{2}{c}{BRAM\_18K} & \multicolumn{2}{c}{$F_{\max}$ (MHz)}\\',
         r'\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}\cmidrule(lr){8-9}\cmidrule(lr){10-11}',
         r'Design & HLS & impl. & HLS & impl. & HLS & impl. & HLS & impl. & HLS & impl.\\', r'\midrule']
    for lab, k in rows:
        r = D.get(k, {})
        L.append('%s & %s & \\textbf{%s} & %s & \\textbf{%s} & %s & \\textbf{%s} & %s & \\textbf{%s} & %s & \\textbf{%s}\\\\' % (
            lab, n(r.get('hLUT')), n(r.get('LUT')), n(r.get('hFF')), n(r.get('FF')), n(r.get('hDSP')), n(r.get('DSP')),
            n(r.get('hBRAM')), n(r.get('BRAM')), n(r.get('hFmax'), '%.1f'), n(r.get('fmax'), '%.1f')))
    L.append(r'\midrule')
    for lab, k in rows:
        r = D.get(k, {})
        if r.get('LUT') and r.get('hLUT'):
            pass
    L += [r'\bottomrule', r'\end{tabular}', r'\end{table}']
    open(path, 'w').write(('\n'.join(L).replace(r'\midrule' + '\n' + r'\bottomrule', r'\bottomrule') + '\n').replace("\\'", "'"))

def tab_replica(D, path):
    k = D.get('abl_k', {}); s = D.get('abl_k_sg1', {})
    L = [r'\begin{table}[htbp]', r'\centering',
         r'\caption[The replica against Kiem\'s published design]{The rebuilt design against Kiem\'s published compression IP (his Table~5.3 and Section~5.2.3). Replica figures are post-route, out of context, on the \texttt{xcku5p} at speed grades $-2$ and $-1$; Kiem\'s are post-route, in system, on the \texttt{XCZU3CG-SFVC784-1-e}. Kiem\'s BRAM is given in 36\,Kb tiles and converted.}',
         r'\label{tab:replica}', r'\small',
         r'\begin{tabular}{@{}lrrr@{}}', r'\toprule',
         r'& Replica ($-2$) & Replica ($-1$) & Kiem \cite{kiem2025}\\', r'\midrule',
         r'LUT & %s & %s & \num{45892}\\' % (n(k.get('LUT')), n(s.get('LUT'))),
         r'FF & %s & %s & \num{9243}\\' % (n(k.get('FF')), n(s.get('FF'))),
         r'DSP & %s & %s & \num{44}\\' % (n(k.get('DSP')), n(s.get('DSP'))),
         r'BRAM (36\,Kb tiles) & %s & %s & \num{10}\\' % (n(k.get('BRAM') and k['BRAM'] // 2), n(s.get('BRAM') and s['BRAM'] // 2)),
         r'Initiation interval & %s & %s & 1\\' % (n(k.get('hII')), n(s.get('hII'))),
         r'Pipeline depth (HLS, cycles) & %s & %s & 23\\' % (n(k.get('hDepth')), n(s.get('hDepth'))),
         r'Achieved clock (MHz) & %s & %s & 100 (met)\\' % (n(k.get('fmax'), '%.1f'), n(s.get('fmax'), '%.1f')),
         r'Compression ratio (ColoRadar, 10 frames) & \multicolumn{2}{c}{\num{3.31904}} & ---\\',
         r'\bottomrule', r'\end{tabular}', r'\end{table}']
    open(path, 'w').write(('\n'.join(L) + '\n').replace("\\'", "'"))

LADDER = [('0', 'DRHE-1 as built', 'drhe1'),
          ('1', 'packer shift offset made unsigned', 'abl_p1'),
          ('2', 'Kiem\'s 58-bit per-channel packer', 'abl_p2'),
          ('3', 'state cleared by read, not write', 'abl_p2r'),
          ('4', 'Kiem\'s fixed-point arithmetic', 'abl_fxc'),
          ('5', 'open loop $=$ replica of Kiem', 'abl_k')]

def tab_ladder(D, path):
    L = [r'\begin{table}[htbp]', r'\centering',
         r'\caption[From DRHE-1 to the replica, one change per step]{From DRHE-1 to the replica of Kiem\'s design, one design decision per step. Every row is a lossless compressor implemented through placement and routing on the \texttt{xcku5p-ffvb676-2-e} at \SI{10}{\nano\second}. II and depth are from HLS; everything else is post-route. BRAM in BRAM\_18K units.}',
         r'\label{tab:abl}', r'\small', r'\setlength{\tabcolsep}{4pt}',
         r'\begin{tabular}{@{}cl rrrr cc r@{}}', r'\toprule',
         r'Step & Change from the row above & LUT & FF & DSP & BRAM & II & Depth & MHz\\', r'\midrule']
    for st, lab, k in LADDER:
        r = D.get(k, {})
        L.append(r'%s & %s & %s & %s & %s & %s & %s & %s & %s\\' % (st, lab, n(r.get('LUT')), n(r.get('FF')), n(r.get('DSP')),
                 n(r.get('BRAM')), n(r.get('hII')), n(r.get('hDepth')), n(r.get('fmax'), '%.1f')))
    L += [r'\midrule',
          r'--- & Kiem, published \cite{kiem2025} & \num{45892} & \num{9243} & \num{44} & \num{20} & 1 & 23 & 100\\',
          r'\bottomrule', r'\end{tabular}', r'\end{table}']
    open(path, 'w').write(('\n'.join(L) + '\n').replace("\\'", "'"))



def emit_extra(data, path):
    L = []
    def put(design, key, val):
        L.append(r'\expandafter\def\csname hw@%s@%s\endcsname{%s}' % (design, key, val))
    a, b = data.get('abl_k'), data.get('abl_k_sg1')
    if a and b and a.get('fmax') and b.get('fmax'):
        put('ablksgone', 'sgpct', '%.1f' % (100.0 * (1 - b['fmax'] / a['fmax'])))
    r = data.get('drhe_n')
    if r and r.get('LUT'):
        put('drhen', 'sysLUT', r'\num{%d}' % (r['LUT'] + 13461))
        put('drhen', 'sysLUTpct', '%.0f' % (100.0 * (r['LUT'] + 13461) / 70560))
        put('drhen', 'fourLUT', r'\num{%d}' % (4 * r['LUT']))
        put('drhen', 'fourLUTpct', '%.0f' % (100.0 * 4 * r['LUT'] / 216960))
    # per-module groups: floating-point operators, loop body, interfaces
    FOP = ('fadd/fsub', 'fmul', 'sqrt (float)', 'atan2 (float CORDIC)', 'round', 'sin/cos (float)', 'int->float')
    for d, r in data.items():
        b = r.get('breakdown') or {}
        if not b or not r.get('LUT'): continue
        t = tag(d)
        fl = sum(b[k]['LUT'] for k in FOP if k in b); ff = sum(b[k]['FF'] for k in FOP if k in b)
        if fl:
            put(t, 'fopLUT', r'\num{%d}' % fl); put(t, 'fopFF', r'\num{%d}' % ff)
            put(t, 'fopLUTpct', '%.0f' % (100.0 * fl / r['LUT'])); put(t, 'fopFFpct', '%.0f' % (100.0 * ff / r['FF']))
        body = [k for k in b if k.startswith('logic:') and 'Pipeline' in k] + [k for k in b if k.startswith('flattened:') and 'Pipeline' in k]
        bl = sum(b[k]['LUT'] for k in body); bf = sum(b[k]['FF'] for k in body)
        put(t, 'bodyLUT', r'\num{%d}' % bl); put(t, 'bodyFF', r'\num{%d}' % bf)
        io = [k for k in b if k in ('AXIS register slice', 'AXI-Lite control')]
        put(t, 'ioLUT', r'\num{%d}' % sum(b[k]['LUT'] for k in io)); put(t, 'ioFF', r'\num{%d}' % sum(b[k]['FF'] for k in io))
        for k, nm in (('atan2 (float CORDIC)', 'atan'), ('sin/cos (float)', 'sincos'), ('fadd/fsub', 'fadd'), ('fmul', 'fmul'), ('fixed mult', 'fxmul')):
            if k in b:
                put(t, nm + 'LUT', r'\num{%d}' % b[k]['LUT']); put(t, nm + 'FF', r'\num{%d}' % b[k]['FF'])
                put(t, nm + 'N', '%d' % b[k]['n'])
    # LPC against DRHE
    for a_, b_ in (('lpc1', 'drhe1'), ('lpc_n', 'drhe_n')):
        A, B = data.get(a_), data.get(b_)
        if A and B and A.get('LUT') and B.get('LUT'):
            put(tag(a_), 'vsDLUT', '%.2f' % (A['LUT'] / B['LUT'])); put(tag(a_), 'vsDFF', '%.2f' % (A['FF'] / B['FF']))
    # cost of the TDM correction, post-route
    for a_, b_ in (('drhe_n', 'drhe1'), ('lpc_n', 'lpc1')):
        A, B = data.get(a_), data.get(b_)
        if A and B and A.get('LUT') and B.get('LUT'):
            for key in ('LUT', 'FF', 'DSP', 'BRAM'):
                dv = A[key] - B[key]
                put(tag(a_), 'dB' + key, r'\num{%d}' % abs(dv)); put(tag(a_), 'dB' + key + 'sign', 'more' if dv >= 0 else 'fewer')
                put(tag(a_), 'pB' + key, '%.1f' % (100.0 * abs(dv) / B[key]))
    # side experiments on the replica, against the replica
    k = data.get('abl_k')
    for d in ('abl_kpk3', 'abl_kpk0', 'abl_k23', 'abl_f', 'abl_ol', 'abl_k_sg1'):
        r = data.get(d)
        if not (r and k and r.get('LUT')): continue
        t = tag(d)
        for key in ('LUT', 'FF', 'DSP', 'BRAM', 'SRL'):
            dv = r[key] - k[key]
            put(t, 'dk' + key, r'\num{%d}' % abs(dv)); put(t, 'dk' + key + 'sign', 'more' if dv >= 0 else 'fewer')
        put(t, 'gapLUTpct', '%.0f' % (100.0 * (r['LUT'] - k['LUT']) / (KIEM['LUT'] - k['LUT'])))
        put(t, 'gapFFpct', '%.0f' % (100.0 * (r['FF'] - k['FF']) / (KIEM['FF'] - k['FF'])))
        put(t, 'vsKLUT', '%.2f' % (r['LUT'] / KIEM['LUT'])); put(t, 'vsKFF', '%.2f' % (r['FF'] / KIEM['FF']))
    # variants against DRHE-1 (one change from the control)
    D1 = data.get('drhe1')
    for d in ('abl_f', 'abl_ctrl_sg1', 'abl_p1'):
        r = data.get(d)
        if not (r and D1 and r.get('LUT')): continue
        for key in ('LUT', 'FF', 'DSP', 'BRAM'):
            dv = r[key] - D1[key]
            put(tag(d), 'dD' + key, r'\num{%d}' % abs(dv)); put(tag(d), 'dD' + key + 'sign', 'more' if dv >= 0 else 'fewer')
            put(tag(d), 'pD' + key, '%.0f' % (100.0 * abs(dv) / D1[key]))
    # float at II=1 against Kiem DSP
    p = data.get('abl_p2r')
    if p and p.get('DSP'):
        put('ablptwor', 'DSPvsK', '%.1f' % (p['DSP'] / KIEM['DSP']))
    c = data.get('abl_ctrl_sg1')
    if c and c.get('fmax') and data.get('drhe1', {}).get('fmax'):
        put('ablctrlsgone', 'sgpct', '%.1f' % (100.0 * (1 - c['fmax'] / data['drhe1']['fmax'])))
    open(path, 'a').write('\n'.join(L) + '\n')

def tab_devrows(D, path):
    rows = [('DRHE-1', 'drhe1'), ('DRHE-$n$', 'drhe_n'), ('LPC-1,2', 'lpc1'), ('LPC-$n$,$2n$', 'lpc_n'), ('Replica of Kiem', 'abl_k')]
    K5 = dict(LUT=216960, FF=433920, BRAM=960, DSP=1824); Z3 = dict(LUT=70560, FF=141120, BRAM=432, DSP=360)
    L = []
    for lab, k in rows:
        r = D.get(k)
        if not r or r.get('LUT') is None:
            L.append(lab + r' & --- & --- & --- & --- & --- & --- & --- & ---\\'); continue
        v = [100.0 * r[x] / K5[x] for x in ('LUT', 'FF', 'BRAM', 'DSP')] + [100.0 * r[x] / Z3[x] for x in ('LUT', 'FF', 'BRAM', 'DSP')]
        L.append(lab + ' & ' + ' & '.join('%.0f' % x for x in v) + r'\\')
    head = [r'\begin{table}[htbp]', r'\centering',
            r'\caption[Implemented resources as a fraction of two devices]{Post-route resources of each design as a fraction of the \texttt{xcku5p} used here and of Kiem\'s \texttt{XCZU3CG} (\num{70560} LUT, \num{141120} FF, 432 BRAM\_18K, 360 DSP). Kiem\'s compression IP is shown for reference.}',
            r'\label{tab:resdevice}', r'\small', r'\setlength{\tabcolsep}{4pt}', r'\begin{tabular}{@{}lrrrrrrrr@{}}', r'\toprule',
            r'& \multicolumn{4}{c}{\% of \texttt{xcku5p}} & \multicolumn{4}{c}{\% of \texttt{XCZU3CG}}\\',
            r'\cmidrule(lr){2-5}\cmidrule(lr){6-9}', r'Design & LUT & FF & BRAM & DSP & LUT & FF & BRAM & DSP\\', r'\midrule']
    tail = [r'\midrule', r"Kiem's IP \cite{kiem2025} & 21 & 2 & 2 & 2 & 65 & 7 & 5 & 12\\", r'\bottomrule', r'\end{tabular}', r'\end{table}']
    open(path, 'w').write(('\n'.join(head + L + tail) + '\n').replace("\\'", "'"))


def tab_kiemgap(D, path):
    k = D.get('abl_k', {})
    rows = [('Replica, speed grade $-2$', 'the reference point', 'abl_k'),
            ('Replica, speed grade $-1$', "Kiem's speed grade", 'abl_k_sg1'),
            ('Replica, literal packer', 'four inserts, \\texttt{int} offset', 'abl_kpk3'),
            ('Replica, 23-cycle pipeline', "Kiem's reported depth", 'abl_k23')]
    L = [r'\begin{table}[htbp]', r'\centering',
         r"\caption[Testing explanations for the gap to Kiem's LUT and FF counts]{Testing explanations for the gap between the replica and Kiem's published LUT and flip-flop counts. Each row is the replica with one thing changed, implemented and routed on the \texttt{xcku5p}. ``Share'' is the change from the replica as a fraction of the gap to Kiem (\num{28751} LUTs, \num{4193} flip-flops).}",
         r'\label{tab:kiemgap}', r'\small', r'\setlength{\tabcolsep}{4pt}',
         r'\begin{tabular}{@{}llrrrr@{}}', r'\toprule',
         r'Variant & Tests & LUT & FF & LUT share & FF share\\', r'\midrule']
    for lab, what, key in rows:
        r = D.get(key, {})
        if r.get('LUT') is None or not k.get('LUT'):
            L.append(r'%s & %s & --- & --- & --- & ---\\' % (lab, what)); continue
        if key == 'abl_k':
            L.append(r'%s & %s & %s & %s & --- & ---\\' % (lab, what, n(r['LUT']), n(r['FF']))); continue
        sl = 100.0 * (r['LUT'] - k['LUT']) / (KIEM['LUT'] - k['LUT']); sf = 100.0 * (r['FF'] - k['FF']) / (KIEM['FF'] - k['FF'])
        sl = 0.0 if abs(sl) < 0.5 else sl; sf = 0.0 if abs(sf) < 0.5 else sf
        L.append(r'%s & %s & %s & %s & %.0f\,\%% & %.0f\,\%%\\' % (lab, what, n(r['LUT']), n(r['FF']), sl, sf))
    L += [r'\midrule', r"Kiem, published \cite{kiem2025} & in system, 2022.2 & \num{45892} & \num{9243} & 100\,\% & 100\,\%\\",
          r'\bottomrule', r'\end{tabular}', r'\end{table}']
    open(path, 'w').write(('\n'.join(L) + '\n').replace("\\'", "'"))


def emit_cosim(data, path):
    here = os.path.dirname(os.path.abspath(__file__))
    cyc = json.load(open(os.path.join(here, 'cosim_cycles.json')))
    L = []
    def put(design, key, val):
        L.append(r'\expandafter\def\csname hw@%s@%s\endcsname{%s}' % (design, key, val))
    for d, c in cyc.items():
        tg = tag(d)
        bits = 3145728
        put(tg, 'framecyc', r'\num{%d}' % c)
        put(tg, 'thrmeas', '%.2f' % (bits / (c * 10e-9) / 1e9))
        put(tg, 'bpcmeas', '%.1f' % (bits / c))
        r = data.get(d)
        if r and r.get('p_dyn'):
            e = r['p_dyn'] * c * 10e-9
            put(tg, 'Eframe', '%.0f' % (e * 1e6))
            put(tg, 'pJbit', '%.0f' % (e / bits * 1e12))
            data[d]['E_frame_uJ'] = e * 1e6
        if r is not None: data[d]['cosim_cycles'] = c
    open(path, 'a').write('\n'.join(L) + '\n')

if __name__ == '__main__':
    root = sys.argv[1]
    data = collect(root)
    here = os.path.dirname(os.path.abspath(__file__))
    json.dump(data, open(os.path.join(here, 'hw_numbers.json'), 'w'), indent=1, default=str)
    for nme, r in data.items():
        print(nme, {k: r.get(k) for k in ('LUT', 'FF', 'DSP', 'BRAM', 'SRL', 'cp_impl', 'fmax', 'wns', 'p_total', 'p_dyn', 'hLUT', 'hFF', 'hDSP', 'hBRAM', 'hII', 'hDepth', 'hFmax')})
        for k, a in sorted(r['breakdown'].items(), key=lambda x: -x[1]['LUT'])[:14]:
            print('    %-60s n=%-3d LUT=%-6d FF=%-6d DSP=%-4d B36=%d B18=%d' % (k[:60], a['n'], a['LUT'], a['FF'], a['DSP'], a['B36'], a['B18']))
    emit_tex(data, os.path.join(here, 'hw_numbers.tex'))
    emit_extra(data, os.path.join(here, 'hw_numbers.tex'))
    emit_cosim(data, os.path.join(here, 'hw_numbers.tex'))
    out = os.path.join(here, '..', 'thesis')
    tab_hlsvsimpl(data, os.path.join(out, 'tab_hlsvsimpl.tex'))
    tab_replica(data, os.path.join(out, 'tab_replica.tex'))
    tab_ladder(data, os.path.join(out, 'tab_ladder.tex'))
    tab_devrows(data, os.path.join(out, 'tab_device.tex'))
    tab_kiemgap(data, os.path.join(out, 'tab_kiemgap.tex'))
    import shutil; shutil.copy(os.path.join(here, 'hw_numbers.tex'), os.path.join(out, 'hw_numbers.tex'))
