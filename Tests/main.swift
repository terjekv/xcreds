import Foundation
import Security
import XCTest

let testRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XCREDS_TEST_ROOT"]!)
try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: testRoot) }
UserDefaults.standard.setVolatileDomain([
    "showDebug": false, "LogFolderPath": testRoot.path, "LogFileName": "test.log"
], forName: UserDefaults.argumentDomain)

final class AuthenticationTests: XCTestCase {
    @objc func testLDAPTakesPrecedenceOverRefreshAndROPG() {
        for refresh in [false, true] {
            for ropg in [false, true] {
                XCTAssertEqual(AuthenticationPolicy.passwordCheck(useLDAP: true, useROPG: ropg, hasRefreshToken: refresh), .ldap)
            }
        }
    }

    @objc func testOIDCRequiresRefreshOrROPG() {
        XCTAssertEqual(AuthenticationPolicy.passwordCheck(useLDAP: false, useROPG: false, hasRefreshToken: false), .none)
        XCTAssertEqual(AuthenticationPolicy.passwordCheck(useLDAP: false, useROPG: true, hasRefreshToken: false), .oidc)
        XCTAssertEqual(AuthenticationPolicy.passwordCheck(useLDAP: false, useROPG: false, hasRefreshToken: true), .oidc)
    }

    @objc func testMissingOrEmptyAccessIsRejected() {
        for token: String? in [nil, "", " \n\t"] { XCTAssertFalse(AuthenticationPolicy.hasAccessToken(token)) }
        XCTAssertTrue(AuthenticationPolicy.hasAccessToken("access-token"))
    }

    @objc func testLocalAliasIsNotParsedAsAD() {
        for domain: String? in [nil, "", "  "] {
            XCTAssertFalse(AuthenticationPolicy.shouldParseADUsername(localOnly: false, domain: domain))
        }
        XCTAssertFalse(AuthenticationPolicy.shouldParseADUsername(localOnly: true, domain: "example.org"))
        XCTAssertTrue(AuthenticationPolicy.shouldParseADUsername(localOnly: false, domain: "example.org"))
    }

