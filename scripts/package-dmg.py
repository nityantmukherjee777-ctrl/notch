#!/usr/bin/env python3
"""Build a personal/test DMG; never publishes it or changes privacy settings."""
import argparse
import hashlib
import importlib.metadata
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / ".build/dmg-tools"))
PINNED = {"ds-store": "1.3.1", "mac-alias": "2.2.2"}
for package, version in PINNED.items():
    try:
        installed = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        installed = None
    if installed != version:
        raise SystemExit("Install pinned build tools first: python3 -m pip install --target .build/dmg-tools ds-store==1.3.1 mac-alias==2.2.2")
from ds_store import DSStore
from mac_alias import Alias

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def verify_app(app):
    run("codesign", "--verify", "--deep", "--strict", app)
    run(sys.executable, ROOT / "scripts/check-compatibility.py", app)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=ROOT / "dist/NotchHarbor.app")
args = parser.parse_args()
app = args.app.resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if app.name != "NotchHarbor.app" or info.get("CFBundleName") != "NotchHarbor":
    raise SystemExit("Expected a branded NotchHarbor.app bundle")
verify_app(app)
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
destination = ROOT / f"dist/NotchHarbor-{version}-{build}-local.dmg"
destination.parent.mkdir(exist_ok=True)
env = os.environ.copy()
env.setdefault("SDKROOT", "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk")
env["CLANG_MODULE_CACHE_PATH"] = str(ROOT / ".build/ModuleCache")
env["SWIFT_MODULECACHE_PATH"] = env["CLANG_MODULE_CACHE_PATH"]

# A generic /tmp mount path avoids embedding the developer's home/workspace in Finder aliases.
with tempfile.TemporaryDirectory(prefix="notchharbor-dmg-", dir="/tmp") as directory:
    work = Path(directory)
    stage = work / "stage"; stage.mkdir()
    run("ditto", app, stage / app.name)
    (stage / "Applications").symlink_to("/Applications", target_is_directory=True)
    (stage / "Start Here.txt").write_bytes((ROOT / "Resources/DMG-Start-Here.txt").read_bytes())
    (stage / ".background").mkdir()
    run("swift", "-sdk", env["SDKROOT"], ROOT / "scripts/dmg-background.swift", stage / ".background/install.tiff", env=env)
    editable = work / "editable.dmg"
    run("hdiutil", "create", "-srcfolder", stage, "-volname", "NotchHarbor", "-fs", "HFS+", "-format", "UDRW", editable)
    mount = work / "mount"; mount.mkdir()
    run("hdiutil", "attach", "-nobrowse", "-noautoopen", "-mountpoint", mount, editable)
    try:
        # /tmp resolves to /private/tmp; normalize before computing the volume-relative alias.
        background_alias = Alias.for_file(str((mount / ".background/install.tiff").resolve()))
        if background_alias.target.posix_path != b"/.background/install.tiff":
            raise RuntimeError("Background alias must stay inside the image")
        alias = background_alias.to_bytes()
        with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
            store["."]["vSrn"] = ("long", 1)
            store["."]["bwsp"] = {"ShowToolbar": False, "ShowStatusBar": False, "ShowSidebar": False, "ContainerShowSidebar": False, "PreviewPaneVisibility": False, "SidebarWidth": 180, "ShowPathbar": False, "ShowTabView": False, "WindowBounds": "{{180, 140}, {700, 448}}"}
            store["."]["icvp"] = {"viewOptionsVersion": 1, "backgroundType": 2, "backgroundColorRed": 0.965, "backgroundColorGreen": 0.965, "backgroundColorBlue": 0.965, "backgroundImageAlias": alias, "iconSize": 90.0, "textSize": 13.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0, "scrollPositionX": 0.0, "scrollPositionY": 0.0, "arrangeBy": "none", "showIconPreview": True, "showItemInfo": False, "labelOnBottom": True}
            store["."]["icvl"] = ("type", b"icnv")
            store[app.name]["Iloc"] = (180, 196)
            store["Applications"]["Iloc"] = (520, 196)
            store["Start Here.txt"]["Iloc"] = (350, 328)
    finally:
        run("hdiutil", "detach", mount)
    compressed = work / "release.dmg"
    run("hdiutil", "convert", editable, "-format", "UDZO", "-imagekey", "zlib-level=9", "-o", compressed)
    run("hdiutil", "verify", compressed)
    run("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount, compressed)
    try:
        expected = {app.name, "Applications", "Start Here.txt", ".background", ".DS_Store"}
        actual = {p.name for p in mount.iterdir()}
        # HFS may create these hidden volume bookkeeping directories.
        if actual - expected - {".fseventsd", ".Trashes", ".Spotlight-V100"} or not expected <= actual:
            raise RuntimeError("Unexpected disk image contents")
        if os.readlink(mount / "Applications") != "/Applications":
            raise RuntimeError("Invalid Applications link")
        verify_app(mount / app.name)
        if (mount / "Start Here.txt").read_bytes() != (stage / "Start Here.txt").read_bytes():
            raise RuntimeError("Installation instructions changed")
    finally:
        run("hdiutil", "detach", mount)
    # Keep an existing good image until every verification above succeeds.
    run("ditto", compressed, destination)
digest = hashlib.sha256(destination.read_bytes()).hexdigest()
destination.with_suffix(".dmg.sha256").write_text(f"{digest}  {destination.name}\n")
print(f"Prepared personal/test DMG (not notarized): {destination}")
