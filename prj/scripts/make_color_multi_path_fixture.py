"""Golden connected components after CCM, spatial gains and the shared filter."""
from pathlib import Path
import json
import numpy as np
from scipy import ndimage
import argparse
import re

root=Path(__file__).resolve().parents[2]
out=root/'src/sim/fixtures/color_multi_path';out.mkdir(exist_ok=True)
spec=json.loads((root/'src/sim/fixtures/color_shapes/cases.json').read_text())
image=np.array([int(v,16) for v in (root/'src/sim/fixtures/color_shapes/four_colours.mem').read_text().split()],np.uint32).reshape(256,512)
rgb=np.stack([(image>>16)&255,(image>>8)&255,image&255],axis=-1).astype(np.int64)
matrix=np.array([[286,-55,25],[-25,283,-2],[9,-56,303]])
ccm=np.clip((rgb@matrix.T+128)//256,0,255)
parser=argparse.ArgumentParser()
parser.add_argument('--coefficients',default='src/rtl/isp/spatial_color_coeff.vh')
args=parser.parse_args()
coefficient_text=(root/args.coefficients).read_text()
if Path(args.coefficients).suffix=='.json':
    coefficients=json.loads(coefficient_text)['gains_q8_rgb']
else:
    rows=re.findall(r"7'd(\d+): spatial_node=\{10'd(\d+),10'd(\d+),10'd(\d+)\}",coefficient_text)
    assert [int(row[0])for row in rows]==list(range(77))
    coefficients=[[int(value)for value in row[1:]]for row in rows]
nodes=np.array(coefficients).reshape(7,11,3)
yy,xx=np.indices((256,512));fy=(yy%128)[...,None];fx=(xx%128)[...,None];i=yy//128;j=xx//128
gain=(nodes[i,j]*(128-fx)*(128-fy)+nodes[i,j+1]*fx*(128-fy)+nodes[i+1,j]*(128-fx)*fy+nodes[i+1,j+1]*fx*fy+8192)//16384
spatial=np.clip((ccm*gain+128)//256,0,255)
objects=spec['cases'][0]['objects']
rows=[]
for dn in (0,1):
    if dn:
        pad=np.pad(spatial,((1,1),(1,1),(0,0)))
        tiles=np.stack([pad[a:a+256,b:b+512] for a in range(3) for b in range(3)])
        med=np.sort(tiles,axis=0)[4]
        weights=np.array([1,2,1,2,4,2,1,2,1])[:,None,None,None]
        gauss=(np.sum(tiles*weights,axis=0)+8)//16
        filtered=(med+gauss+1)//2
    else:filtered=spatial
    quality=np.zeros_like(filtered);quality[1:,1:]=filtered[:-1,:-1]
    sample=quality[::4,::4];r,g,b=sample.transpose(2,0,1)
    palette=np.zeros(r.shape,np.uint8)
    for color,a,c,d in [(1,r,g,b),(2,g,r,b),(3,b,r,g)]:
        palette[(a>=32)&(a>=c+18)&(a>=d+18)&(2*a>=3*c)&(2*a>=3*d)]=color
    palette[(r>=32)&(g>=32)&(r>=b+18)&(g>=b+18)&(2*r>=3*b)&(2*g>=3*b)&(2*r<=3*g)&(2*g<=3*r)]=4
    components=[]
    for color in (1,2,3,4):
        labels,n=ndimage.label(palette==color,structure=np.ones((3,3),dtype=np.uint8))
        areas=np.bincount(labels.ravel())
        for k,bounds in enumerate(ndimage.find_objects(labels),1):
            if bounds is None:continue
            ys,xs=bounds
            x,y,w,h,area=xs.start,ys.start,xs.stop-xs.start,ys.stop-ys.start,int(areas[k])
            if area<9:continue
            shape=next(o[1] for o in objects if o[0]==color)
            components.append(dict(color=color,shape=shape,area=area*16,bbox=[x*4,(x+w-1)*4,y*4,(y+h-1)*4]))
    assert len(components)==4
    components.sort(key=lambda c:-c['area']);rows.append(components)
    encoded=(quality[:,:,0]<<16)|(quality[:,:,1]<<8)|quality[:,:,2]
    (out/f'quality-dn{dn}.mem').write_text('\n'.join(f'{v:06x}' for v in encoded.ravel())+'\n')
(out/'expected.json').write_text(json.dumps(dict(components=rows,source_sha256=__import__('hashlib').sha256((root/'src/sim/fixtures/color_shapes/four_colours.mem').read_bytes()).hexdigest(),coefficients_sha256=__import__('hashlib').sha256((root/args.coefficients).read_bytes()).hexdigest()),indent=2)+'\n')
s='function [25:0] path_result;input integer dn,slot;begin path_result=0;case(dn*4+slot)\n'
for dn,components in enumerate(rows):
    for slot,c in enumerate(components):s+=f"{dn*4+slot}:path_result=26'h{(c['color']<<23)|(c['shape']<<20)|c['area']:07x};\n"
s+='endcase end endfunction\nfunction [47:0] path_box;input integer dn,slot;begin path_box=0;case(dn*4+slot)\n'
for dn,components in enumerate(rows):
    for slot,c in enumerate(components):
        box=0
        for a in c['bbox']:box=(box<<12)|a
        s+=f"{dn*4+slot}:path_box=48'h{box:012x};\n"
s+='endcase end endfunction\n'
(out/'expected.vh').write_text(s)
print(json.dumps(rows))
