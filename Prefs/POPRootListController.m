// PullOver Pro (rootless) settings.
// Values go through CFPreferences (what the tweak reads) and every change
// posts a Darwin notification so SpringBoard applies it without a respring.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <rootless.h>
#import <dlfcn.h>
#import "../Shared/POShared.h"

@interface POPRootListController : PSListController
@end

@implementation POPRootListController

+ (void)initialize {
    if (self != [POPRootListController class]) return;
    // The favourites picker comes from AltList (a package dependency); load it
    // at runtime so the plist can name its controller class.
    dlopen(ROOT_PATH("/Library/Frameworks/AltList.framework/AltList"), RTLD_NOW);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
        // AltList is only a "Recommends" dependency. If it is missing, hide the
        // favorites picker instead of letting Preferences crash on an unknown
        // ATLApplicationListMultiSelectionController class.
        BOOL hasAltList = NSClassFromString(@"ATLApplicationListMultiSelectionController") != nil;
        if (!hasAltList) {
            NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:loaded.count];
            for (PSSpecifier *specifier in loaded) {
                NSString *detail = [specifier propertyForKey:@"detail"];
                if ([detail isEqualToString:@"ATLApplicationListMultiSelectionController"]) continue;
                [filtered addObject:specifier];
            }
            loaded = filtered;
        }
        _specifiers = loaded;
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PODomain);
    id result = CFBridgingRelease(value);
    return result ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) { [super setPreferenceValue:value specifier:specifier]; return; }
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)PODomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PODomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(POPrefsChangedNotification), NULL, NULL, YES);
}

- (void)openURL:(PSSpecifier *)specifier {
    NSURL *url = [NSURL URLWithString:[specifier propertyForKey:@"url"]];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
