# Stable local signing

macOS associates privacy grants with the app's code-signing requirement. The
previous ad-hoc requirement was a hash of a specific build. Every changed build
therefore had a different permission identity. A normal quit/relaunch of the
exact same signed binary should not change that identity.

## One-time setup

`python3 scripts/setup-local-signing.py` creates a private keychain and one
self-signed code-signing certificate in
`~/Library/Application Support/Notch/Signing`. It retains an existing identity,
does not modify system trust roots, and restores the keychain search list. The
private key and keychain password are not stored in the repository. Keep this
directory private and retain it for future builds; deleting it loses the local
signing identity.

The local certificate then needs **explicit owner approval** for a user-domain
trust entry constrained to `codeSign` and `/usr/bin/codesign`. This is required
before the signing tool will use the self-signed certificate. It does not add
SSL trust, grant Accessibility/audio access, or notarize the app. Do not replace
this scoped entry with blanket “Always Trust” settings.

After owner approval, the setup command is:

```sh
security add-trusted-cert -r trustRoot -p codeSign -a /usr/bin/codesign \
  -k "$HOME/Library/Application Support/Notch/Signing/Notch.keychain-db" \
  "$HOME/Library/Application Support/Notch/Signing/certificate.pem"
```

Alternatively, set `NOTCH_SIGNING_IDENTITY` to an existing Apple-issued signing
identity. Public distribution requires Developer ID and notarization, as
described in [PRODUCTION.md](PRODUCTION.md).

## Subsequent builds

Run `./scripts/build.sh`. It signs the framework and app with the retained
certificate and validates the package before replacing `dist/NotchHarbor.app`. A
signing failure leaves the existing app intact. No ad-hoc fallback is allowed.
During signing, the private keychain is added temporarily to the user's search
list so `codesign` can resolve the certificate chain; the original list is
restored even if signing fails. The user-domain trust entry remains restricted
to the signing tool and code-signing policy.
The designated requirement must pin the certificate and bundle identifier,
not only a bundle identifier or a build-specific code hash.

Switching from the old ad-hoc build requires one final macOS approval of the
new app identity. Do not routinely reset TCC, remove/re-add Accessibility
entries, regenerate certificates, or alternate between differently signed
copies. Check quit/relaunch and rebuild/relaunch separately before considering
permission persistence verified.

Reference: [Apple TN3127, code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
