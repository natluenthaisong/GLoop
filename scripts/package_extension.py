#!/usr/bin/env python3
"""Package only the reviewed extension sources and license."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / "extension"
FILES = ["manifest.json", "background.js", "core.js", "content.js", "README.md"]
manifest = json.loads((EXT / "manifest.json").read_text())
assert manifest["permissions"] == ["activeTab", "scripting"]
assert not manifest.get("host_permissions")
output = ROOT / "dist" / "releases" / f"GLoop-YouTube-{manifest['version']}.zip"
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in FILES:
        source = EXT / name
        assert source.is_file() and not source.is_symlink()
        content = source.read_bytes()
        assert b"/Users/" not in content, f"Personal path in {name}"
        archive.writestr(f"GLoop-YouTube/{name}", content)
    archive.writestr("GLoop-YouTube/LICENSE", (ROOT / "LICENSE").read_bytes())
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(".sha256").write_text(f"{digest}  {output.name}\n")
print(f"{output}\nSHA-256: {digest}")
