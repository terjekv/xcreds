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

The repository's release script is maintainer-specific and performs commits, tags, pushes, uploads, and calls an external packaging script. It is not needed for compiling XCreds and should not be run as a general build command.
