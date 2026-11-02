//
//  POApplicationHelper.m
//  PullOverPro
//
//  Created by Will Smillie on 4/8/19.
//  Rootless port (iOS 15-16): Jond-ie.
//

#import "POApplicationHelper.h"
#import "ContextInterfaces.h"
#import "POLog.h"

@interface UIImage (POPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@implementation POApplicationHelper

// Recents live on SBMainSwitcherViewController on iOS 15 and moved to
// SBMainSwitcherControllerCoordinator on iOS 16.
+(NSArray *)recentAppLayouts{
    for (NSString *name in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
        Class cls = NSClassFromString(name);
        if (![cls respondsToSelector:@selector(sharedInstance)]) continue;
        id switcher = [cls sharedInstance];
        if ([switcher respondsToSelector:@selector(recentAppLayouts)]) {
            @try {
                NSArray *layouts = [[switcher valueForKey:@"recentAppLayouts"] copy];
                POLog(@"recents from %@: %lu layouts", name, (unsigned long)layouts.count);
                return layouts ?: @[];
            } @catch (NSException *exception) {
                POLog(@"recents from %@ exception: %@", name, exception);
            }
        }
    }
    POLog(@"recents: no switcher class answered");
    return @[];
}

+(NSArray *)recentAppsWithCount:(int)count{
    NSMutableArray *objects = [NSMutableArray new];
    for (id layout in [self recentAppLayouts]) {
        if ((int)objects.count >= count) break;
        NSString *bundleId = nil;
        @try {
            bundleId = [[[layout valueForKey:@"allItems"] valueForKey:@"bundleIdentifier"] firstObject];
        } @catch (NSException *e) {}
        if ([bundleId isKindOfClass:[NSString class]] && ![objects containsObject:bundleId]) {
            [objects addObject:bundleId];
        }
    }
    POLog(@"recent apps: %@", objects);
    return objects;
}

+(UIImage *)imageForBundleId:(NSString *)bundleId{
    if (!bundleId) return nil;

    // format 2 = home screen icon size (60 pt). The private UIKit helper has
    // been stable for years, but iOS 26 is a new major version, so check before
    // calling it and fall back to SpringBoard's icon classes.
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        @try {
            UIImage *image = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:2 scale:[UIScreen mainScreen].scale];
            if (image) return image;
        } @catch (NSException *exception) {
            POLog(@"icon image exception: %@", exception);
        }
    }

    @try {
        id controller = [NSClassFromString(@"SBApplicationController") sharedInstance];
        if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
            id app = [controller applicationWithBundleIdentifier:bundleId];
            Class iconClass = NSClassFromString(@"SBApplicationIcon");
            if (app && iconClass) {
                id icon = [[iconClass alloc] initWithApplication:app];
                if ([icon respondsToSelector:@selector(generateIconImage:)]) {
                    return [icon generateIconImage:2];
                }
            }
        }
    } @catch (NSException *exception) {
        POLog(@"icon fallback exception: %@", exception);
    }

    return nil;
}

static NSString *POTrackedFrontMost;
static BOOL POHasTrackedFrontMost;

void POSetFrontMostBundleId(NSString *bundleId){
    POTrackedFrontMost = [bundleId copy];
    POHasTrackedFrontMost = YES;
}

+(NSString *)frontMostBundleId{
    if (POHasTrackedFrontMost) return POTrackedFrontMost;

    UIApplication *sb = [UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
        @try {
            id app = [sb _accessibilityFrontMostApplication];
            if ([app respondsToSelector:@selector(bundleIdentifier)]) return [app bundleIdentifier];
        } @catch (NSException *exception) {
            POLog(@"frontMost _accessibilityFrontMostApplication exception: %@", exception);
        }
    }

    Class controllerClass = NSClassFromString(@"SBApplicationController");
    if ([controllerClass respondsToSelector:@selector(sharedInstance)]) {
        id controller = [controllerClass sharedInstance];
        for (NSString *selectorName in @[@"frontMostApplication", @"_frontMostApplication"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([controller respondsToSelector:selector]) {
                @try {
                    IMP imp = [controller methodForSelector:selector];
                    id (*call)(id, SEL) = (id (*)(id, SEL))imp;
                    id app = call(controller, selector);
                    if ([app respondsToSelector:@selector(bundleIdentifier)]) return [app bundleIdentifier];
                } @catch (NSException *exception) {
                    POLog(@"frontMost %@ exception: %@", selectorName, exception);
                }
            }
        }
    }

    return nil;
}

static NSDictionary *POCachedSettings;

+(NSDictionary *)defaultSettings{
    return @{
        @"enabled": @YES,
        @"hideInLandscape": @YES,
        @"favorites": @[],
        @"recentAppsCount": @5,
        @"quickswitchScale": @1.75f,
        @"style": @"Recent Apps",
        @"leftHanded": @NO,
        @"darkHandle": @NO,
        @"hideLabels": @NO,
        @"hapticFeedback": @YES,
        @"closeOnHome": @YES,
        @"keyboardAvoiding": @NO,
        @"externalKeyboard": @NO,
        @"autoNub": @NO,
        @"autoNub-time": @5,
    };
}

// Defaults merged with whatever the settings page saved (CFPreferences, so
// cfprefsd's cache is always current; reading the plist file can be stale).
+(NSDictionary *)settings{
    @synchronized (self) {
        if (!POCachedSettings) {
            CFStringRef domain = (__bridge CFStringRef)PODomain;
            CFPreferencesAppSynchronize(domain);
            NSMutableDictionary *merged = [[self defaultSettings] mutableCopy];
            CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (keys) {
                NSDictionary *saved = CFBridgingRelease(CFPreferencesCopyMultiple(keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
                [merged addEntriesFromDictionary:saved];
                CFRelease(keys);
            }
            POCachedSettings = [merged copy];
        }
        return POCachedSettings;
    }
}

+(void)reloadSettings{
    @synchronized (self) { POCachedSettings = nil; }
}

+(NSUserDefaults *)state{
    static NSUserDefaults *state;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ state = [[NSUserDefaults alloc] initWithSuiteName:POStateDomain]; });
    return state;
}

@end