    @objc func testErrorsDoNotDiscloseAuthenticationResponse() {
        let error = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [
            NSLocalizedDescriptionKey: "https://idp.invalid/?code=secret-authorization-code",
            "access_token": "secret-access-token"
        ])
        XCTAssertEqual(AuthenticationPolicy.errorSummary(error), "NSURLErrorDomain (-1001)")
    }

    @objc func testAuditDropsTokenAndRetainsLoginHistory() throws {
        let audit = XCredsAudit()
        audit.configFileURL = testRoot.appendingPathComponent("audit.plist")
        var record = XCredsAudit.AuditRecord()
        record.identityToken = "sensitive-token-claims"
        record.lastSuccessfulLoginUser = "fixture-user"
        audit.saveAuditRecord(record)
        audit.tokensUpdated(idToken: "raw-identity-token")
        let contents = try String(contentsOf: audit.configFileURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("sensitive-token"))
        XCTAssertFalse(contents.contains("raw-identity-token"))
        XCTAssertNil(audit.currentAuditRecord().identityToken)
        XCTAssertEqual(audit.currentAuditRecord().lastSuccessfulLoginUser, "fixture-user")
        XCTAssertNotNil(audit.currentAuditRecord().identityTokenUpdateDate)
    }

    @objc func testOldAuditTokensAreNotExposed() throws {
        let audit = XCredsAudit()
        audit.configFileURL = testRoot.appendingPathComponent("legacy-audit.plist")
        var record = XCredsAudit.AuditRecord()
        record.identityToken = "old-sensitive-token"
        try PropertyListEncoder().encode(record).write(to: audit.configFileURL)
        XCTAssertNil(audit.currentAuditRecord().identityToken)
        XCTAssertNil(audit.auditRecord(path: audit.configFileURL.path)?.identityToken)
        XCTAssertNil(audit.auditRecordDictionary(record)["identityToken"])
    }

    @objc func testConnectivityCompletesOnceAndCancelsTimeout() {
        let center = NotificationCenter()
        let wait = LoginConnectivityWait(center: center)
        let name = Notification.Name("test-connectivity")
        var results = [Bool]()
        wait.start(notification: name, timeout: 0.01) { results.append($0) }
        center.post(name: name, object: nil)
        center.post(name: name, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(results, [true])
    }

    @objc func testTimeoutRejectsLateConnectivity() {
        let center = NotificationCenter()
        let wait = LoginConnectivityWait(center: center)
        let name = Notification.Name("test-connectivity")
        var results = [Bool]()
        wait.start(notification: name, timeout: 0.01) { results.append($0) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        center.post(name: name, object: nil)
        XCTAssertEqual(results, [false])
    }

    @objc func testCancellingWaitRemovesCallback() {
        let center = NotificationCenter()
        let wait = LoginConnectivityWait(center: center)
        let name = Notification.Name("test-connectivity")
        wait.start(notification: name, timeout: 0.01) { _ in XCTFail("Cancelled callback ran") }
        wait.cancel()
        center.post(name: name, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    }

    @objc func testStartingNewWaitCancelsPreviousTimeoutAndObserver() {
        let center = NotificationCenter()
        let wait = LoginConnectivityWait(center: center)
        wait.start(notification: .init("old"), timeout: 0.01) { _ in XCTFail("Old callback ran") }
        var results = [Bool]()
        wait.start(notification: .init("new"), timeout: 1) { results.append($0) }
        center.post(name: .init("old"), object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(results.isEmpty)
        center.post(name: .init("new"), object: nil)
        XCTAssertEqual(results, [true])
    }

    @objc func testDebugPreferenceAndSuppressionGateLogOutput() throws {
        let logger = TCSUnifiedLogger.shared()
        let url = try XCTUnwrap(logger.logFileURL)
        TCSLog("debug-disabled-marker")
        TCSLogError("error-marker")
        var data = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(data.contains("debug-disabled-marker"))
        XCTAssertTrue(data.contains("error-marker"))
        var preferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        preferences["showDebug"] = true
        UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
        defer {
            preferences["showDebug"] = false
            UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
            logger.suppressDebug = false
        }
        TCSLog("debug-enabled-marker")
        logger.suppressDebug = true
        TCSLog("debug-suppressed-marker")
        data = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(data.contains("debug-enabled-marker"))
        XCTAssertFalse(data.contains("debug-suppressed-marker"))
    }
}

@available(macOS, deprecated: 10.10)
final class TestKeychainUtil: KeychainUtil {
    override func trustedApps() -> [SecTrustedApplication] {
        [XCredsLegacyTrustedApplication(CommandLine.arguments[0]) as! SecTrustedApplication]
    }

    override var trustedPartitions: [String] {
        var code: SecStaticCode?
        precondition(SecStaticCodeCreateWithPath(URL(fileURLWithPath: CommandLine.arguments[0]) as CFURL, [], &code) == errSecSuccess)
        var info: CFDictionary?
        precondition(SecCodeCopySigningInformation(code!, [], &info) == errSecSuccess)
        let hash = (info! as NSDictionary)[kSecCodeInfoUnique] as! Data
        return ["cdhash:" + hash.hexEncodedString()]
    }
}

@available(macOS, deprecated: 10.10)
final class KeychainTests: XCTestCase {
    private let password = "temporary-ø🔑-test-keychain-password"
    private var keychains = [SecKeychain]()
    private var originalSearchList: CFArray?
    private let utility = TestKeychainUtil()
    private let service = "xcreds-regression-" + UUID().uuidString

    override func setUp() {
        XCTAssertEqual(SecKeychainCopySearchList(&originalSearchList), errSecSuccess)
    }

    private func makeKeychain() throws -> SecKeychain {
        // macOS recognizes a /Library/Keychains path component when selecting
        // the partition-aware format. Keep that hierarchy inside our temp folder.
        let directory = testRoot.appendingPathComponent("Library/Keychains")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(UUID().uuidString + ".keychain").path
        var keychain: SecKeychain?
        // These are temporary files only. Never change the default keychain/search list.
        let status = password.withCString { SecKeychainCreate(path, UInt32(password.utf8.count), $0, false, nil, &keychain) }
        XCTAssertEqual(status, errSecSuccess)
        let created = try XCTUnwrap(keychain)
        keychains.append(created)
        XCTAssertEqual(SecKeychainLock(created), errSecSuccess)
        XCTAssertEqual(password.withCString { SecKeychainUnlock(created, UInt32(password.utf8.count), $0, true) }, errSecSuccess)
        return created
    }

    override func tearDown() {
        for keychain in keychains { XCTAssertEqual(SecKeychainDelete(keychain), errSecSuccess) }
        keychains.removeAll()
        var searchList: CFArray?
        XCTAssertEqual(SecKeychainCopySearchList(&searchList), errSecSuccess)
        XCTAssertEqual(searchList as NSArray?, originalSearchList as NSArray?)
    }

    @objc func testReadUpdateAndDeleteStayInRequestedKeychain() throws {
        let first = try makeKeychain()
        let second = try makeKeychain()
        for (keychain, value) in [(first, "first"), (second, "second")] {
            XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: "account", pass: value, keychainPassword: password, keychain: keychain))
        }
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: first)?.password, "first")
        XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: "account", pass: "updated-ø🔑", keychainPassword: password, keychain: first))
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: first)?.password, "updated-ø🔑")
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: second)?.password, "second")
        XCTAssertTrue(utility.clearPasswords(serviceName: service, keychain: first))
        XCTAssertNil(utility.findPassword(serviceName: service, accountName: "account", keychain: first))
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: second)?.password, "second")
        XCTAssertTrue(utility.clearPasswords(serviceName: service, keychain: first))
    }

    @objc func testWrongKeychainPasswordDoesNotReplaceExistingCredential() throws {
        let keychain = try makeKeychain()
        XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: "account", pass: "original", keychainPassword: password, keychain: keychain))
        XCTAssertFalse(utility.updatePassword(serviceName: service, accountName: "account", pass: "replacement", keychainPassword: "incorrect", keychain: keychain))
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: keychain)?.password, "original")
    }

    @objc func testFailedCreationRemovesOnlyNewItem() throws {
        let keychain = try makeKeychain()
        XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: "existing", pass: "original", keychainPassword: password, keychain: keychain))
        XCTAssertNil(utility.setPassword(serviceName: service, accountName: "new", pass: "new", keychainPassword: "incorrect", keychain: keychain))
        XCTAssertNil(utility.findPassword(serviceName: service, accountName: "new", keychain: keychain))
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "existing", keychain: keychain)?.password, "original")
    }

    @objc func testDeletingOneAccountPreservesOthers() throws {
        let keychain = try makeKeychain()
        for account in ["first", "second"] {
            XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: account, pass: account, keychainPassword: password, keychain: keychain))
        }
        XCTAssertTrue(utility.findAndDelete(serviceName: service, accountName: "first", keychain: keychain))
        XCTAssertNil(utility.findPassword(serviceName: service, accountName: "first", keychain: keychain))
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "second", keychain: keychain)?.password, "second")
    }

    @objc func testExistingItemPermissionsAreMigrated() throws {
        let keychain = try makeKeychain()
        let originalApps = utility.trustedApps() + [XCredsLegacyTrustedApplication("/usr/bin/security") as! SecTrustedApplication]
        let access = XCredsLegacyAccess("old item" as CFString, originalApps as CFArray) as! SecAccess
        var result: CFTypeRef?
        XCTAssertEqual(SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "account",
            kSecValueData as String: Data("old".utf8), kSecUseKeychain as String: keychain,
            kSecAttrAccess as String: access, kSecReturnRef as String: true
        ] as CFDictionary, &result), errSecSuccess)
        let item = try XCTUnwrap(result) as! SecKeychainItem
        // Seed an upstream-era signing partition on the actual macOS item.
        let oldAccess = XCredsLegacyKeychainItemAccess(item) as! SecAccess
        let oldACLs = XCredsLegacyACLList(oldAccess) as! [SecACL]
        let partitionACL = try XCTUnwrap(oldACLs.first {
            XCredsLegacyACLAuthorizations($0)?.contains("ACLAuthorizationPartitionID") == true
        })
        let partitionData = try PropertyListSerialization.data(fromPropertyList: [
            "Partitions": utility.trustedPartitions + ["teamid:UXP6YEHSPW"]
        ], format: .xml, options: 0)
        var prompt = SecKeychainPromptSelector()
        _ = XCredsLegacyACLContents(partitionACL, &prompt)
        XCTAssertEqual(XCredsLegacyACLSetContents(partitionACL, utility.trustedApps() as CFArray,
            partitionData.hexEncodedString() as CFString, prompt), errSecSuccess)
        XCTAssertEqual(XCredsLegacyKeychainItemSetAccess(item, oldAccess, Data(password.utf8)), errSecSuccess)
        XCTAssertTrue(utility.updatePassword(serviceName: service, accountName: "account", pass: "new", keychainPassword: password, keychain: keychain))
        let migrated = XCredsLegacyKeychainItemAccess(item) as! SecAccess
        let acls = XCredsLegacyACLList(migrated) as! [SecACL]
        let decryptACL = try XCTUnwrap(acls.first {
            XCredsLegacyACLAuthorizations($0)?.contains("ACLAuthorizationDecrypt") == true
        })
        let decryptContents = try XCTUnwrap(XCredsLegacyACLContents(decryptACL, &prompt))
        XCTAssertEqual((decryptContents[XCredsLegacyACLApplicationsKey] as? NSArray)?.count, originalApps.count)
        XCTAssertEqual(utility.findPassword(serviceName: service, accountName: "account", keychain: keychain)?.password, "new")
        var found = false
        for acl in acls where XCredsLegacyACLAuthorizations(acl)?.contains("ACLAuthorizationPartitionID") == true {
            var prompt = SecKeychainPromptSelector()
            let contents = try XCTUnwrap(XCredsLegacyACLContents(acl, &prompt))
            let description = try XCTUnwrap(contents[XCredsLegacyACLDescriptionKey] as? String)
            let data = try XCTUnwrap(Data(fromHexEncodedString: description))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            XCTAssertEqual(plist["Partitions"] as? [String], utility.trustedPartitions)
            found = true
        }
        XCTAssertTrue(found)
    }
}

let suite = XCTestSuite(name: "XCreds regression tests")
suite.addTest(AuthenticationTests.defaultTestSuite)
suite.addTest(KeychainTests.defaultTestSuite)
suite.run()
let run = suite.testRun!
print("Executed \(run.executionCount) tests; failures: \(run.totalFailureCount)")
try? FileManager.default.removeItem(at: testRoot)
exit(run.executionCount > 0 && run.hasSucceeded ? 0 : 1)
