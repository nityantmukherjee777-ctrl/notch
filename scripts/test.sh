#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$framework_dir/Testing.framework" ]]; then
  swift test --disable-sandbox --disable-xctest --scratch-path .build --cache-path .build/cache \
    -Xswiftc -F -Xswiftc "$framework_dir" \
    -Xlinker -rpath -Xlinker "$framework_dir" \
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
else
  swift test --disable-sandbox --disable-xctest --scratch-path .build --cache-path .build/cache
fi
