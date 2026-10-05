#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/electromagnet-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/electromagnet-module-cache
swift test --disable-sandbox --scratch-path .build --cache-path /private/tmp/electromagnet-swift-cache --config-path /private/tmp/electromagnet-swift-config --security-path /private/tmp/electromagnet-swift-security -Xswiftc -module-cache-path -Xswiftc /private/tmp/electromagnet-module-cache
