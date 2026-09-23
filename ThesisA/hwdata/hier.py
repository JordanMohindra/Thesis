import re,sys,collections
def load(f):
    rows=[]
    hdr=None
    for l in open(f):
        if not l.startswith('|'): continue
        c=l.rstrip('\n').split('|')
        if 'Instance' in c[1] and 'Module' in c[2]:
            hdr=[x.strip() for x in c[1:-1]]; continue
        if hdr is None: continue
        inst=c[1]; depth=(len(inst)-len(inst.lstrip(' ')))//2
        vals=[x.strip() for x in c[1:-1]]
        d=dict(zip(hdr,vals)); d['depth']=depth; d['name']=inst.strip()
        for k in ('Total LUTs','Logic LUTs','LUTRAMs','SRLs','FFs','RAMB36','RAMB18','DSP Blocks','URAM'):
            if k in d:
                try: d[k]=float(d[k]) if '.' in d[k] else int(d[k])
                except: d[k]=0
        rows.append(d)
    return rows
def classify(name):
    n=name
    n=re.sub(r'^grp_','',n); n=re.sub(r'_fu_\d+$','',n); n=re.sub(r'_U\d+$','',n)
    for pat,lab in [(r'frame_buf','frame buffer (BRAM)'),(r'srem|urem|sdiv|udiv','integer divide/modulo'),(r'EMIT_COEF','coefficient emit'),
                    (r'flow_control_loop','loop control'),(r'atan2','atan2 (float CORDIC)'),(r'sin_or_cos','sin/cos (float)'),(r'fsqrt','sqrt (float)'),
                    (r'fmul','fmul'),(r'faddfsub|fadd|fsub','fadd/fsub'),(r'sitofp','int->float'),(r'fptosi','float->int'),
                    (r'generic_round','round'),(r'fcmp','fcmp'),(r'sparsemux','Huffman/S4 lookup mux'),(r'control_s_axi','AXI-Lite control'),
                    (r'_stream_stream_|_s_mag|_s_prev|_s_phase','state BRAM'),(r'regslice','AXIS register slice'),(r'lpc_solve','LPC solver'),
                    (r'mul_|mac_|am_|ama_','fixed mult'),]:
        if re.search(pat,n): return lab
    return n
def children(rows,i):
    d=rows[i]['depth']; out=[]
    for j in range(i+1,len(rows)):
        if rows[j]['depth']<=d: break
        if rows[j]['depth']==d+1: out.append(j)
    return out
if __name__=='__main__':
    rows=load(sys.argv[1]); target=sys.argv[2] if len(sys.argv)>2 else 'Pipeline'
    # print top levels
    for i,r in enumerate(rows):
        if r['depth']<=4: print('  '*r['depth']+f"{r['name'][:60]:60s} LUT={r['Total LUTs']:>6} FF={r['FFs']:>6} B36={r['RAMB36']} B18={r['RAMB18']} DSP={r['DSP Blocks']}")
    for i,r in enumerate(rows):
        if r['depth']>=3 and target in r['name'] and not r['name'].startswith('('):
            agg=collections.OrderedDict()
            for j in children(rows,i):
                k=classify(rows[j]['name']) if not rows[j]['name'].startswith('(') else '(loop body logic: packer, S4, control)'
                a=agg.setdefault(k,[0,0,0,0,0,0]); a[0]+=1; a[1]+=rows[j]['Total LUTs']; a[2]+=rows[j]['FFs']; a[3]+=rows[j]['DSP Blocks']; a[4]+=rows[j]['RAMB36']; a[5]+=rows[j]['RAMB18']
            print('== breakdown of',r['name'])
            for k,a in sorted(agg.items(),key=lambda x:-x[1][1]): print(f"  {a[0]:3d}x {k:45s} LUT={a[1]:>6} FF={a[2]:>6} DSP={a[3]:>4} B36={a[4]} B18={a[5]}")
            break
