#!/usr/bin/env python3
"""Read-only gate. A local signing certificate must never pass this gate."""
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/Notch.app").resolve()
problems = []
def command(*args):
    return subprocess.run(args, text=True, capture_output=True)

info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
details = command("codesign", "-dv", "--verbose=4", str(app)).stderr
if "Authority=Developer ID Application:" not in details:
    problems.append("Needs Developer ID Application signing, not the personal/local certificate.")
if "runtime" not in details:
    problems.append("Hardened Runtime is not enabled.")
if "Timestamp=" not in details:
    problems.append("A secure signing timestamp is missing.")
if info.get("CFBundleIdentifier", "").startswith("local."):
    problems.append("Set the publisher's permanent bundle identifier before the first public binary.")
for args, reason in [
    (("codesign", "--verify", "--deep", "--strict", str(app)), "Code signature verification failed."),
    (("xcrun", "stapler", "validate", str(app)), "A valid notarization ticket is not stapled."),
    (("spctl", "--assess", "--type", "execute", str(app)), "Gatekeeper assessment did not pass.")
]:
    if command(*args).returncode:
        problems.append(reason)
if problems:
    print("PUBLIC BINARY RELEASE BLOCKED")
    for problem in problems:
        print("- " + problem)
    sys.exit(1)
print("Signing/notarization gate passed. This does not replace functional, privacy, licence or clean-Mac testing.")
