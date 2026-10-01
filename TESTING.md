# XCreds deployment smoke tests

Use a dedicated test Mac with console access, a working local administrator, and
a retained installer for rollback. Record the package checksum, source commit,
macOS version, architecture, IdP/MDM configuration, and pass/fail for each case.
Never put passwords, tokens, authorization URLs, or recovery keys in test records.

Run `./scripts/test.sh` first. CI also builds an unsigned universal app; these
manual tests require a signed installation. Repeat on each supported deployment
OS/architecture, especially when changing signing identities or macOS versions.

| Case | Expected result |
| --- | --- |
| Fresh cloud login | New account is created; subsequent login uses the same account; menu app refreshes credentials |
| Map an existing account | Advanced account mapping prompts once; correct local password maps the account; cancel and incorrect passwords leave the account unchanged |
| Local/offline login | Login works without network; email-shaped local aliases remain intact with AD unset; local-only mode does not initiate AD authentication |
| AD login | Configured domain/UPN mappings still work; local-only mode remains available according to policy |
| Expired/revoked cloud credentials | Invalid or missing access tokens trigger sign-in rather than reporting successful refresh |
| LDAP password checking | With LDAP checking enabled and a cached refresh token present, change the directory password; the LDAP failure triggers sign-in |
| Password change and keychain | Change the cloud password; local account and login keychain remain usable; a failed keychain permission update is reported and preserves the stored credential |
| Upgrade from upstream signing | Inspect that partition trust is migrated to the math.uio team. Existing application ACLs remain intact and macOS may prompt for one-time approval of the newly signed app. Check the app, autofill extension, and login host can access credentials after approval; fresh credentials receive the current application ACL |
| FileVault and SecureToken | With an MDM-enrolled Mac and stored admin credentials lacking a SecureToken, exercise setup, reboot, and FileVault login; verify token state and the intended account/session |
| Network timeout and reconnection | During SecureToken setup, remain offline past 30 seconds; normal login appears. Reconnect repeatedly; there is no second login attempt or context replacement |
| Logging | With `showDebug` off, debug events are absent. With it on, diagnostics contain no tokens, passwords, authorization codes, or complete authorization URLs; audit/status output omits identity-token contents |
| Installer and rollback | Install over the previous math.uio version, reboot, verify app/plugin/helper versions, then reinstall the retained package and verify login recovery |

To return the test Mac to Apple's login window before removing the app:

```sh
sudo /Applications/XCreds.app/Contents/Resources/xcreds_login.sh -r
```

This changes system login authorization; run it only on the test machine. Retain
the authorization backup at `/Library/Application Support/xcreds/rights.bak`.

## Result record

- Package/checksum:
- Commit (clean build):
- Signing team/notarization:
- macOS/architecture:
- IdP/MDM configuration (no secrets):
- Tester/date:
- Cases passed:
- Failures and reproduction steps:
- Rollback verified:

No manual deployment results are implied by the automated test suite.
