//
//  LegacyKeychainBridge.h
//  XCreds
//
//  The authorization plug-in is loaded by Apple's authorizationhost process.
//  That process cannot join an XCreds keychain access group, so file-keychain
//  ACLs remain necessary for sharing login credentials with it. Keep the
//  deprecated Security.framework surface isolated here; all ordinary item
//  lookup, update, and deletion uses the modern SecItem API in KeychainUtil.
//

#ifndef LegacyKeychainBridge_h
#define LegacyKeychainBridge_h

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const XCredsLegacyACLApplicationsKey;
FOUNDATION_EXPORT NSString * const XCredsLegacyACLDescriptionKey;

id _Nullable XCredsLegacyKeychainForDomain(SecPreferencesDomain domain);
id _Nullable XCredsLegacyTrustedApplication(const char *path);
id _Nullable XCredsLegacyAccess(CFStringRef descriptor, CFArrayRef _Nullable trustedApplications);
NSArray * _Nullable XCredsLegacyACLList(SecAccessRef access);
NSDictionary * _Nullable XCredsLegacyACLContents(
    SecACLRef acl,
    SecKeychainPromptSelector * _Nonnull promptSelector
);
NSArray<NSString *> * _Nullable XCredsLegacyACLAuthorizations(SecACLRef acl);
OSStatus XCredsLegacyACLSetContents(
    SecACLRef acl,
    CFArrayRef _Nullable applicationList,
    CFStringRef description,
    SecKeychainPromptSelector promptSelector
);
id _Nullable XCredsLegacyKeychainItemAccess(SecKeychainItemRef item);

NS_ASSUME_NONNULL_END

#endif /* LegacyKeychainBridge_h */
