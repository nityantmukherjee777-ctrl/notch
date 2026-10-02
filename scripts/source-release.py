#!/usr/bin/env python3
"""Export only app sources and documentation, never the whole working folder."""
import hashlib
import os
import re
import tempfile
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent.parent
files = ["Package.swift", "Package.resolved", ".gitignore", "README.md", "LICENSE", "BACKLOG.md", "PRODUCTION.md", "LOCAL_SIGNING.md", "UPDATES.md", "COMPATIBILITY.md",
         "THIRD_PARTY.md", "SECURITY.md", "PRIVACY.md", "AUDIT.md", "RELEASE_NOTES.md"]
allowed = [root / name for name in files]
for directory in ["Sources", "Tests", "scripts", "Resources", "Vendor"]:
    for path in (root / directory).rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if any(part.startswith(".") or part in ["__pycache__", "node_modules"] for part in path.relative_to(root).parts):
            continue
        if path.suffix in [".pyc", ".p12", ".pem", ".key", ".keychain-db", ".docx"]:
            continue
        allowed.append(path)
destination = root / "dist/Notch-source.zip"
destination.parent.mkdir(exist_ok=True)
# Validate every input before creating an archive; never leave a partial release.
validated = []
for path in sorted(set(allowed)):
    if not path.is_file():
        raise SystemExit(f"Required release file missing: {path.name}")
    data = path.read_bytes()
    if re.search(rb"(?m)^-----BEGIN [A-Z ]*PRIVATE KEY-----\r?$", data):
        raise SystemExit(f"Private key marker found; refusing export: {path.name}")
    validated.append(path)
fd, temporary = tempfile.mkstemp(prefix=".Notch-source-", suffix=".zip", dir=destination.parent)
os.close(fd)
try:
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in validated:
            archive.write(path, "Notch/" + str(path.relative_to(root)))
    os.replace(temporary, destination)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)

digest = hashlib.sha256(destination.read_bytes()).hexdigest()
destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n")
print(f"Exported {len(set(allowed))} app files: {destination}")
