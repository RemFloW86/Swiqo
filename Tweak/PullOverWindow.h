//
//  PullOverWindow.h
//  PullOverPro
//
//  Created by Will Smillie on 4/8/19.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "PullOverViewController.h"

@interface PullOverWindow : UIWindow

@property (nonatomic, strong) PullOverViewController *controller;

+ (id)sharedWindow;
- (void)applySettings;                 // rebuild the drawer from the current settings
- (void)attachToScene:(UIWindowScene *)scene; // attach to a known SpringBoard scene
- (void)attachToSceneIfNeeded;         // iOS 13+ needs a UIWindowScene before it can show
- (void)updateVisibilityForLockState;  // hide on the Lock Screen, show after unlock

@end
