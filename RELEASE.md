# math.uio XCreds 5.9.3 (9151) — stabilization candidate

This fork's version sequence is independent of upstream. It is based on upstream
5.9 (9148), with public dependency replacements, math.uio signing and preferences,
and the custom login controls from 5.9.2. This candidate selectively backports
fixes rather than merging upstream's 6.0 development branch.

## Changes

- Remove ID tokens, authorization URLs, and raw token responses from diagnostics.
  The debug preference now gates system logging too. Audit records retain status
  and timestamps, without storing or displaying identity-token contents.
- Scope credential reads, updates, and deletes to the requested/default user
  keychain. Migrate signing partitions on existing credentials before updating
  their contents; preserve application access rules and report ACL failures.
- Give configured LDAP password checks precedence over refresh-token checks and
  reject refresh results without a nonempty access token.
- Recheck SecureToken setup state after connectivity arrives. Remove block
  observers correctly, handle each wait once, and fall back to login on timeout.
- Preserve local aliases, including email-shaped aliases, when AD is not configured.
- Add automated authentication, logging, audit, and disposable-keychain tests,
  configuration validation, and CI with an unsigned universal Release build.
- Correct fork build instructions and the OneLogin sample preference domain;
  align bundle versions and record installer checksums and build provenance.

## Upstream backports

| Commit | Change |
| --- | --- |
| [25a05ab](https://github.com/twocanoes/xcreds/commit/25a05abe68b0fc324cccb7ef3f9cdf0698cb7338) | SecureToken/autologin fix included in upstream 5.9.1; adapted with observer ownership and timeout cleanup |
| [23225af](https://github.com/twocanoes/xcreds/commit/23225affba70d184cb321a1660ba46ca5bccd496) | Reject refresh responses without access tokens |
| [e8b428e](https://github.com/twocanoes/xcreds/commit/e8b428eed4551700731fd6e24177ed3e89cbfe1f) | Honor LDAP checking when a refresh token exists |
| [99bd58c](https://github.com/twocanoes/xcreds/commit/99bd58c740b94ce661bd96a05df6bf3d61ff1071) | Preserve aliases without AD; only the relevant login change is backported |

Upstream 6.0 features and its remaining password-reset/migration changes are not
part of this candidate. They need separate review against our synchronous login
callbacks and existing account-mapping UI.

## Deployment verification

Run `scripts/test.sh` and build the universal app. Complete the manual cases in
[TESTING.md](TESTING.md) with the signed candidate before production rollout.
An automated build alone does not validate FileVault, SecurityAgent, MDM-managed
configuration, or access to credentials created by an upstream-signed release.
Existing log files may contain historical credentials; this change prevents new
disclosure and does not erase historical logs.

Existing application ACLs are preserved. macOS may require a one-time Keychain
Access approval for the newly signed app when upgrading from the vendor build.
New credentials receive the math.uio app/extension/login-host access list.

## Local validation — 2026-10-01

- Xcode 26.6 (17F113), macOS 27.0, Apple Silicon: all 17 regression tests passed;
  109 configuration/script files validated.
- Unsigned Release build passed for arm64 and x86_64. The app, login plug-in,
  autofill app/extension, tap extension, and overlay report 5.9.3 (9151).
- Signed archive stopped at `codesign` with `errSecInternalComponent`. Both
  installed Application signing identities failed a separate disposable-binary
  signing check. No new installer was produced, notarized, installed, or published.
- CI has been added but has not yet run on GitHub. Device smoke tests remain open.
