#!/usr/bin/env python3
"""Inject public update configuration into the staged bundle before signing.

Never accept or store an update private key. An unconfigured personal build
includes Sparkle but does not start its updater or make update requests.
"""
import base64
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlsplit


def configure(info, environment):
    result = dict(info)
    feed = environment.get("NOTCH_UPDATE_FEED_URL", "")
    key = environment.get("NOTCH_SPARKLE_PUBLIC_KEY", "")
    if not feed and not key:
        if environment.get("NOTCH_PUBLIC_RELEASE") == "1":
            raise ValueError("Public builds require NOTCH_UPDATE_FEED_URL and NOTCH_SPARKLE_PUBLIC_KEY.")
        return result
    url = urlsplit(feed)
    if (url.scheme != "https" or not url.hostname or url.username is not None
            or url.password is not None or url.fragment or any(c.isspace() for c in feed)):
        raise ValueError("NOTCH_UPDATE_FEED_URL must be an HTTPS URL without credentials or a fragment.")
    try:
        decoded = base64.b64decode(key, validate=True)
    except ValueError:
        decoded = b""
    if len(decoded) != 32:
        raise ValueError("NOTCH_SPARKLE_PUBLIC_KEY must be Sparkle's base64-encoded 32-byte Ed25519 public key.")
    result["SUFeedURL"] = feed
    result["SUPublicEDKey"] = key
    return result


def main():
    path = Path(sys.argv[1]) / "Contents/Info.plist"
    info = plistlib.loads(path.read_bytes())
    try:
        result = configure(info, os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    path.write_bytes(plistlib.dumps(result))
    print("Sparkle: configured" if result.get("SUFeedURL") else "Sparkle: included; release feed not configured")


if __name__ == "__main__":
    main()
