#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
# The macOS 26.5 SDK currently bundled with this Mac's command-line tools is
# one patch behind its Swift compiler. The compatible SDK keeps local builds
# reproducible until Apple refreshes the command-line tools package.
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
if [[ ! -f Resources/AppIcon.icns || scripts/icon.swift -nt Resources/AppIcon.icns ]]; then
  swift scripts/icon.swift .build/AppIcon.iconset Resources/AppIcon.icns
fi
# Separate CLT builds avoid the full-Xcode dependency of SwiftPM's multi-arch backend.
swift build -c "$configuration" --arch arm64 --disable-sandbox --scratch-path .build --cache-path .build/cache
arm_binary_dir="$(swift build -c "$configuration" --arch arm64 --disable-sandbox --scratch-path .build --cache-path .build/cache --show-bin-path)"
swift build -c "$configuration" --arch x86_64 --disable-sandbox --scratch-path .build/intel --cache-path .build/cache
intel_binary_dir="$(swift build -c "$configuration" --arch x86_64 --disable-sandbox --scratch-path .build/intel --cache-path .build/cache --show-bin-path)"
package_stage="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$package_stage"' EXIT
app_bundle="$package_stage/NotchHarbor.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
xcrun lipo -create "$arm_binary_dir/Notch" "$intel_binary_dir/Notch" -output "$app_bundle/Contents/MacOS/Notch"
cp Resources/Info.plist "$app_bundle/Contents/Info.plist"
python3 scripts/configure-updates.py "$app_bundle"
cp Resources/DeviceEarbuds.png Resources/DeviceHeadphones.png "$app_bundle/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$app_bundle/Contents/Resources/AppIcon.icns"
fi
# Build the pinned, vendored MediaRemote adapter with the installed CLT.
framework="$app_bundle/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$framework/Versions/A/Resources"
# Replace the previous generated flat binary with a standard versioned framework.
if [[ -f "$framework/MediaRemoteAdapter" && ! -L "$framework/MediaRemoteAdapter" ]]; then
  rm "$framework/MediaRemoteAdapter"
fi
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$framework/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$framework/Resources"
cp Resources/MediaRemoteAdapter-Info.plist "$framework/Versions/A/Resources/Info.plist"
xcrun clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -I Vendor/mediaremote-adapter/include -I Vendor/mediaremote-adapter/src \
  Vendor/mediaremote-adapter/src/adapter/*.m Vendor/mediaremote-adapter/src/private/*.m Vendor/mediaremote-adapter/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -o "$framework/Versions/A/MediaRemoteAdapter"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$app_bundle/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$app_bundle/Contents/Resources/MediaRemoteAdapter-LICENSE"
# SwiftPM links the binary framework; our CLT packager must embed it, including
# the updater helpers, executable permissions and versioned-framework symlinks.
sparkle_distribution="$PWD/.build/artifacts/sparkle/Sparkle"
ditto "$sparkle_distribution/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_distribution/LICENSE" "$app_bundle/Contents/Resources/Sparkle-LICENSE"
python3 scripts/check-compatibility.py "$app_bundle"
python3 scripts/sign-app.py "$app_bundle"
# Do not overwrite the runnable app until the complete replacement is signed.
python3 scripts/install-local-build.py "$app_bundle" "$PWD/dist/NotchHarbor.app"
print "Built: $PWD/dist/NotchHarbor.app"
