# Source-publication review — October 2, 2026

The initial public source commit is
`9c043f9d44366dc71d3382ec91c835cda5f04b7d`: 111 files and one history snapshot.
The actual GitHub tree was retrieved and compared with its Git blobs. It contains
project source, tests, build scripts, release documentation, project-generated
artwork and the vendored BSD media adapter. No unrelated documents, chat logs,
account/session files, environment files, signing certificates/private keys,
authentication configuration, build caches, app bundles or disk images were
found in that published tree. Author metadata uses the GitHub noreply address.

The build 22 update was reviewed against the same publication boundaries before
push. The repository has a default-deny root allowlist; source exports use a
separate explicit allowlist. Installed build tools, vendor Git metadata and
all local artifacts stay excluded. Third-party source and license notices
remain public intentionally. Historical product names are retained in release
notes where they describe previous builds.

`scripts/audit-public-source.py` checks every reachable commit snapshot for
unexpected paths/file types, symlinks/submodules, private-key headers, common
GitHub/OpenAI/AWS credential patterns and personal home paths. It can inspect
the staged index before publishing and a fetched remote ref afterwards:

```sh
python3 scripts/audit-public-source.py --staged
python3 scripts/audit-public-source.py --ref origin/main
```

No findings were detected in the reviewed files. This combines file inventory,
pattern scanning and a source review; it cannot guarantee that every possible
secret or vulnerability is absent. Do not publish an archive of the working
folder. Publish only the reviewed source export or signed, separately reviewed
release artifact. The prepared personal/test DMG is local, not uploaded, and
contains only its signed app, Applications link, setup instructions and Finder
assets/metadata. It is not notarized and does not yet supply an update feed.
