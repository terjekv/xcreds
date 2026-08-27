//
//  LegacyKeychainBridge.m
//  XCreds
//

#import "LegacyKeychainBridge.h"

NSString * const XCredsLegacyACLApplicationsKey = @"applications";
NSString * const XCredsLegacyACLDescriptionKey = @"description";

// There is no access-group replacement for granting an Apple-owned process
// access to a file-keychain item. Suppress deprecation diagnostics only around
// this deliberately retained compatibility boundary.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

id _Nullable XCredsLegacyKeychainForDomain(SecPreferencesDomain domain) {
    SecKeychainRef keychain = NULL;
    OSStatus status = SecKeychainCopyDomainDefault(domain, &keychain);
    if (status != errSecSuccess || keychain == NULL) {
        return nil;
    }
    return CFBridgingRelease(keychain);
}

id _Nullable XCredsLegacyTrustedApplication(const char *path) {
    SecTrustedApplicationRef application = NULL;
    OSStatus status = SecTrustedApplicationCreateFromPath(path, &application);
    if (status != errSecSuccess || application == NULL) {
        return nil;
    }
    return CFBridgingRelease(application);
}

id _Nullable XCredsLegacyAccess(CFStringRef descriptor, CFArrayRef _Nullable trustedApplications) {
    SecAccessRef access = NULL;
    OSStatus status = SecAccessCreate(descriptor, trustedApplications, &access);
    if (status != errSecSuccess || access == NULL) {
        return nil;
    }
    return CFBridgingRelease(access);
}

NSArray * _Nullable XCredsLegacyACLList(SecAccessRef access) {
    CFArrayRef aclList = NULL;
    OSStatus status = SecAccessCopyACLList(access, &aclList);
    if (status != errSecSuccess || aclList == NULL) {
        return nil;
    }
    return CFBridgingRelease(aclList);
}

NSDictionary * _Nullable XCredsLegacyACLContents(
    SecACLRef acl,
    SecKeychainPromptSelector * _Nonnull promptSelector
) {
    CFArrayRef applicationList = NULL;
    CFStringRef description = NULL;
    OSStatus status = SecACLCopyContents(acl, &applicationList, &description, promptSelector);
    if (status != errSecSuccess) {
        if (applicationList != NULL) {
            CFRelease(applicationList);
        }
        if (description != NULL) {
            CFRelease(description);
        }
        return nil;
    }

    NSArray *applications = applicationList == NULL ? @[] : CFBridgingRelease(applicationList);
    NSString *itemDescription = description == NULL ? @"" : CFBridgingRelease(description);
    return @{
        XCredsLegacyACLApplicationsKey: applications,
        XCredsLegacyACLDescriptionKey: itemDescription
    };
}

NSArray<NSString *> * _Nullable XCredsLegacyACLAuthorizations(SecACLRef acl) {
    CFArrayRef authorizations = SecACLCopyAuthorizations(acl);
    if (authorizations == NULL) {
        return nil;
    }
    return CFBridgingRelease(authorizations);
}

OSStatus XCredsLegacyACLSetContents(
    SecACLRef acl,
    CFArrayRef _Nullable applicationList,
    CFStringRef description,
    SecKeychainPromptSelector promptSelector
) {
    return SecACLSetContents(acl, applicationList, description, promptSelector);
}

id _Nullable XCredsLegacyKeychainItemAccess(SecKeychainItemRef item) {
    SecAccessRef access = NULL;
    OSStatus status = SecKeychainItemCopyAccess(item, &access);
    if (status != errSecSuccess || access == NULL) {
        return nil;
    }
    return CFBridgingRelease(access);
}

#pragma clang diagnostic pop
