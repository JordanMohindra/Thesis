"""Map every scheduled operation in a Vitis HLS verbose.sched.rpt to a pipeline
phase, by the source line it came from. Returns {phase: (first_stage, last_stage)}."""
import re, sys, collections
def phases_abl(line_file, ln, arith):
    f, n = line_file, ln
    if f.endswith('drhe_abl_common.h'):
        if (76 <= n <= 87) or (89 <= n <= 95):
            if n in (83, 84, 93, 94): return 'sin/cos and rescale'
            if n in (80, 91, 92): return 'phase wrap'
            return 'IIR prediction'
        if 102 <= n <= 109:
            if n in (105, 109): return 'atan2'
            return 'magnitude (sqrt)'
    if f.endswith('drhe_abl_compress.cpp'):
        if 60 <= n <= 72: return 'state load'
        if 92 <= n <= 102: return 'residual, clamp, reconstruct'
        if 106 <= n <= 111: return 'state store'
        if 113 <= n <= 170: return 'S4, Huffman, packing'
        if n <= 50: return 'read input'
    fl = f.lower()
    if 'cordic' in fl or 'atan' in fl: return 'atan2'
    if 'sqrt' in fl: return 'magnitude (sqrt)'
    if 'hotbm' in fl or 'sin' in fl or 'cos' in fl: return 'sin/cos and rescale'
    return None
def parse(path):
    span = collections.OrderedDict()
    last_src = None
    for l in open(path, errors='replace'):
        m = re.match(r'ST_(\d+) : Operation \d+ \[\d+/\d+\] \([\d.]+ns\)\s+--->\s+"(.*?)"\s+(\[([^\]]*)\])?', l)
        if not m: continue
        s = int(m.group(1)); body = m.group(2); src = m.group(4) or ''
        mm = re.search(r'([\w./\\:-]+\.(?:cpp|h)):(\d+)', src)
        ph = None
        if mm:
            ph = phases_abl(mm.group(1).replace('\\', '/'), int(mm.group(2)), None)
        c = re.search(r'@(\w+)', body)
        if c and ph is None:
            nm = c.group(1)
            if 'atan2' in nm: ph = 'atan2'
            elif 'sin_or_cos' in nm or 'sinf' in nm or 'cos' in nm: ph = 'sin/cos and rescale'
            elif 'sqrt' in nm: ph = 'magnitude (sqrt)'
        if ph is None: continue
        a = span.setdefault(ph, [s, s]); a[0] = min(a[0], s); a[1] = max(a[1], s)
    return span
if __name__ == '__main__':
    for p in sys.argv[1:]:
        print('==', p.split('/')[-1])
        for k, (a, b) in sorted(parse(p).items(), key=lambda x: x[1][0]): print('  %2d-%2d %s' % (a, b, k))
