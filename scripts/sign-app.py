#!/usr/bin/env python3
"""Sign with an explicit Developer ID identity or the retained local identity."""
import json
import os
import plistlib
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
from signing_policy import host_entitlements

app = Path(sys.argv[1]).resolve()
root = Path.home() / "Library/Application Support/Notch/Signing"
identity = os.environ.get("NOTCH_SIGNING_IDENTITY")
local_identity = not identity
public_release = os.environ.get("NOTCH_PUBLIC_RELEASE") == "1"
if public_release and not identity:
    raise SystemExit("Public release requires NOTCH_SIGNING_IDENTITY set to a Developer ID Application identity. A local certificate cannot be published as a verified public build.")
bundle_id = plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier", "")
if not bundle_id or (public_release and bundle_id.startswith("local.")):
    raise SystemExit("Set a permanent publisher-owned bundle identifier before public signing.")
try:
    entitlements = host_entitlements(plistlib.loads(Path("Resources/Notch.entitlements").read_bytes()),
                                    local_identity=local_identity, public_release=public_release,
                                    allow_local_sparkle=os.environ.get("NOTCH_ALLOW_LOCAL_SPARKLE") == "1")
except ValueError as error:
    raise SystemExit(str(error)) from None
options = []
search_list = None
if not identity:
    if not (root / "identity.json").exists():
        raise SystemExit("No stable signing identity. Run python3 scripts/setup-local-signing.py once, or set NOTCH_SIGNING_IDENTITY. Ad-hoc fallback is intentionally disabled.")
    config = json.loads((root / "identity.json").read_text())
    identity = config["identity"]
    unlock = subprocess.run(["security", "unlock-keychain", "-p", (root / "keychain-password").read_text(), config["keychain"]], capture_output=True)
    if unlock.returncode:
        # Never let CalledProcessError include password-bearing arguments.
        raise SystemExit("Unable to unlock Notch's private signing keychain. The existing app has not been replaced.")
    options = ["--keychain", config["keychain"]]
if identity == "-":
    raise SystemExit("Ad-hoc signing would invalidate saved permissions. Choose a persistent signing identity.")
framework = app / "Contents/Frameworks/MediaRemoteAdapter.framework"
sparkle = app / "Contents/Frameworks/Sparkle.framework"
sparkle_version = sparkle / "Versions/B"
entitlements_file = None
try:
    with tempfile.NamedTemporaryFile(prefix="notch-signing-", suffix=".plist", delete=False) as stream:
        stream.write(plistlib.dumps(entitlements))
        entitlements_file = Path(stream.name)
    if options:
        # --keychain restricts identity lookup, but codesign also requires its
        # certificate chain to be on the search list. Restore the list after use.
        search_list = shlex.split(subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True))
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *search_list, config["keychain"]], check=True)
    # Sign inside out; --deep is for verification, not for applying signatures.
    # Preserve upstream helper entitlements rather than giving them the host's
    # Automation entitlement or weakening the host's library validation.
    nested = [(sparkle_version / "Autoupdate", ["--preserve-metadata=identifier,entitlements"]),
              (sparkle_version / "Updater.app", ["--preserve-metadata=identifier,entitlements"])]
    nested += [(path, ["--preserve-metadata=identifier,entitlements"])
               for path in sorted((sparkle_version / "XPCServices").glob("*.xpc"))]
    for path, extra in [*nested, (sparkle, []), (framework, []), (app, ["--entitlements", str(entitlements_file)])]:
        subprocess.run(["codesign", "--force", "--sign", identity, "--options", "runtime",
                        "--timestamp" if public_release else "--timestamp=none", *options, *extra, str(path)], check=True)
finally:
    if entitlements_file is not None:
        entitlements_file.unlink(missing_ok=True)
    if search_list is not None:
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *search_list], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
result = subprocess.run(["codesign", "-d", "-r-", str(app)], capture_output=True, text=True, check=True)
requirement = result.stdout + result.stderr
if ("designated => cdhash" in requirement or f'identifier {json.dumps(bundle_id)}' not in requirement
        or not ("certificate " in requirement or "anchor " in requirement)):
    raise SystemExit("Signing did not produce a reusable identity.")
print(requirement.strip())
if public_release:
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True, text=True, check=True).stderr
    if "Authority=Developer ID Application:" not in details or "TeamIdentifier=not set" in details or "Timestamp=" not in details:
        raise SystemExit("Public release rejected: Developer ID Application signature, Team ID and secure timestamp are required.")
