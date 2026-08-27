# Building XCreds

## Requirements

- A Mac with full Xcode installed (Xcode 26.6 is currently verified).
- Xcode's command-line tools selected with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Xcode's license and first-launch components installed with `sudo xcodebuild -runFirstLaunch`.
- Internet access the first time Swift Package Manager resolves the public dependencies.

An Apple Developer account and signing certificate are not required for an unsigned development build.

## Build

```sh
git clone https://github.com/twocanoes/xcreds.git
cd xcreds

xcodebuild -resolvePackageDependencies \
  -project XCreds.xcodeproj \
  -scheme XCreds \
  -clonedSourcePackagesDirPath build/SourcePackages

xcodebuild \
  -project XCreds.xcodeproj \
  -scheme XCreds \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  build
```

Build products are written to `build/DerivedData/Build/Products/Debug`.

## Public dependencies

- [OIDCLite](https://github.com/twocanoes/OIDCLite), MIT License.
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser), Apache License 2.0.
- The utility sources in the `BSD Licensed Tools` Xcode group, covered by this repository's BSD 3-Clause license.

## Not required

- Carthage.
- Git submodules or access to `tcsopensourcetools`.
- ProductLicense or Paddle frameworks.
- Two Canoes' private release scripts, credentials, signing identity, or Apple Developer team.

## Signing and distribution

Deployable builds use Apple Developer team `SC6H7VDLB4` and the `no.uio.math.xcreds` identifier namespace. Install the corresponding Apple Development or Developer ID certificates and provisioning profiles, then archive and notarize using that account.

The upstream release script is maintainer-specific and performs commits, tags, pushes, uploads, and calls an external packaging script. It is not needed for compiling XCreds and should not be run as a general build command.

## Release installer

The native release workflow archives and exports a Developer ID-signed universal app, creates a component package with the installation hooks, signs the installer, validates its payload, and optionally submits it to Apple's notary service:

```sh
./scripts/build_release_pkg.sh
```

The output is `build/ReleaseArtifacts/XCreds_Build-<build>_Version-<version>.pkg`. The script refuses to overwrite an existing artifact. It accepts these optional environment variables:

- `NOTARY_PROFILE`: a `notarytool` keychain profile. When omitted, the package is signed but not notarized.
- `OUTPUT_DIR` and `WORK_DIR`: alternate artifact and temporary-work directories.
- `TEAM_ID`, `INSTALLER_IDENTITY`, and `PACKAGE_IDENTIFIER`: signing overrides for another authorized deployment.
- `VERSION` and `BUILD_NUMBER`: assertions that fail the release if the exported app has unexpected version metadata.

Store notarization credentials once, using an app-specific password or App Store Connect API key supported by `notarytool`. Do not put credentials in this repository:

```sh
xcrun notarytool store-credentials math-uio-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id SC6H7VDLB4

NOTARY_PROFILE=math-uio-notary ./scripts/build_release_pkg.sh
```

On a remotely accessed Mac, the private-key access prompt is still a GUI operation. Run the first `codesign` or `productsign` invocation from Terminal.app in the logged-in desktop session and choose **Always Allow**. A headless build machine instead needs a dedicated keychain populated from an authorized PKCS#12 export, with access explicitly granted to `/usr/bin/codesign` and `/usr/bin/productsign`.
