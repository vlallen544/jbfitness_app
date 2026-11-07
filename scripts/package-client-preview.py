"""Create a smaller ZIP download containing the unchanged, verified preview APK."""
import hashlib
from pathlib import Path
import sys
import zipfile


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
    return result.hexdigest()


folder = Path(sys.argv[1] if len(sys.argv) > 1 else 'artifacts/client-preview')
apk_name = 'JB_Fitness_Client_Preview.apk'
names = [apk_name, 'INSTALL.txt', 'SHA256SUMS.txt']
for name in names:
    if not (folder / name).is_file():
        raise SystemExit(f'Missing preview handover file: {name}')
expected = (folder / 'SHA256SUMS.txt').read_text().split()[0]
target = folder / 'JB_Fitness_Client_Preview.zip'
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name in names:
        archive.write(folder / name, arcname=name)
with zipfile.ZipFile(target) as archive:
    with archive.open(apk_name) as stream:
        if digest(stream) != expected:
            raise SystemExit('The archived APK does not match its verified checksum.')
    for name in names[1:]:
        if archive.read(name) != (folder / name).read_bytes():
            raise SystemExit(f'The archived {name} does not match the original.')
with target.open('rb') as stream:
    checksum = digest(stream)
(folder / (target.name + '.sha256')).write_text(f'{checksum}  {target.name}\n')
print(f'ZIP ready: {target} ({target.stat().st_size} bytes); embedded APK checksum verified.')
