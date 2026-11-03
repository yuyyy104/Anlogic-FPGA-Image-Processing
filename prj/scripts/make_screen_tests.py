"""Deterministic screen diagnostics; reference code values are not measured light."""
from pathlib import Path
from fractions import Fraction
import av,numpy as np,json,hashlib
from PIL import Image,ImageDraw,ImageFont

OUT=Path(__file__).resolve().parents[2]/'docs/屏幕校准素材/2026-10-04'
OUT.mkdir(parents=True,exist_ok=True)
W,H,FPS=1280,720,30
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',30)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',22)
def canvas(title):
    im=Image.new('RGB',(W,H),(96,96,96));d=ImageDraw.Draw(im)
    d.rectangle((0,0,W,105),fill=(40,40,40));d.text((30,20),title,font=font,fill=(220,220,220))
    d.text((30,65),'Screen-relative test | Lock exposure and WB before RGB sampling',font=small,fill=(180,180,180))
    return im
def patch(number,rgb):
    im=canvas(f'PATCH {number:02d}  RGB {rgb[0]:03d} {rgb[1]:03d} {rgb[2]:03d}')
    ImageDraw.Draw(im).rectangle((384,160,895,671),fill=rgb)
    return im
def grey_chart(values,title):
    im=canvas(title);d=ImageDraw.Draw(im);width=1152//len(values)
    for n,v in enumerate(values):
        x=64+n*width;d.rectangle((x,170,x+width-1,560),fill=(v,v,v))
        d.text((x+5,585),str(v),font=small,fill=(20,20,20))
    return im
gray=[0,16,32,48,64,80,96,112,128,144,160,176,192,208,224,240]
high=[192,208,224,232,240,244,248,252,255]
cal=[(64,64,64),(96,96,96),(128,128,128),(160,160,160),(192,192,192),(224,224,224),
     (160,48,48),(208,64,64),(224,96,96),(48,160,48),(64,208,64),(96,224,96),
     (48,48,160),(64,64,208),(96,96,224),(48,160,160),(160,48,160),(160,160,48),
     (192,112,64),(112,64,192),(64,192,112),(192,64,112),(112,192,64),(64,112,192)]
validation=[(80,80,80),(144,144,144),(208,208,208),(184,72,40),(40,184,72),(72,40,184)]
sequences={
 '01_gray_and_highlights':[(grey_chart(gray,'GRAYSCALE - check monotonic levels'),10),(grey_chart(high,'HIGHLIGHTS - check clipping / lost steps'),10)],
 '02_channels':[(patch(n,c),5) for n,c in enumerate([(192,32,32),(32,192,32),(32,32,192),(32,192,192),(192,32,192),(192,192,32)],1)],
 '03_relative_calibration':[(patch(n,c),6) for n,c in enumerate(cal,1)],
 '04_holdout_validation':[(patch(n,c),6) for n,c in enumerate(validation,1)]}
shape=[]
for n,kind in enumerate(['NONE','CIRCLE','RECT','RING','TRIANGLE','TWO','CIRCLE_DIM','RECT_DIM']):
    im=canvas('SHAPE '+kind);d=ImageDraw.Draw(im);red=(208,48,48) if 'DIM' not in kind else (144,32,32)
    if 'CIRCLE' in kind:d.ellipse((490,260,790,560),fill=red)
    if 'RECT' in kind:d.rectangle((430,280,850,540),fill=red)
    if kind=='RING':d.ellipse((490,260,790,560),fill=red);d.ellipse((550,320,730,500),fill=(96,96,96))
    if kind=='TRIANGLE':d.polygon([(640,250),(430,560),(850,560)],fill=red)
    if kind=='TWO':d.ellipse((300,300,520,520),fill=red);d.rectangle((760,300,980,520),fill=red)
    shape.append((im,6))
sequences['05_shapes']=shape
manifest={'scope':'screen-relative diagnostics and fit; no physical colorimetric ground truth','width':W,'height':H,'fps':FPS,'encoding':'H264 yuv444p full range, BT.709 matrix; PNG authoritative input codes','calibration':cal,'holdout':validation,'files':[]}
def encode(name,seq):
    path=OUT/(name+'.mp4')
    if path.exists():raise FileExistsError(path)
    container=av.open(str(path),'w');stream=container.add_stream('libx264',rate=FPS)
    stream.width=W;stream.height=H;stream.pix_fmt='yuv444p'
    stream.options={'crf':'12','preset':'fast','x264-params':'range=pc:colorprim=bt709:transfer=iec61966-2-1:colormatrix=bt709'}
    stream.codec_context.color_range=2
    seconds=0
    for idx,(im,duration) in enumerate(seq):
        png=OUT/f'{name}_{idx+1:02d}.png';im.save(png)
        arr=np.asarray(im)
        for _ in range(duration*FPS):
            frame=av.VideoFrame.from_ndarray(arr,format='rgb24')
            frame=frame.reformat(format='yuv444p',src_colorspace='ITU709',dst_colorspace='ITU709',src_color_range=2,dst_color_range=2)
            for packet in stream.encode(frame):container.mux(packet)
        seconds+=duration
    for packet in stream.encode():container.mux(packet)
    container.close()
    manifest['files'].append({'file':path.name,'seconds':seconds,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    print('encoded',path.name,seconds,flush=True)
for name,seq in sequences.items():encode(name,seq)
(OUT/'manifest.json').write_bytes(json.dumps(manifest,indent=2).encode())
print('all deterministic materials complete')
