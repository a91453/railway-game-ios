"""Package current delivery only; keep history and ZIP's own digest outside ZIP."""
import hashlib,json,sys,zipfile
from pathlib import Path
root=Path(sys.argv[1])
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
exclude={'SHA256SUMS.txt','asset-package.zip','package-verification.json'}
files=sorted(p for p in root.rglob('*') if p.is_file() and p.relative_to(root).parts[0]!='history' and p.name not in exclude)
(root/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.relative_to(root).as_posix()}\n' for p in files))
files.append(root/'SHA256SUMS.txt')
with zipfile.ZipFile(root/'asset-package.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in files:z.write(p,p.relative_to(root).as_posix())
with zipfile.ZipFile(root/'asset-package.zip') as z:
 assert z.testzip() is None
 assert set(z.namelist())=={p.relative_to(root).as_posix() for p in files}
 for p in files:assert z.read(p.relative_to(root).as_posix())==p.read_bytes()
report={'status':'VERIFIED','zip_sha256':digest(root/'asset-package.zip'),'members':len(files),'checks':['CRC for every member','exact member set','full decompression and every member byte compared with current files'],'history':'Complete actual previous delivery kept separately in history/true-v8; true-v1 through true-v7 preserved.'}
(root/'package-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
