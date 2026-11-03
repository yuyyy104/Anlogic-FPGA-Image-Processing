"""Independent palette-component fixtures for multiple coloured shapes."""
from pathlib import Path
import json
import numpy as np
import cv2
import argparse

parser=argparse.ArgumentParser()
parser.add_argument('--hd',action='store_true')
parser.add_argument('--noise',action='store_true')
args=parser.parse_args()

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/('src/sim/fixtures/color_shapes_hd' if args.hd else 'src/sim/fixtures/color_shapes_noise' if args.noise else 'src/sim/fixtures/color_shapes')
OUT.mkdir(parents=True,exist_ok=True)
W,H=(1280,720) if args.hd else (512,256)
PALETTE={1:(220,45,35),2:(35,210,45),3:(30,45,220),4:(215,210,30)}
cases=[]

def build(name,objects):
    image=np.full((H,W,3),96,np.uint8)
    shape_masks=[]
    for color,shape,center,size,angle in objects:
        mask=np.zeros((H,W),np.uint8)
        cx,cy=center;w,h=size
        if shape==1:
            cv2.ellipse(mask,(cx,cy),(w//2,h//2),angle,0,360,1,-1)
        elif shape==4:
            points=np.array([[-w/2,h/2],[w/2,h/2],[0,-h/2]],float)
            r=np.deg2rad(angle);rotation=np.array([[np.cos(r),-np.sin(r)],[np.sin(r),np.cos(r)]])
            points=np.rint(points@rotation.T+[cx,cy]).astype(np.int32)
            cv2.fillConvexPoly(mask,points,1)
        else:
            points=np.rint(cv2.boxPoints(((cx,cy),(w,h),angle))).astype(np.int32)
            cv2.fillConvexPoly(mask,points,1)
        assert not any(np.any(mask&m) for m in shape_masks)
        shape_masks.append(mask)
        image[mask!=0]=PALETTE[color]
    if args.noise:
        fraction=int(name.split('_')[-1])/100
        missing=np.random.default_rng(9821+len(cases)).random((H//4,W//4))<fraction
        missing=np.repeat(np.repeat(missing,4,axis=0),4,axis=1)
        image[missing]=96
    # Independent OpenCV flood fill defines actual sampled components, including
    # raster boundaries and any quantisation of analytic shapes.
    sampled=image[::4,::4]
    components=[]
    for color,rgb in PALETTE.items():
        binary=np.all(sampled==rgb,axis=2).astype(np.uint8)
        n,labels,stats,_=cv2.connectedComponentsWithStats(binary,8)
        for i in range(1,n):
            x,y,w,h,area=map(int,stats[i])
            if area<9:continue
            matches=[o for o,m in zip(objects,shape_masks) if o[0]==color and np.any((labels==i)&(m[::4,::4]!=0))]
            assert len(matches)==1
            shape=matches[0][1]
            components.append(dict(color=color,shape=shape,area=area*16,bbox=[x*4,(x+w-1)*4,y*4,(y+h-1)*4]))
    components.sort(key=lambda x:-x['area'])
    # Fixtures use distinct areas; slot ties otherwise follow colour/pass order.
    assert len({c['area'] for c in components})==len(components)
    encoded=(image[:,:,0].astype(np.uint32)<<16)|(image[:,:,1].astype(np.uint32)<<8)|image[:,:,2]
    (OUT/(name+'.mem')).write_text('\n'.join(f'{v:06x}' for v in encoded.ravel())+'\n')
    while len(components)<4:components.append(dict(color=0,shape=0,area=0,bbox=[0]*4))
    c=dict(name=name,components=components[:4],count=sum(c['area']!=0 for c in components),objects=objects)
    cases.append(c)

if args.noise:
    for fraction in [5,10,15,20]:
        build('noise_'+str(fraction),[(1,1,(85,78),(104,104),0),(2,2,(268,82),(160,80),25),(3,3,(430,78),(76,76),40),(4,4,(260,200),(120,84),0)])
elif args.hd:
    build('hd_four',[(1,1,(190,190),(200,200),0),(2,2,(1120,180),(224,120),30),(3,3,(1116,560),(160,160),45),(4,4,(310,560),(200,180),35)])
    build('hd_large',[(1,2,(620,360),(1000,560),0)])
    build('hd_full',[(2,2,(640,360),(1280,720),0)])
    build('hd_edges',[(4,2,(1160,650),(232,128),0),(3,3,(70,70),(136,136),0)])
    build('hd_five',[(1,1,(140,180),(200,200),0),(2,2,(450,180),(256,112),15),(3,3,(810,180),(160,160),30),(4,4,(1130,180),(176,160),0),(2,1,(640,540),(128,128),0)])
    build('hd_empty',[])
else:
 build('four_colours',[(1,1,(80,72),(88,88),0),(2,2,(225,70),(120,56),0),(3,3,(370,70),(64,64),0),(4,4,(275,188),(112,76),0)])
if not args.hd and not args.noise:
 build('same_colour',[(2,1,(80,78),(100,100),0),(2,2,(245,78),(120,60),30),(3,4,(395,165),(88,100),35)])
for angle in ([] if args.hd or args.noise else [0,15,30,45,60,75,90]):
    build('rotated_'+str(angle),[(1,2,(125,125),(160,72),angle),(3,3,(345,125),(88,88),angle)])
if not args.hd and not args.noise:
 build('triangle_rotations',[(1,4,(90,105),(112,100),0),(2,4,(260,130),(96,104),90),(4,4,(425,95),(80,88),35)])
 build('overlapping_boxes',[(2,1,(110,88),(64,64),0),(2,1,(162,140),(60,60),0)])
for phase in ([] if args.hd or args.noise else range(16)):
    dx,dy=phase%4,phase//4
    build('small_circle_'+str(phase),[(1,1,(100+dx,100+dy),(24,24),0)])
if not args.hd and not args.noise:build('empty',[])
(OUT/'cases.json').write_text(json.dumps(dict(size=[W,H],cases=cases),indent=2)+'\n')
spec='function [25:0] expected_color_shape; input integer f,s; begin expected_color_shape=0;case(f*4+s)\n'
for f,c in enumerate(cases):
    for i,e in enumerate(c['components']):spec+=f"{f*4+i}:expected_color_shape=26'h{(e['color']<<23)|(e['shape']<<20)|e['area']:07x};\n"
spec+='endcase end endfunction\n'
spec+='function [47:0] expected_box; input integer f,s;begin expected_box=0;case(f*4+s)\n'
for f,c in enumerate(cases):
    for i,e in enumerate(c['components']):
        box=0
        for v in e['bbox']:box=(box<<12)|v
        spec+=f"{f*4+i}:expected_box=48'h{box:012x};\n"
spec+='endcase end endfunction\n'
spec+=f'localparam CASES={len(cases)};\n'
spec+='function [7:0] expected_total; input integer f;begin expected_total=0;case(f)\n'
for f,c in enumerate(cases):spec+=f"{f}:expected_total={c['count']};\n"
spec+='endcase end endfunction\n'
spec+='function [2047:0] fixture_name; input integer f;begin case(f)\n'
for f,c in enumerate(cases):spec+=f'{f}:fixture_name="{(OUT/(c["name"]+".mem")).as_posix()}";\n'
spec+='default:fixture_name="";endcase end endfunction\n'
(OUT/'expected.vh').write_text(spec)
print('FIXTURES',len(cases))
