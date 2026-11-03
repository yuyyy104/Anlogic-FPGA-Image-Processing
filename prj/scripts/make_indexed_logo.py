"""Losslessly encode the existing 25-bit Logo case table for synchronous ROMs."""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[2]
source=root/'prj/td/lab_ex3_sc520/user_source/hdl_source/anlogic_logo_rom.v'
entries={int(a):int(v,16) for a,v in re.findall(r"15'd(\d+):\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)",source.read_text())}
assert len(entries)==6387 and min(entries)==5494 and max(entries)==20426
palette=[0]+sorted(set(entries.values()));index={v:i for i,v in enumerate(palette)}
assert len(palette)<=1024 and 20426-5494<16383
mapping=[0]*16384
for addr,pixel in entries.items():mapping[addr-5494]=index[pixel]
for addr in range(32768):
    key=addr-5494 if 5494<=addr<=20426 else 16383
    assert palette[mapping[key]]==entries.get(addr,0)
out=root/'src/rtl/osd/logo_data';out.mkdir(exist_ok=True)
(out/'index.dath').write_text(''.join(f'{v:03x}\n' for v in mapping))
(out/'palette.dath').write_text(''.join(f'{v:07x}\n' for v in palette+[0]*(1024-len(palette))))
report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'entries':len(entries),'palette_entries':len(palette),'addresses_verified':32768,'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.suffix=='.dath'}}
print('LOSSLESS_LOGO',report)
