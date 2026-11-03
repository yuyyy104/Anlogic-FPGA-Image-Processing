"""Deterministic masks and independent full-image geometry for detector regression."""
from pathlib import Path
import hashlib,json
import numpy as np

root=Path(__file__).resolve().parents[2];dest=root/'src/sim/fixtures/shape_field';dest.mkdir(parents=True,exist_ok=True)
W,H=512,256;y,x=np.indices((H,W));base=(x>=10)&(x<412)&(y>=10)&(y<210)
cases=[]
def add(name,m,cls,reason=0):cases.append((name,m.copy(),cls,reason))
add('rect',base,2)
circle=(x-256)**2+(y-128)**2<=10000
add('circle',circle,1)
trapezoid=(y>=28)&(y<228)&(x>=28+(y-28)//10)&(x<228-(y-28)//12)
for label,m,cls in [('circle',circle,1),('rect',base,2),('trapezoid',trapezoid,2)]:
    n=m.copy();rng=np.random.default_rng(7)
    for _ in range(40):
        yy,xx=rng.integers(50,205),rng.integers(60,200);n[yy:yy+6,xx:xx+6]=False
    add(label+'_6px_clusters',n,cls)
add('ring',circle & ((x-256)**2+(y-128)**2>=4000),3,1)
for label,axis in [('vertical_crack',0),('horizontal_crack',1),('diagonal_crack',2)]:
    n=base.copy()
    if axis==0:n[:,200]=False
    elif axis==1:n[128,:]=False
    else:
        for yy in range(10,210):n[yy,100+(yy-10)//3]=False
    add(label,n,3,2 if axis==1 else 1)
for width,height in [(12,1),(13,1),(1,16),(1,17)]:
    n=base.copy();n[80:80+height,80:80+width]=False
    add(f'gap_{width}x{height}',n,2 if width<=12 and height<=16 else 3,0 if width<=12 and height<=16 else 1)
for count in [16,17]:
    n=base.copy()
    for xx in range(20,20+22*count,22):n[80,xx]=False
    add(f'slots_{count}',n,2 if count==16 else 3,0 if count==16 else 6)
for extra in [0,1]:
    n=base.copy()
    for yy in range(10,210):
        for xx in [40,105,170,235,300]:
            xx+=(yy%2)*13;n[yy,xx:xx+10+(extra if yy==80 and xx==40 else 0)]=False
    add('hole_budget_'+str(extra),n,2 if extra==0 else 3,0 if extra==0 else 5)
for yy in [0,H-3]:
    n=np.zeros((H,W),bool);n[max(0,yy-20):min(H,yy+21),100:300]=True;n[yy,190:194]=False
    add('border_'+str(yy),n,2)
triangle=(y>=128)&(y<240)&(np.abs(x-256)<=y-128)
add('triangle_tracking_base',triangle,3,3)
n=triangle.copy();n[15:18,80:83]=True;add('triangle_caption_outlier',n,3,2)
# The final eligible centre is one clock before MASK_CLEANUP's row-end token.
# An open parent continues through that final gap while its left span narrows.
n=np.zeros((H,W),bool);n[10:210,10:511]=True
n[10,504:509]=False;n[11,10:505]=False;n[11,508]=False
add('last_column_open_chain_forward',n,2)
n=np.zeros((H,W),bool);n[10:H,10:511]=True;n[H-3,496:509]=False
add('last_visible_row_wide_gap',n,3,1)
for count in [16,17]:
    n=base.copy();n[80:82,20:20+2*count:2]=False
    add(f'dense_slots_{count}',n,2 if count==16 else 3,0 if count==16 else 6)
metadata=[];words=[]
for i,(name,m,cls,reason) in enumerate(cases):
    p=np.pad(m,1);neigh=p[:-2,1:-1].astype(np.uint8)+p[2:,1:-1]+p[1:-1,:-2]+p[1:-1,2:]
    clean=m|(neigh>=3);a=np.zeros_like(m);a[:-2,1:-2]=clean[:-2,:-3]&clean[:-2,1:-2]&clean[:-2,2:-1]
    ys,xs=np.nonzero(a);v=[cls,len(xs),int(xs.min()),int(xs.max()),int(ys.min()),int(ys.max()),reason]
    fp=dest/f'{i:02d}.mem';fp.write_text('\n'.join(np.where(m.ravel(),'1','0'))+'\n',encoding='ascii')
    words.extend(v);metadata.append({'name':name,'file':fp.name,'expected':v,'sha256':hashlib.sha256(fp.read_bytes()).hexdigest()})
(dest/'expected.mem').write_text('\n'.join(f'{v:08x}' for v in words)+'\n',encoding='ascii')
(dest/'manifest.json').write_text(json.dumps({'width':W,'height':H,'cases':metadata},indent=2),encoding='utf8')
print('FIXTURES',len(cases),W,H)
