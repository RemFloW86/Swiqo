// PullOver Pro (rootless) — SpringBoard hooks.
// Original by c1d3r (Will Smillie), GPL-3.0. iOS 15-27 rootless and RootHide
// support: Jond-ie. iOS 26 fixes: scene attach retry, launch visibility and
// safer private API use.
//
// Changes from the original: the licence check, the What's New sheet and the
// activation alert are gone, and the window is attached to SpringBoard's scene.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <unistd.h>

#import "headers.h"
#import "PullOverWindow.h"
#import "POApplicationHelper.h"
#import "POLog.h"

static PullOverWindow *window;

@interface SpringBoard (PullOver)
- (void)addActiveOrientationObserver:(id)observer;
@end

// Hides the drawer in landscape when "Hide in Landscape" is on.
@interface POOrientationObserver : NSObject
+ (instancetype)shared;
@end

@implementation POOrientationObserver
+ (instancetype)shared {
    static POOrientationObserver *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}
- (void)activeInterfaceOrientationWillChangeToOrientation:(long long)orientation {}
- (void)activeInterfaceOrientationDidChangeToOrientation:(long long)orientation willAnimateWithDuration:(double)duration fromOrientation:(long long)from {
    if (!window || ![[POApplicationHelper settings][@"hideInLandscape"] boolValue]) return;
    BOOL portrait = (orientation == UIInterfaceOrientationPortrait);
    if (!portrait && [window.controller isOpened]) {
        [window.controller endHosting];
        [window.controller close];
    }
    [UIView animateWithDuration:0.2 animations:^{
        window.rootViewController.view.alpha = portrait ? 1 : 0;
    }];
}
@end

// Settings changed in the settings page: re-read them and rebuild the drawer
// so every option applies without a respring.
static void POPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        POLog(@"prefs changed notification");
        [POApplicationHelper reloadSettings];
        BOOL enabled = [[POApplicationHelper settings][@"enabled"] boolValue];
        if (enabled && !window) {
            window = [PullOverWindow sharedWindow];
            [window attachToSceneIfNeeded];
            [window makeKeyAndVisible];
        }
        [window applySettings];
        [window updateVisibilityForLockState];
    });
}

// "Close When Going Home" (on by default): the Home button, the home swipe and anything else
// that lands on the Home Screen tucks the pulled-over app away.
static BOOL POCloseOnHome(void) {
    return [[POApplicationHelper settings][@"closeOnHome"] boolValue];
}

// Commands from other tweaks (POShared.h). Ignored while the drawer is hidden:
// switched off, on the Lock Screen, or in landscape with "Hide in Landscape" on.
static void POCommand(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *command = [(__bridge NSString *)name lastPathComponent];
    dispatch_async(dispatch_get_main_queue(), ^{
        PullOverViewController *controller = window.controller;
        if (!controller || window.hidden || window.alpha == 0 || controller.view.alpha == 0) return;
        BOOL open = [command isEqualToString:@"open"] || ([command isEqualToString:@"toggle"] && !controller.isOpened);
        if (open) {
            if (controller.isOpened) return;
            if (controller.handle.isNubbed) controller.handle.isNubbed = NO;
            [controller open];
        } else if (controller.isOpened) {
            [controller close];
        }
    });
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(UIApplication *)arg1{
    %orig;

    POLog(@"SpringBoard applicationDidFinishLaunching");

    if (![[POApplicationHelper settings][@"enabled"] boolValue]) {
        POLog(@"tweak disabled in settings");
        return;
    }

    window = [PullOverWindow sharedWindow];
    [window attachToSceneIfNeeded];
    [window makeKeyAndVisible];
    [window applySettings];
    [window updateVisibilityForLockState];

    POLog(@"window=%@ scene=%@ alpha=%f hidden=%d", window, window.windowScene, window.alpha, window.hidden);

    // Orientation: SpringBoard's own observer list instead of hooking
    // noteInterfaceOrientationChanged:, which iOS 27 dropped.
    if ([self respondsToSelector:@selector(addActiveOrientationObserver:)]) {
        [self addActiveOrientationObserver:[POOrientationObserver shared]];
    }
}

// Remember the front app (nil = Home Screen).
-(void)frontDisplayDidChange:(id)display{
    %orig;

    @try {
        NSString *front = nil;
        if ([display respondsToSelector:@selector(bundleIdentifier)]) {
            front = [display bundleIdentifier];
        } else if ([display respondsToSelector:@selector(clientProcess)]) {
            id process = [display clientProcess];
            if ([process respondsToSelector:@selector(bundleIdentifier)]) front = [process bundleIdentifier];
        }
        POSetFrontMostBundleId(front);
        POLog(@"front display -> %@", front ?: @"(home)");

        // Back on the Home Screen. The transition hook below already closed the drawer as the animation
        // began; this is the fallback, and re-attaches the app when the drawer stays open.
        if (!front && [window.controller isOpened]) {
            if (POCloseOnHome()) {
                dispatch_async(dispatch_get_main_queue(), ^{ [window.controller close]; });
            } else {
                // Staying open: going home sends every app to the background, the pulled-over one too
                // (it shows black). Attach it again once the Home Screen has settled.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PullOverViewController *c = window.controller;
                    if (![c isOpened]) return;
                    [c endHosting];
                    c.isOpened = YES;
                });
            }
        }
    } @catch (NSException *exception) {
        POLog(@"frontDisplayDidChange exception: %@", exception);
    }
}
%end

