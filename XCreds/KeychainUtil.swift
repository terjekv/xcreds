//
//  KeychainUtil.swift
//  NoMAD
//
//  Created by Joel Rennich on 8/7/16.
//  Copyright © 2016 Trusource Labs. All rights reserved.
//

// class to manage all keychain interaction

enum KeychainError: Error {
    case notConnected
    case notLoggedIn
    case noPasswordExpirationTime
    case ldapServerLookup
    case ldapNamingContext
    case ldapServerPasswordExpiration
    case ldapConnectionError
    case userPasswordSetDate
    case userHome
    case noStoredPassword
    case storedPasswordWrong
}


import OSLog
import Foundation
import Security

struct certDates {
    var serial : String
    var expireDate : Date
}
struct PasswordItem{

    var username: String
    var password: String

}
class KeychainUtil {
    // Kept overridable so integration tests can use their own signed executable.
    var trustedPartitions: [String] { ["apple:", "teamid:SC6H7VDLB4"] }

    private func targetKeychain(_ keychain: SecKeychain?) -> SecKeychain? {
        if let keychain { return keychain }
        guard let userKeychain = XCredsLegacyKeychainForDomain(.user) else {
            TCSLogErrorWithMark("Could not open the user's default keychain")
            return nil
        }
        return (userKeychain as! SecKeychain)
    }

    private func passwordQuery(serviceName: String, accountName: String?, keychain: SecKeychain?) -> [String: Any]? {
        // Fail closed if the intended keychain is unavailable. Omitting this
        // restriction would search/update/delete matching items in other keychains.
        guard let keychain = targetKeychain(keychain) else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchSearchList as String: [keychain]
        ]
        if let accountName { query[kSecAttrAccount as String] = accountName }
        return query
    }

    func findPassword(serviceName: String, accountName: String?, keychain: SecKeychain? = nil) -> PasswordItem? {
        guard var query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain) else { return nil }
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { TCSLogErrorWithMark("Keychain lookup failed: \(status)") }
            return nil
        }
        guard let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8), !password.isEmpty else { return nil }
        return PasswordItem(username: account, password: password)
    }

    @available(macOS, deprecated: 10.10)
    func trustedApps() -> [SecTrustedApplication] {
        let paths = [
            "/Applications/XCreds.app",
            "/Applications/XCreds.app/Contents/Resources/XCreds Login Autofill.app/Contents/PlugIns/XCreds Login Password.appex",
            "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.x86_64.xpc",
            "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.arm64.xpc"
        ]
        return paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path),
                  let application = XCredsLegacyTrustedApplication(path) else { return nil }
            return (application as! SecTrustedApplication)
        }
    }

    /// Migrate signing partitions without replacing the item's application ACL.
    /// Preserve existing restrictions and user customizations. A change in the
    /// application's signing identity may need separate macOS approval; this
    /// password-authorized operation updates only the signing partition.
    @available(macOS, deprecated: 10.10)
    private func updateAccess(for item: SecKeychainItem, keychainPassword: String) -> Bool {
        guard let object = XCredsLegacyKeychainItemAccess(item) else { return false }
        let access = object as! SecAccess
        guard let acls = XCredsLegacyACLList(access) as? [SecACL] else { return false }
        var foundPartition = false
        for acl in acls {
            guard let authorizations = XCredsLegacyACLAuthorizations(acl) else { return false }
            guard authorizations.contains("ACLAuthorizationPartitionID") else { continue }
            foundPartition = true
            var prompt = SecKeychainPromptSelector()
            guard let contents = XCredsLegacyACLContents(acl, &prompt),
                  var description = contents[XCredsLegacyACLDescriptionKey] as? String else { return false }
            do {
                guard let data = Data(fromHexEncodedString: description),
                      var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
                    TCSLogErrorWithMark("Could not decode keychain signing partitions")
                    return false
                }
                plist["Partitions"] = trustedPartitions
                guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return false }
                description = data.hexEncodedString()
            }
            let applications = contents[XCredsLegacyACLApplicationsKey] as? NSArray
            let status = XCredsLegacyACLSetContents(acl, applications, description as CFString, prompt)
            guard status == errSecSuccess else {
                TCSLogErrorWithMark("Could not update credential ACL: \(status)")
                return false
            }
        }
        // Older/custom keychains can lack partition ACLs. There is no signing
        // partition to migrate there, and their existing access rules stay intact.
        guard foundPartition else { return true }
        let status = XCredsLegacyKeychainItemSetAccess(item, access, Data(keychainPassword.utf8))
        if status != errSecSuccess { TCSLogErrorWithMark("Could not save credential ACL: \(status)") }
        return status == errSecSuccess
    }

    @available(macOS, deprecated: 10.10)
    func setPassword(serviceName: String, accountName: String, pass: String, keychainPassword: String, keychain: SecKeychain? = nil) -> SecKeychainItem? {
        guard let keychain = targetKeychain(keychain) else { return nil }
        let apps = trustedApps()
        guard !apps.isEmpty,
              let object = XCredsLegacyAccess(accountName as CFString, apps as CFArray) else { return nil }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accountName,
            kSecAttrService as String: serviceName,
            kSecValueData as String: Data(pass.utf8),
            kSecAttrAccess as String: object as! SecAccess,
            kSecUseKeychain as String: keychain,
            kSecReturnRef as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemAdd(attributes as CFDictionary, &result)
        guard status == errSecSuccess, let result else {
            TCSLogErrorWithMark("Could not create credential item: \(status)")
            return nil
        }
        let item = result as! SecKeychainItem
        guard updateAccess(for: item, keychainPassword: keychainPassword) else {
            // Delete only this newly created item, never a pre-existing credential.
            SecItemDelete([kSecValueRef as String: item] as CFDictionary)
            return nil
        }
        return item
    }

    @available(macOS, deprecated: 10.10)
    func updatePassword(serviceName: String, accountName: String, pass: String, keychainPassword: String, keychain: SecKeychain? = nil) -> Bool {
        guard var query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain) else { return false }
        query[kSecReturnRef as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return setPassword(serviceName: serviceName, accountName: accountName, pass: pass,
                               keychainPassword: keychainPassword, keychain: keychain) != nil
        }
        guard status == errSecSuccess, let result else {
            TCSLogErrorWithMark("Could not locate credential to update: \(status)")
            return false
        }
        let item = result as! SecKeychainItem
        // Keep the original password if migrating permissions fails.
        guard updateAccess(for: item, keychainPassword: keychainPassword) else { return false }
        let updateStatus = SecItemUpdate([kSecValueRef as String: item] as CFDictionary,
                                        [kSecValueData as String: Data(pass.utf8)] as CFDictionary)
        if updateStatus != errSecSuccess { TCSLogErrorWithMark("Could not update credential: \(updateStatus)") }
        return updateStatus == errSecSuccess
    }

    func clearPasswords(serviceName: String, keychain: SecKeychain? = nil) -> Bool {
        findAndDelete(serviceName: serviceName, accountName: nil, keychain: keychain)
    }

    func findAndDelete(serviceName: String, accountName: String?, keychain: SecKeychain? = nil) -> Bool {
        guard let query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain) else { return false }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { TCSLogErrorWithMark("Could not delete credential: \(status)") }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
