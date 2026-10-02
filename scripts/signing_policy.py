"""Explicit personal-build exception; verified distribution never inherits it."""


def host_entitlements(base, *, local_identity, public_release, allow_local_sparkle):
    result = dict(base)
    exception = "com.apple.security.cs.disable-library-validation"
    if public_release and (allow_local_sparkle or result.get(exception)):
        raise ValueError("Public release signing must retain library validation.")
    if local_identity:
        if not allow_local_sparkle:
            raise ValueError(
                "The retained personal certificate has no Apple Team ID, so macOS cannot load Sparkle with library validation. "
                "Use an Apple signing identity, or explicitly approve the personal-build exception with NOTCH_ALLOW_LOCAL_SPARKLE=1. "
                "The existing app has not been replaced.")
        result[exception] = True
    return result