// SpringBoard's home screen controller is a reliable point at which the main
// window scene exists. iOS 13+ refuses to display a window without a scene, and
// on iOS 26 the scene is not always ready in applicationDidFinishLaunching:.
%hook SBHomeScreenViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!window) {
        window = [PullOverWindow sharedWindow];
        [window makeKeyAndVisible];
        [window applySettings];
    }
    // The home screen controller lives in SpringBoard's real main window, so
    // its scene is the correct one even when connectedScenes has several.
    if (self.view.window.windowScene) {
        [window attachToScene:self.view.window.windowScene];
    }
    [window attachToSceneIfNeeded];
    [window updateVisibilityForLockState];
    POLog(@"home screen appeared; scene=%@ alpha=%f hidden=%d", window.windowScene, window.alpha, window.hidden);
}
%end

// Closes the drawer as the trip home STARTS (swipe released, Home pressed, an action), so it slides away
// with iOS's own animation. unlockedEnvironmentMode 1 = Home Screen.
@protocol POLayoutState <NSObject>
- (long long)unlockedEnvironmentMode;
@end
@protocol POLayoutTransitionContext <NSObject>
- (id<POLayoutState>)toLayoutState;
@end
%hook SBFluidSwitcherViewController
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig;
    @try {
        if (![window.controller isOpened] || !POCloseOnHome()) return;
        id<POLayoutState> to = [context respondsToSelector:@selector(toLayoutState)] ? [(id<POLayoutTransitionContext>)context toLayoutState] : nil;
        if ([to respondsToSelector:@selector(unlockedEnvironmentMode)] && [to unlockedEnvironmentMode] == 1) {
            [window.controller close];
        }
    } @catch (NSException *exception) {
        POLog(@"layout transition exception: %@", exception);
    }
}
%end

// Hide the drawer while the device is locked and show it again after unlock.
%hook SBLockStateAggregator
-(void)_updateLockState{
    %orig;
    @try {
        if (!window) return;
        unsigned long long state = [self respondsToSelector:@selector(lockState)] ? [self lockState] : 0;
        POLog(@"lock state -> %llu", state);
        [window updateVisibilityForLockState];
    } @catch (NSException *exception) {
        POLog(@"_updateLockState exception: %@", exception);
    }
}
%end

%ctor {
    POLog(@"PullOverPro loaded (ctor) pid=%d", getpid());
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, POPrefsChanged,
                                    CFSTR(POPrefsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    for (NSString *name in @[@POOpenNotification, @POCloseNotification, @POToggleNotification]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, POCommand,
                                        (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }

#if DEBUG
    // Diagnostic beacon: a double vibration ~1.5 s after the dylib loads proves
    // the injection worked even when SpringBoard's sandbox blocks the log file.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        });
    });

    // Force the window up once SpringBoard has a scene, whether or not the
    // applicationDidFinishLaunching: / home screen hooks fired.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [POApplicationHelper reloadSettings];
        BOOL enabled = [[POApplicationHelper settings][@"enabled"] boolValue];
        UIApplication *app = [UIApplication sharedApplication];
        POLog(@"DIAG scenes=%lu enabled=%d homeClass=%d", (unsigned long)app.connectedScenes.count, enabled,
              NSClassFromString(@"SBHomeScreenViewController") != nil);
        if (!enabled) return;

        if (!window) window = [PullOverWindow sharedWindow];
        [window attachToSceneIfNeeded];
        [window makeKeyAndVisible];
        [window updateVisibilityForLockState];
        [window.controller.view setNeedsLayout];
        [window.controller.view layoutIfNeeded];

        POLog(@"DIAG window=%@ scene=%@ level=%f alpha=%f hidden=%d bounds=%@",
              window, window.windowScene, window.windowLevel, window.alpha, window.hidden,
              NSStringFromCGRect(window.bounds));
        POLog(@"DIAG controller=%@ handle=%@ frame=%@ hidden=%d alpha=%f",
              window.controller, window.controller.handle,
              NSStringFromCGRect(window.controller.handle.frame),
              window.controller.handle.hidden, window.controller.handle.alpha);
    });
#endif
}
