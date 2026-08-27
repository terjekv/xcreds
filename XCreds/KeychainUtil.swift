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

//    var myErr: OSStatus
//    let serviceName = "xcreds"

//    var myKeychainItem: SecKeychainItem?

//    init() {
//        myErr = 0
//    }

  

    private func passwordQuery(
        serviceName: String,
        accountName: String?,
        keychain: SecKeychain? = nil
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        if let accountName {
            query[kSecAttrAccount as String] = accountName
        }
        if let keychain {
            query[kSecUseKeychain as String] = keychain
        }
        return query
    }

    // Find an existing generic password with the supported SecItem API.
    func findPassword(serviceName: String, accountName: String?, keychain: SecKeychain? = nil) -> PasswordItem? {
        TCSLogWithMark("Finding \(serviceName) in keychain")
        TCSLogWithMark("find password for account:\(String(describing: accountName)) service:\(serviceName)")

        var query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                TCSLogErrorWithMark("Error finding \(serviceName) in keychain: \(status)")
            }
            return nil
        }

        guard let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              let passwordData = item[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8),
              !password.isEmpty else {
            TCSLogErrorWithMark("Could not decode \(serviceName) from the keychain")
            return nil
        }

        TCSLogWithMark("\(serviceName) found in keychain")
        return PasswordItem(username: account, password: password)
    }

    func trustedApps() -> [SecTrustedApplication] {
        let paths = [
            "/Applications/XCreds.app",
            "/Applications/XCreds.app/Contents/Resources/XCreds Login Autofill.app/Contents/PlugIns/XCreds Login Password.appex",
            "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.x86_64.xpc",
            "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.arm64.xpc"
        ]
        var secApps = [SecTrustedApplication]()

        for path in paths where FileManager.default.fileExists(atPath: path) {
            guard let application = XCredsLegacyTrustedApplication(path) else {
                TCSLogWithMark("error appending trust for \(path)")
                continue
            }
            secApps.append(application as! SecTrustedApplication)
        }
        return secApps
    }

    // set the password

    func setPassword(serviceName:String, accountName: String, pass: String, keychainPassword:String, keychain:SecKeychain?=nil) -> SecKeychainItem? {
        
        
        let account = accountName
        let passwordData = pass.data(using: String.Encoding.utf8)!
        var keychainItem:CFTypeRef?
        var keychainToUse:SecKeychain
        
        TCSLogWithMark("Setting password for account:\(accountName) service:(serviceName)")

        
        if let keychain = keychain {
            os_log("using provided keychain")
            keychainToUse=keychain
        }
        else {
            os_log("using user keychain")

            guard let userKeychain = XCredsLegacyKeychainForDomain(SecPreferencesDomain.user) else {
                os_log("error getting user keychain")
                return nil
            }
            keychainToUse = userKeychain as! SecKeychain
        }


        TCSLogWithMark("Creating ACL")
        //create the default ACLs as SecAccess so we can modify them
        guard let secAccessObject = XCredsLegacyAccess(accountName as CFString, nil) else {
            TCSLogWithMark("Error setting ACL")
            return nil
        }
        let secAccess = secAccessObject as! SecAccess
        
        //In order to not get prompted, the app that are allowed to use the
        // ACLAuthorizationDecrypt operation
        //must be included when the ACLs are created.
        //convert the ACLs to a list and then go through them
        //and modify ACLAuthorizationDecrypt. ACLAuthorizationDecrypt is the right
        //that is needed to give apps access to a password
        //adding the app path is not enough; the team id needs to
        //be added to the partition ACL, but we can't create that ACL.
        //We have create the ACLs and then the partition ACL gets added.
        //We then loop over, find it, and modify it.
        
        //convert opaque secAccess to an array
        guard let initialACLs = XCredsLegacyACLList(secAccess) as? [SecACL] else {
            TCSLogWithMark("Error reading newly created ACL")
            return nil
        }
        //get a list of the trusted apps to share the password
        let secApps = trustedApps()
         
        //loop over them looking for ACLAuthorizationDecrypt
        for acl in initialACLs {
            var prompt = SecKeychainPromptSelector()
            guard XCredsLegacyACLContents(acl, &prompt) != nil else {
                continue
            }
            let authArray = XCredsLegacyACLAuthorizations(acl)
            
            //set the apps that are allowed to have access to the password item
            if authArray?.contains("ACLAuthorizationDecrypt") == true {
                
                TCSLogWithMark("Found ACLAuthorizationDecrypt.")
                XCredsLegacyACLSetContents(acl, secApps as CFArray, "" as CFString, prompt)
                continue
            }
        }
                
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecAttrService as String: serviceName,
                                    kSecValueData as String: passwordData,
                                    kSecAttrAccess as String: secAccess as SecAccess,
                                     kSecUseKeychain as String:keychainToUse as Any,
                                    kSecReturnRef as String: true
        ]
        
        TCSLogWithMark("Calling SecItemAdd, returning new keychain item (generic password)")
        let res = SecItemAdd(attributes as CFDictionary, &keychainItem)
        if  res != OSStatus(errSecSuccess)  {
            TCSLogWithMark("Error SecItemAdd: \(res) ")
            return nil
        }
        
        let secKeychainItem = keychainItem as! SecKeychainItem
        guard let accessControlListObject = XCredsLegacyKeychainItemAccess(secKeychainItem) else {
            TCSLogWithMark("invalid accessControlList")
            return nil
        }
        let accessControlList = accessControlListObject as! SecAccess
        //turn the opaque accessControlList to an array of secACLs
        //so we can iterate over them
        guard let itemACLs = XCredsLegacyACLList(accessControlList) as? [SecACL] else {
            TCSLogWithMark("Error reading item ACL")
            return nil
        }

        //iterate over the acls in the array
        //when the acl in the array changes, it changes the items
        //in the accessControlList but doesn't change the
        //access control list in the secKeychainItem until
        //SecKeychainItemSetAccessWithPassword is called
        
        for acl in itemACLs {
            
            //each ACL has one or more auth operations
            //a list of apps that have access to those operations
            //and a prompt selector. the prompt selector is the default
            //since macOS seems to want to prompt on everything regardless
            
            var prompt = SecKeychainPromptSelector()
            guard let contents = XCredsLegacyACLContents(acl, &prompt) else {
                continue
            }
            
            //For this ACL, get the operations that it covers
            
            let authArray = XCredsLegacyACLAuthorizations(acl)
            
            //see if it is ACLAuthorizationPartitionID, which is the
            //ACL that allows access by team id.
            if authArray?.contains("ACLAuthorizationPartitionID") == true {
                TCSLogWithMark("Found ACLAuthorizationPartitionID.")
                
                // pull in the description that is a plist
                guard let description = contents[XCredsLegacyACLDescriptionKey] as? String,
                      let rawData = Data(fromHexEncodedString: description) else {
                    TCSLogWithMark("Could not decode ACLAuthorizationPartitionID")
                    continue
                }
                var format: PropertyListSerialization.PropertyListFormat = .xml
                
                var propertyListObject = [ String: [String]]()
                
                do {
                    propertyListObject = try PropertyListSerialization.propertyList(from: rawData, options: [], format: &format) as! [ String: [String]]
                } catch {
                    TCSLogWithMark("No teamid in ACLAuthorizationPartitionID.")
                }
                let teamIds = [ "apple:", "teamid:SC6H7VDLB4" ]
                
                propertyListObject["Partitions"] = teamIds
                
                // now serialize it back into a plist
                
                guard let xmlObject = try? PropertyListSerialization.data(fromPropertyList: propertyListObject as Any, format: format, options: 0) else {
                    TCSLogWithMark("Could not encode ACLAuthorizationPartitionID")
                    continue
                }
                
                // now that all ACLs has been adjusted, we can update the item
                
                let err = XCredsLegacyACLSetContents(acl, secApps as CFArray, xmlObject.hexEncodedString() as CFString, prompt)
                
                if err == 0 {
                    TCSLogWithMark("SecACLSetContents success")
                }
                else {
                    TCSLogWithMark("error SecACLSetContents")
                }
                

            }
            
        }
        
        
        //we really should be using SecKeychainItemSetAccess but it always errors if you change
        //the partition ID.
        
        let passwordBytes = keychainPassword.utf8CString
        let err = passwordBytes.withUnsafeBufferPointer { buffer in
            SecKeychainItemSetAccessWithPassword(
                secKeychainItem,
                accessControlList,
                UInt32(max(0, buffer.count - 1)),
                buffer.baseAddress
            )
        }

        if err == 0 {
            TCSLogWithMark("SecKeychainItemSetAccessWithPassword success")
        }
        else {
            TCSLogWithMark("error SecKeychainItemSetAccessWithPassword: \(err)")
        }

        return secKeychainItem


    }

    func updatePassword(serviceName: String, accountName: String, pass: String, keychainPassword: String, keychain: SecKeychain? = nil) -> Bool {
        guard let passwordData = pass.data(using: .utf8) else {
            TCSLogErrorWithMark("Could not encode password for \(accountName)")
            return false
        }

        let query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain)
        let updates = [kSecValueData as String: passwordData]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)

        if status == errSecSuccess {
            TCSLogWithMark("updated password for \(accountName) \(serviceName)")
            return true
        }
        guard status == errSecItemNotFound else {
            TCSLogErrorWithMark("updating password failed for \(accountName): \(status)")
            return false
        }

        TCSLogWithMark("setting new password for \(accountName) \(serviceName)")
        guard setPassword(
            serviceName: serviceName,
            accountName: accountName,
            pass: pass,
            keychainPassword: keychainPassword,
            keychain: keychain
        ) != nil else {
            TCSLogErrorWithMark("setting new password FAILURE: accountname:\(accountName)")
            return false
        }
        TCSLogWithMark("setting new password success")
        return true
    }

    func clearPasswords(serviceName:String,keychain:SecKeychain?=nil) -> Bool {
        findAndDelete(serviceName: serviceName, accountName: nil, keychain: keychain)
    }

    // Convenience function for deleting one account or all accounts for a service.
    func findAndDelete(serviceName: String, accountName: String?, keychain:SecKeychain?=nil) -> Bool {
        let query = passwordQuery(serviceName: serviceName, accountName: accountName, keychain: keychain)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }
        TCSLogErrorWithMark("deleting password failed for \(serviceName): \(status)")
        return false
    }
}
