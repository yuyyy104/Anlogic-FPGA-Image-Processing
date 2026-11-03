from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[2]
source=root/'prj/td/lab_ex3_sc520/user_source/hdl_source/anlogic_logo_rom.v'
text=source.read_text();pixels=[0]*(160*160)
rows=re.findall(r"15'd(\d+): O_pixel = 25'h([0-9a-fA-F]+);",text)
assert rows and "default: O_pixel = 25'd0;" in text
for addr,value in rows:
    addr=int(addr);assert 0<=addr<len(pixels);pixels[addr]=int(value,16)
folder=root/'src/sim/fixtures/logo_stage';folder.mkdir(exist_ok=True)
target=folder/'pixels.mem';target.write_text(''.join(f'{x:07x}\n' for x in pixels))
(folder/'fixture.json').write_text(json.dumps({'source':source.relative_to(root).as_posix(),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'entries':len(pixels),'opaque_entries':len(rows),
    'memory_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'oracle':'independent ROM case literal extraction; no DUT signal used'},indent=2))
print('LOGO_FIXTURE',len(pixels),len(rows))
