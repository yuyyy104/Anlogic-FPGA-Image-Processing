"""Full-image geometry oracle for recall-first single-candidate recognition."""
from pathlib import Path
import numpy as np,json,hashlib
root=Path(__file__).resolve().parents[2];dest=root/'src/sim/fixtures/shape_recall';dest.mkdir(parents=True,exist_ok=True)
W,H=512,256;y,x=np.indices((H,W));cases=[]
BG=np.array([48,48,48],np.uint8);RED=np.array([106,47,38],np.uint8)
def add(name,mask,semantic=None,color=RED):
    rgb=np.broadcast_to(BG,(H,W,3)).copy();rgb[mask]=color;cases.append((name,rgb,semantic))
legacy=json.loads((root/'src/sim/fixtures/shape_field/manifest.json').read_text())
for row in legacy['cases']:
    m=np.loadtxt(root/'src/sim/fixtures/shape_field'/row['file'],dtype=np.uint8).reshape(H,W)>0
    semantic=3 if row['name'] in ['ring','triangle_tracking_base','triangle_caption_outlier'] else 1 if row['name'].startswith('circle') else 2
    add('legacy_'+row['name'],m,semantic)
base=(x>=70)&(x<414)&(y>=18)&(y<236)
m=base.copy()
for yy in range(24,228,12):
    for xx in range(78,404,10):m[yy:yy+2,xx:xx+2]=False
add('camera_like_342x218_many_fragments',m,2)
m=base.copy()
for yy in range(18,236):m[yy,78+(yy%2)*2:408:5]=False
add('sixty_plus_raw_holes_per_row',m,2)
rng=np.random.default_rng(42)
circle=(x-256)**2+(y-128)**2<=10000
for prob in [.1,.2,.25]:
    add(f'circle_noise_{prob}',circle & (rng.random((H,W))>=prob),1)
    add(f'rect_noise_{prob}',base & (rng.random((H,W))>=prob),2)
for fraction in [.25,.35,.4]:
    m=base.copy();side=int(344*fraction);m[22:232,242-side//2:242+(side-side//2)]=False
    add(f'rect_central_missing_{fraction}',m,2)
m=circle.copy()
for yy in list(range(25,29))+list(range(228,232)):
    m[yy,154:161]=True;m[yy,352:359]=True
add('circle_sparse_end_fragments',m,1)
for absent in [16,17]:
    m=np.zeros((H,W),bool);m[80:144,100:166]=True;m[100:100+absent,100:166]=False
    add(f'row_coverage_missing_{absent}',m,2 if absent==16 else 3)
for label,color,want in [('dark_red_24',[64,40,24],2),('dark_red_23',[63,40,24],0),
    ('ratio_equal',[90,60,50],2),('ratio_minus1',[89,60,50],0),('warm_skin',[200,140,130],0),
    ('warm_gray',[164,140,135],0),('white',[220,220,220],0),('green',[64,160,48],0),('wrap',[255,240,20],0)]:
    add(label,base,want,np.array(color,np.uint8))
m=np.zeros((H,W),bool);m[100:102,100:111]=True;add('too_small',m,0)
m=np.zeros((H,W),bool);m[50:230:12,80:414:12]=True;add('sparse_points',m,0)
m=base.copy();m[:]=False;m[18:236,70:414:12]=True;add('sparse_stripes',m,0)
# The density boundary shell uses smaller, single-run rows; large-profile
# acceptance is tested separately through the missing-centre targets above.
def density(width,height,area):
    m=np.zeros((H,W),bool);left,top=100,80;remain=area-2*width
    for yy in range(height):
        n=width if yy in [0,height-1] else remain//(height-2)+(yy<=remain%(height-2))
        lo=left+(width-n)//2;m[top+yy,lo-1:lo+n+1]=True
    return m
for area,want in [(208,2),(207,1),(144,1),(142,3)]:add(f'fill_raw_before_cleanup_{area}',density(16,16,area),want)
for width,want in [(66,1),(67,3)]:
    cx,rx=(256.5,34) if width==66 else (256,34.5)
    add(f'aspect_2to1_margin_{width}',((x-cx)/rx)**2+((y-128.5)/16.5)**2<=1,want)

def oracle(rgb):
    a=rgb.astype(np.int32);r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
    red=(r>=g+24)&(r>=b+24)&(2*r>=3*g)&(2*r>=3*b)
    p=np.pad(red,1);neighbors=p[:-2,1:-1].astype(np.uint8)+p[2:,1:-1]+p[1:-1,:-2]+p[1:-1,2:]
    clean=red|(neighbors>=3);accepted=np.zeros((H,W),bool)
    accepted[:-2,1:-2]=clean[:-2,:-3]&clean[:-2,1:-2]&clean[:-2,2:-1]
    ys,xs=np.nonzero(accepted);area=len(xs)
    if not area:return [0,0,0,0,0,0,0],dict(area=0)
    x0,x1,y0,y1=int(xs.min()),int(xs.max()),int(ys.min()),int(ys.max());ww=x1-x0+1;hh=y1-y0+1;box=ww*hh
    rows=np.flatnonzero(accepted.any(axis=1));spans=[int(np.flatnonzero(accepted[yy])[-1]-np.flatnonzero(accepted[yy])[0]+1) for yy in rows]
    counts=accepted.sum(axis=1)[rows];top,bottom=sum(spans[:4]),sum(spans[-4:]);ct,cb=int(sum(counts[:4])),int(sum(counts[-4:]))
    outline=ww>=32 and hh>=32 and 2*top>=5*ww and 2*bottom>=5*ww and 2*ct>=top and 2*cb>=bottom
    row_ok=4*len(rows)>=3*hh;aspect=max(ww,hh)<=2*min(ww,hh)+2
    rect=16*area>=13*box or (outline and 16*area>=9*box)
    circ=16*area>=9*box and 16*area<13*box and aspect
    cls=0 if area<64 else 3 if not row_ok else 2 if rect else 1 if circ else 3
    why=0 if cls!=3 else 2 if not row_ok else 4 if 16*area>=9*box and 16*area<13*box and not aspect else 3
    return [cls,area,x0 if cls else 0,x1 if cls else 0,y0 if cls else 0,y1 if cls else 0,why],dict(area=area,width=ww,height=hh,fill=area/box,rows=len(rows),top_span=top,bottom_span=bottom,top_points=ct,bottom_points=cb,outline=bool(outline))
words=[];metadata=[]
for i,(name,rgb,semantic) in enumerate(cases):
    expected,stats=oracle(rgb)
    if semantic is not None:assert expected[0]==semantic,(name,semantic,expected,stats)
    fp=dest/f'{i:02d}.mem';packed=(rgb[:,:,0].astype(np.uint32)<<16)|(rgb[:,:,1].astype(np.uint32)<<8)|rgb[:,:,2]
    fp.write_text('\n'.join(f'{v:06x}' for v in packed.ravel())+'\n')
    words.extend(expected);metadata.append(dict(name=name,file=fp.name,expected=expected,stats=stats,sha256=hashlib.sha256(fp.read_bytes()).hexdigest()))
(dest/'expected.mem').write_text('\n'.join(f'{v:08x}' for v in words)+'\n')
(dest/'manifest.json').write_text(json.dumps(dict(width=W,height=H,count=len(cases),cases=metadata),indent=2))
print('RECALL_FIXTURES',len(cases),W,H)
