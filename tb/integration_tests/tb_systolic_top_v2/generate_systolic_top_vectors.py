#!/usr/bin/env python3
from __future__ import annotations
import argparse, random
from pathlib import Path
DATA_WIDTH=32; ACC_WIDTH=71; S_MAX=32; MAX_M=256; MAX_K=108; MAX_N=64
MAGIC=0x53595341

def lim(w): return (-(1<<(w-1)), (1<<(w-1))-1)
def enc(v,w):
    lo,hi=lim(w)
    if not lo<=v<=hi: raise OverflowError(f"{v} does not fit signed {w}-bit")
    return v & ((1<<w)-1)
def wr(f,v,w): f.write(f"{enc(v,w):0{(w+3)//4}X}\n")
def choose_s(m,k,n):
    best_s=1; best=None
    for s in range(1,S_MAX+1):
        tm=(m+s-1)//s; tn=(n+s-1)//s
        cost=tm*tn*(k+4)+tn*m+tm*n+m*n
        if best is None or cost<best:
            best=cost; best_s=s
    return best_s,best

def mk(rows,cols,pattern,rng,vmin,vmax,salt):
    if pattern=='random': return [[rng.randint(vmin,vmax) for _ in range(cols)] for _ in range(rows)]
    if pattern=='ones': return [[1 for _ in range(cols)] for _ in range(rows)]
    if pattern=='checker': return [[1 if ((r+c+salt)&1)==0 else -1 for c in range(cols)] for r in range(rows)]
    span=vmax-vmin+1
    return [[vmin+((r*cols+c+salt)%span) for c in range(cols)] for r in range(rows)]
def mm(a,b):
    m=len(a); k=len(a[0]); n=len(b[0]); c=[[0]*n for _ in range(m)]
    for i in range(m):
        for j in range(n):
            x=sum(a[i][kk]*b[kk][j] for kk in range(k)); enc(x,ACC_WIDTH); c[i][j]=x
    return c
def flat(x): return [v for row in x for v in row]
def drain_order(c,m,n,s):
    out=[]
    for mb in range(0,m,s):
        ar=min(s,m-mb)
        for nb in range(0,n,s):
            ac=min(s,n-nb)
            for r in range(ar):
                for col in range(ac): out.append(c[mb+r][nb+col])
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--m',type=int,default=4); ap.add_argument('--k',type=int,default=5); ap.add_argument('--n',type=int,default=3)
    ap.add_argument('--seed',type=lambda x:int(x,0),default=0x1313)
    ap.add_argument('--pattern',choices=['random','ones','checker','ramp'],default='random')
    ap.add_argument('--value-min',type=int,default=-8); ap.add_argument('--value-max',type=int,default=8)
    ap.add_argument('--outdir',type=Path,default=Path('vectors'))
    a=ap.parse_args(); m,k,n=a.m,a.k,a.n
    if not (1<=m<=MAX_M and 1<=k<=MAX_K and 1<=n<=MAX_N): raise SystemExit('dimensions out of range')
    rng=random.Random(a.seed)
    A=mk(m,k,a.pattern,rng,a.value_min,a.value_max,0); B=mk(k,n,a.pattern,rng,a.value_min,a.value_max,17)
    s,cost=choose_s(m,k,n); C=mm(A,B); Af=flat(A); Bf=flat(B); G=drain_order(C,m,n,s)
    a.outdir.mkdir(parents=True,exist_ok=True)
    with (a.outdir/'input.hex').open('w',encoding='ascii') as f:
        for x in [MAGIC,m,k,n,s,len(Af),len(Bf)]: wr(f,x,32)
        for x in Af+Bf: wr(f,x,32)
    with (a.outdir/'golden.hex').open('w',encoding='ascii') as f:
        for x in G: wr(f,x,ACC_WIDTH)
    print(f'[GEN] M={m} K={k} N={n} S_opt={s} cost={cost}')
    print(f'[GEN] {a.outdir/"input.hex"} words={7+len(Af)+len(Bf)}')
    print(f'[GEN] {a.outdir/"golden.hex"} words={len(G)}')
    print('[GEN] golden order: M-tile -> N-tile -> local-row -> local-col')
if __name__=='__main__': main()
