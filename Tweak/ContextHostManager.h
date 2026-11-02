#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ContextInterfaces.h"

// Shows another app's live scene inside SpringBoard.
// iOS 15-16: FBScene -> uiPresentationManager -> _UIScenePresenter.presentationView.
// (The original iOS 10-13 paths, hostManager and FBSceneLayer hosting, are gone.)
@interface ContextHostManager : NSObject
+ (instancetype)sharedInstance;

// Start the app in the background if it has no scene yet (iOS 15-16 way:
// FBSSystemService with the "activate suspended" option).
- (void)launchInBackground:(NSString *)bundleId;
// Bring the app to the front full screen.
- (void)openFullScreen:(NSString *)bundleId;
// The app must already be running (launch it in the background first).
// Returns nil until its scene exists, so callers retry.
- (UIView *)hostViewForBundleID:(NSString *)bundleId;
- (void)stopHostingForBundleID:(NSString *)bundleId;
- (BOOL)isHostViewHosting:(UIView *)hostView;
@end
