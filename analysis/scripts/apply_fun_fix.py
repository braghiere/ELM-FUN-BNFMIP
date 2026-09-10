#!/usr/bin/env python
"""Apply the two FUN N-cost fixes to a CNFUNMod.F90 in place:
   (B) AM N-cost typo ivt(p).eq.7 -> .eq.17
   (A) non-myc kc_nonmyc/kn_nonmyc swap -> exchange RHS of each live pair
Verifies exactly 1 B-fix and 4 A-swaps; refuses to write otherwise."""
import re,sys,shutil
def fix(path,inplace=True):
    lines=open(path).readlines()
    typo='ivt(p).eq.14 .or. ivt(p).eq.7 .or. ivt(p).eq.18'
    fixB='ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18'
    nB=sum(l.count(typo) for l in lines); lines=[l.replace(typo,fixB) for l in lines]
    kc=re.compile(r'^(\s*)kc_nonmyc\(ivt\(p\)\)(\s*=\s*)(\S+)')
    kn=re.compile(r'^(\s*)kn_nonmyc\(ivt\(p\)\)(\s*=\s*)(\S+)')
    live=lambda l: not l.lstrip().startswith('!')
    nA=0;i=0
    while i<len(lines):
        m=kc.match(lines[i]) if live(lines[i]) else None
        if m:
            j=i+1
            while j<len(lines) and (not lines[j].strip() or not live(lines[j])): j+=1
            mn=kn.match(lines[j]) if (j<len(lines) and live(lines[j])) else None
            if mn:
                a,b=m.group(3),mn.group(3)
                lines[i]=kc.sub(rf'\g<1>kc_nonmyc(ivt(p))\g<2>{b}',lines[i])
                lines[j]=kn.sub(rf'\g<1>kn_nonmyc(ivt(p))\g<2>{a}',lines[j])
                nA+=1;i=j+1;continue
        i+=1
    if (nB,nA)!=(1,4):
        return (nB,nA,False)
    if inplace:
        shutil.copy2(path,path+'.prefix_bak')
        open(path,'w').writelines(lines)
    return (nB,nA,True)
if __name__=='__main__':
    for p in sys.argv[1:]:
        nB,nA,ok=fix(p)
        print(f"  {'OK ' if ok else 'FAIL'} B={nB} A={nA}  {p}")
