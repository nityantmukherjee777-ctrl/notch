#!/usr/bin/env python3
"""Read-only allowlist and credential-pattern scan of Git history or the index.
Not an exhaustive secret detector; do not print matching contents.
"""
import argparse
from pathlib import PurePosixPath
import re
import subprocess

DOCS = {".gitignore", "Package.swift", "Package.resolved", "README.md", "LICENSE",
        "BACKLOG.md", "PRODUCTION.md", "LOCAL_SIGNING.md", "UPDATES.md", "COMPATIBILITY.md",
        "THIRD_PARTY.md", "SECURITY.md", "PRIVACY.md", "AUDIT.md", "RELEASE_NOTES.md",
        "INSTALLATION.md", "PUBLICATION_AUDIT.md"}
ROOTS = {"Sources", "Tests", "scripts", "Resources", "Vendor"}
FORBIDDEN = {".p12", ".pfx", ".pem", ".key", ".keychain", ".keychain-db", ".docx", ".dmg", ".zip", ".pyc"}
PATTERNS = {
    "private-key header": rb"(?m)^-----BEGIN [A-Z ]*PRIVATE KEY-----\r?$",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "OpenAI project key": rb"\bsk-proj-[A-Za-z0-9_-]{30,}",
    "personal home path": rb"/Users/(?!test(?:/|\b)|example(?:/|\b)|USERNAME(?:/|\b)|<)[A-Za-z0-9._-]+/",
}

def git(*args):
    return subprocess.check_output(["git", *args])

def inspect(path, mode, blob):
    parts = PurePosixPath(path).parts
    if not (path in DOCS or (parts and parts[0] in ROOTS)):
        raise SystemExit(f"Unexpected published path: {path}")
    if (path != ".gitignore" and any(p.startswith(".") for p in parts)) or PurePosixPath(path).suffix.lower() in FORBIDDEN:
        raise SystemExit(f"Excluded file type or hidden file: {path}")
    if mode not in {"100644", "100755"}:
        raise SystemExit(f"Unexpected symlink or submodule: {path}")
    data = git("cat-file", "blob", blob)
    for label, pattern in PATTERNS.items():
        if re.search(pattern, data):
            raise SystemExit(f"Review required: {label} in {path} (contents withheld)")

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ref", default="HEAD")
parser.add_argument("--staged", action="store_true")
args = parser.parse_args()
checked = set()
snapshots = [None] if args.staged else git("rev-list", args.ref).decode().splitlines()
latest_count = 0
for index, commit in enumerate(snapshots):
    raw = git("ls-files", "-s", "-z") if args.staged else git("ls-tree", "-r", "-z", commit)
    entries = [entry for entry in raw.split(b"\0") if entry]
    if index == 0: latest_count = len(entries)
    for entry in entries:
        meta, path = entry.split(b"\t", 1)
        fields = meta.decode().split()
        mode, blob = (fields[0], fields[1]) if args.staged else (fields[0], fields[2])
        key = (path, mode, blob)
        if key not in checked:
            inspect(path.decode(), mode, blob)
            checked.add(key)
print(f"PASS: {latest_count} current files, {len(snapshots)} {'index' if args.staged else 'history'} snapshots, {len(checked)} distinct file versions; no allowlist or credential-pattern findings.")
print("This is a scoped check, not proof that every possible secret or vulnerability is absent.")
