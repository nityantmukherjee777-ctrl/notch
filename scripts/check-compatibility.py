#!/usr/bin/env python3
"""Verify deployment metadata for every shipped native executable, not runtime behavior."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/Notch.app").resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
minimum = info["LSMinimumSystemVersion"]
def version(value):
    return tuple(int(part) for part in value.split(".")) + (0,) * (3 - len(value.split(".")))

if version(minimum) != version("13.0"):
    raise SystemExit("Expected a macOS 13.0 minimum in the app's Info.plist")
macho_magic = {bytes.fromhex(value) for value in ["feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]}
executables = []
for path in sorted((app / "Contents").rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        if stream.read(4) not in macho_magic:
            continue
    architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(path)], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise SystemExit(f"Not universal: {path.relative_to(app)}: {architectures}")
    for architecture in architectures:
        metadata = subprocess.check_output(["xcrun", "vtool", "-arch", architecture, "-show-build", str(path)], text=True)
        match = re.search(r"(?:minos|version)\s+(\d+\.\d+(?:\.\d+)?)", metadata)
        if not match or version(match[1]) > version(minimum):
            raise SystemExit(f"Unsupported minimum: {path.relative_to(app)} ({architecture})\n{metadata}")
    executables.append(path)
if not executables or app / "Contents/MacOS/Notch" not in executables:
    raise SystemExit("Missing Notch executable")
print(f"PASS: {len(executables)} native binaries contain Intel and Apple silicon slices with macOS {minimum} or earlier deployment targets.")
print("This checks binary metadata; testing on older macOS and Intel hardware is still required.")
