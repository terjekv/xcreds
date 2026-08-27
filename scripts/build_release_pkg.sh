#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

team_id="${TEAM_ID:-SC6H7VDLB4}"
package_identifier="${PACKAGE_IDENTIFIER:-no.uio.math.pkg.xcreds}"
installer_identity="${INSTALLER_IDENTITY:-Developer ID Installer: Terje Kvernes (SC6H7VDLB4)}"
notary_profile="${NOTARY_PROFILE:-}"
output_dir="${OUTPUT_DIR:-${repo_root}/build/ReleaseArtifacts}"
work_dir="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/xcreds-release.XXXXXX")}"

archive_path="${work_dir}/XCreds.xcarchive"
export_path="${work_dir}/export"
export_options="${work_dir}/ExportOptions.plist"
derived_data_path="${work_dir}/DerivedData"
package_root="${work_dir}/package-root"
package_scripts="${work_dir}/package-scripts"
unsigned_package="${work_dir}/XCreds-unsigned.pkg"
signed_package="${work_dir}/XCreds-signed.pkg"
expanded_package="${work_dir}/expanded-package"

# productsign can leave a small, invalid output file when signing fails.
trap '/bin/rm -f "${signed_package}"' EXIT

for tool in xcodebuild codesign pkgbuild productsign pkgutil ditto; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Required tool not found: ${tool}" >&2
        exit 1
    fi
done

mkdir -p "${output_dir}" "${export_path}" "${package_root}/Applications" "${package_scripts}"
/usr/bin/ditto "${repo_root}/build_resources/exportOptions.plist" "${export_options}"
/usr/libexec/PlistBuddy -c "Set :teamID ${team_id}" "${export_options}"

echo "Release work directory: ${work_dir}"
echo "Archiving XCreds with Apple Developer team ${team_id}"

xcodebuild \
    -project "${repo_root}/XCreds.xcodeproj" \
    -scheme XCreds \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${archive_path}" \
    -derivedDataPath "${derived_data_path}" \
    -clonedSourcePackagesDirPath "${repo_root}/build/SourcePackages" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${team_id}" \
    archive

xcodebuild \
    -exportArchive \
    -archivePath "${archive_path}" \
    -exportPath "${export_path}" \
    -exportOptionsPlist "${export_options}" \
    -allowProvisioningUpdates

exported_app="${export_path}/XCreds.app"
if [ ! -d "${exported_app}" ]; then
    echo "Export did not produce ${exported_app}" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${exported_app}/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${exported_app}/Contents/Info.plist")"
package_version="${version}.${build_number}"
artifact_name="XCreds_Build-${build_number}_Version-${version}.pkg"
final_package="${output_dir}/${artifact_name}"

if [ -e "${final_package}" ]; then
    echo "Refusing to overwrite existing artifact: ${final_package}" >&2
    exit 1
fi

if [ -n "${VERSION:-}" ] && [ "${VERSION}" != "${version}" ]; then
    echo "Expected version ${VERSION}, but the exported app is ${version}" >&2
    exit 1
fi

if [ -n "${BUILD_NUMBER:-}" ] && [ "${BUILD_NUMBER}" != "${build_number}" ]; then
    echo "Expected build ${BUILD_NUMBER}, but the exported app is ${build_number}" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "${exported_app}"
/usr/bin/ditto "${exported_app}" "${package_root}/Applications/XCreds.app"

/usr/bin/ditto "${repo_root}/build_resources/Packages/XCreds/scripts/preinstall.sh" "${package_scripts}/preinstall"
/usr/bin/ditto "${repo_root}/build_resources/Packages/XCreds/scripts/postinstall.sh" "${package_scripts}/postinstall"
chmod 755 "${package_scripts}/preinstall" "${package_scripts}/postinstall"

pkgbuild \
    --root "${package_root}" \
    --component-plist "${repo_root}/build_resources/Packages/XCreds/components.plist" \
    --scripts "${package_scripts}" \
    --identifier "${package_identifier}" \
    --version "${package_version}" \
    --install-location / \
    "${unsigned_package}"

echo "Signing installer with ${installer_identity}"
productsign --sign "${installer_identity}" "${unsigned_package}" "${signed_package}"
pkgutil --check-signature "${signed_package}"

pkgutil --expand-full "${signed_package}" "${expanded_package}"
codesign --verify --deep --strict --verbose=2 "${expanded_package}/Payload/Applications/XCreds.app"
cmp "${package_scripts}/preinstall" "${expanded_package}/Scripts/preinstall"
cmp "${package_scripts}/postinstall" "${expanded_package}/Scripts/postinstall"

if [ -n "${notary_profile}" ]; then
    echo "Submitting installer to Apple's notary service"
    xcrun notarytool submit "${signed_package}" --keychain-profile "${notary_profile}" --wait
    xcrun stapler staple "${signed_package}"
    xcrun stapler validate "${signed_package}"
    spctl --assess --type install --verbose=4 "${signed_package}"
else
    echo "NOTARY_PROFILE is unset; the package will be signed but not notarized."
fi

/bin/mv "${signed_package}" "${final_package}"

echo "Created ${final_package}"
echo "Kept release work directory at ${work_dir}"
