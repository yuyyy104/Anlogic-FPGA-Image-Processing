"""Complete raster positives/negatives; expected area/bbox from independent mask oracle."""
from pathlib import Path
import ast, json
import numpy as np
root=Path(__file__).resolve().parents[2]
W,H=320,256
dest=root/'src/sim/fixtures/shape_geometry';dest.mkdir(exist_ok=True)
tree=ast.parse((root/'prj/scripts/make_shape_recall_fixtures.py').read_text())
code=ast.unparse(next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='oracle'))
context=dict(np=np,W=W,H=H);exec(code,context);oracle=context['oracle']
y,x=np.indices((H,W));cases=[]
for family in ['rectangle','square','long_rectangle','circle','ellipse','damaged_rectangle','noisy_rectangle','noisy_circle']:
 for degree in sorted(set(range(0,91,10))|{45}):
  theta=np.deg2rad(degree);u=(x-160)*np.cos(theta)+(y-128)*np.sin(theta);v=-(x-160)*np.sin(theta)+(y-128)*np.cos(theta)
  a,b=(90,60) if family in ['rectangle','ellipse','damaged_rectangle','noisy_rectangle','noisy_circle'] else (65,65) if family in ['square','circle'] else (100,28)
  mask=(u*u/(a*a)+v*v/(b*b)<=1) if family in ['circle','ellipse','noisy_circle'] else (np.abs(u)<=a)&(np.abs(v)<=b)
  if family=='damaged_rectangle':mask &= ~((np.abs(u)<a*.60)&(np.abs(v)<b*.55))
  if family.startswith('noisy_'):mask &= np.random.default_rng(100+degree).random((H,W))>=.15
  cases.append((f'{family}_{degree}',mask,1 if family in ['circle','ellipse','noisy_circle'] else 2))
cases.extend([('empty',np.zeros_like(x,dtype=bool),0),('speckles',((x*37+y*11)%701)==0,0),('sparse_stripes',(x>50)&(x<270)&(y>40)&(y<210)&(x%12<3),3)])
words=[];manifest=[]
for i,(name,mask,want) in enumerate(cases):
 rgb=np.full((H,W,3),48,dtype=np.uint8);rgb[mask]=[255,32,32]
 exp,stats=oracle(rgb);exp[0]=want;exp[6]=0 if want!=3 else exp[6]
 packed=(rgb[:,:,0].astype(np.uint32)<<16)|(rgb[:,:,1].astype(np.uint32)<<8)|rgb[:,:,2]
 (dest/f'{i:02d}.mem').write_text('\n'.join(f'{p:06x}' for p in packed.ravel())+'\n')
 words.extend(exp);manifest.append(dict(name=name,want=want,reference=exp))
(dest/'expected.mem').write_text('\n'.join(f'{p:08x}' for p in words)+'\n')
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('GEOMETRY_FIXTURES',len(cases))
