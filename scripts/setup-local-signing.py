#!/usr/bin/env python3
"""Create one reusable signing identity for this Mac, without changing trust roots.

Private material lives outside the source tree. Never regenerate it on builds:
that would invalidate macOS privacy grants again. Developer ID is required for
public distribution; this identity is only for the owner's local build.
"""
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile

root = Path.home() / "Library/Application Support/Notch/Signing"
config = root / "identity.json"
if config.exists():
    print(f"Existing local identity retained: {config}")
    raise SystemExit(0)
os.umask(0o077)
root.mkdir(parents=True, exist_ok=True)
keychain = root / "Notch.keychain-db"
if keychain.exists():
    raise SystemExit("An unfinished signing setup exists. Inspect it rather than replacing the keychain.")

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        # Arguments may contain temporary key passwords; never print them.
        raise RuntimeError(f"{Path(args[0]).name} failed: {result.stderr.strip()}")
    return result.stdout

password = secrets.token_urlsafe(36)
search_list = shlex.split(run("security", "list-keychains", "-d", "user"))
with tempfile.TemporaryDirectory(prefix="notch-signing-") as scratch:
    temp = Path(scratch)
    (temp / "certificate.cnf").write_text("""[req]
distinguished_name = dn
x509_extensions = signing
prompt = no
[dn]
CN = Notch Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
    run("openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-x509",
        "-days", "3650", "-config", str(temp / "certificate.cnf"),
        "-keyout", str(temp / "key.pem"), "-out", str(temp / "certificate.pem"))
    (temp / "password").write_text(password)
    run("openssl", "pkcs12", "-export", "-inkey", str(temp / "key.pem"),
        "-in", str(temp / "certificate.pem"), "-name", "Notch Local Development",
        "-out", str(temp / "identity.p12"), "-passout", f"file:{temp / 'password'}")
    try:
        run("security", "create-keychain", "-p", password, str(keychain))
        run("security", "unlock-keychain", "-p", password, str(keychain))
        run("security", "import", str(temp / "identity.p12"), "-k", str(keychain),
            "-P", password, "-T", "/usr/bin/codesign")
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:",
            "-s", "-k", password, str(keychain))
    finally:
        run("security", "list-keychains", "-d", "user", "-s", *search_list)
    fingerprint = run("openssl", "x509", "-in", str(temp / "certificate.pem"),
                      "-noout", "-fingerprint", "-sha1").strip().split("=")[-1].replace(":", "")
    (root / "keychain-password").write_text(password)
    (root / "certificate.pem").write_bytes((temp / "certificate.pem").read_bytes())
    config.write_text(json.dumps({"identity": fingerprint, "keychain": str(keychain)}, indent=2) + "\n")
print(f"Created reusable local signing identity: {config}")
print("No system trust roots or privacy grants were changed.")
