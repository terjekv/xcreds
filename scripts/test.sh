#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcreds-tests.XXXXXX")"
trap '/bin/rm -rf "${test_dir}"' EXIT
cd "${repo_root}"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
platform="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
frameworks="${platform}/Library/Frameworks"
for source in LegacyKeychainBridge TCSUnifiedLogger NSFileManager+TCSRealHomeFolder; do
    xcrun clang -fobjc-arc -isysroot "${sdk}" -c "XCreds/${source}.m" -o "${test_dir}/${source}.o"
done
xcrun swiftc -swift-version 5 -sdk "${sdk}" -F "${frameworks}" \
    -module-cache-path "${test_dir}/ModuleCache" -I "${platform}/usr/lib" -L "${platform}/usr/lib" \
    -framework XCTest -framework Security -framework Foundation \
    -Xlinker -rpath -Xlinker "${frameworks}" -Xlinker -rpath -Xlinker "${platform}/usr/lib" \
    -import-objc-header Tests/Bridge.h \
    Shared/AuthenticationPolicy.swift Shared/XCredsAudit.swift DataExtension.swift \
    XCreds/KeychainUtil.swift XCreds/LoggerHelper.swift Tests/main.swift \
    "${test_dir}"/*.o -o "${test_dir}/XCredsTests"
# A stable ad-hoc code hash allows disposable keychain ACLs to trust only this test process.
codesign --force --sign - "${test_dir}/XCredsTests"
XCREDS_TEST_ROOT="${test_dir}/fixtures" "${test_dir}/XCredsTests"
python3 scripts/check_repository.py
