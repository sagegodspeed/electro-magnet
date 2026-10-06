#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/electromagnet-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/electromagnet-module-cache
# Keep signed XCTest bundles outside file-provider folders that attach Finder metadata.
swift test --disable-sandbox --scratch-path /private/tmp/electromagnet-tests-build --cache-path /private/tmp/electromagnet-swift-cache --config-path /private/tmp/electromagnet-swift-config --security-path /private/tmp/electromagnet-swift-security -Xswiftc -module-cache-path -Xswiftc /private/tmp/electromagnet-module-cache
