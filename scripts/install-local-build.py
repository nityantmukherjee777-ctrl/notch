#!/usr/bin/env python3
"""Replace only a completely signed bundle, preserving the prior app on failure."""
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

source, destination = map(lambda p: Path(p).resolve(), sys.argv[1:3])
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)], check=True)
destination.parent.mkdir(parents=True, exist_ok=True)
backup = Path(tempfile.mkdtemp(prefix=".notch-previous-", dir=destination.parent))
previous = backup / "Notch.app"
if destination.exists():
    destination.rename(previous)
try:
    source.rename(destination)
except BaseException:
    # A failed rollback must retain the previous bundle for manual recovery.
    if previous.exists():
        previous.rename(destination)
    backup.rmdir()
    raise
else:
    shutil.rmtree(backup)
