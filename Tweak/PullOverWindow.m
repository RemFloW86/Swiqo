//
//  PullOverWindow.m
//  PullOverPro
//
//  Created by Will Smillie on 4/8/19.
//

#import "PullOverWindow.h"
#import "POApplicationHelper.h"
#import "POLog.h"

@interface PullOverWindow () {
    NSUInteger _sceneAttachAttempts;
    BOOL _lockRecheckScheduled;
}
@end

@implementation PullOverWindow
@synthesize controller;

+ (id)sharedWindow {
    static PullOverWindow *window = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        window = [[self alloc] init];
    });

    return window;
}

- (id)init{
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if(self){
        self.windowLevel = UIWindowLevelAlert-1;
        [self setHidden:NO];
        self.alpha = 1;
        self.rootViewController = controller = [[PullOverViewController alloc] init];
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        [self attachToSceneIfNeeded];
    }
    return self;
}

// iOS 13+ refuses to display a window that is not attached to a UIWindowScene.
// At applicationDidFinishLaunching: the scene may not exist yet, so retry until
// SpringBoard has one. This is the main reason the handle stayed invisible on
// iOS 17/26 even though the tweak was loaded.
- (void)attachToScene:(UIWindowScene *)scene {
    if (!scene || self.windowScene == scene) return;
    self.windowScene = scene;
    POLog(@"attached to explicit scene %@ (state=%ld)", scene, (long)scene.activationState);
    // If makeKeyAndVisible was called before the scene existed, try again now.
    [super makeKeyAndVisible];
    [self updateVisibilityForLockState];
}

- (void)attachToSceneIfNeeded {
    if (self.windowScene) return;
    if (_sceneAttachAttempts > 60) {
        POLog(@"giving up attaching window to a scene");
        return;
    }
    _sceneAttachAttempts++;

    UIWindowScene *candidate = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            candidate = windowScene;
            break;
        }
        if (!candidate) candidate = windowScene;
    }

    if (candidate) {
        [self attachToScene:candidate];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self attachToSceneIfNeeded];
    });
}

- (BOOL)isDeviceLocked {
    // SpringBoard exposes a plain BOOL, but the numeric
    // SBLockStateAggregator values are private and could change in iOS 26.
    // Prefer an explicit known aggregator value, then fall back to isLocked.
    BOOL springboardLocked = NO;
    BOOL haveSpringboardValue = NO;

    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(isLocked)]) {
        @try {
            springboardLocked = [(SpringBoard *)app isLocked];
            haveSpringboardValue = YES;
        } @catch (NSException *exception) {
            POLog(@"isLocked exception: %@", exception);
        }
    }

    Class aggregatorClass = NSClassFromString(@"SBLockStateAggregator");
    if ([aggregatorClass respondsToSelector:@selector(sharedInstance)]) {
        id aggregator = [aggregatorClass sharedInstance];
        if ([aggregator respondsToSelector:@selector(lockState)]) {
            @try {
                unsigned long long state = [aggregator lockState];
                // iOS 15/16: 0 = unlocked, 1 = locked. Only trust these two
                // explicit values so an unknown new state cannot make the
                // handle permanently invisible.
                if (state == 0) return NO;
                if (state == 1) return YES;
            } @catch (NSException *exception) {
                POLog(@"lockState exception: %@", exception);
            }
        }
    }

    return haveSpringboardValue ? springboardLocked : NO;
}

- (void)updateVisibilityForLockState {
    BOOL enabled = [[POApplicationHelper settings][@"enabled"] boolValue];
    BOOL locked = [self isDeviceLocked];
    self.hidden = !enabled;
    self.alpha = (enabled && !locked) ? 1.0 : 0.0;
    POLog(@"visibility enabled=%d locked=%d alpha=%f hidden=%d", enabled, locked, self.alpha, self.hidden);

    // SBLockStateAggregator does not always tell us about an unlock on newer
    // iOS builds. While locked, poll once a second until the device unlocks so
    // the handle cannot get stuck at alpha 0.
    if (enabled && locked && !_lockRecheckScheduled) {
        _lockRecheckScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PullOverWindow *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_lockRecheckScheduled = NO;
            [strongSelf updateVisibilityForLockState];
        });
    }
}

- (void)applySettings{
    NSDictionary *settings = [POApplicationHelper settings];
    if (controller.isOpened) {
        [controller endHosting];
        [controller close];
    }
    // A fresh controller picks up dark mode, scale, labels, left-handed etc.
    self.rootViewController = controller = [[PullOverViewController alloc] init];
    self.transform = [settings[@"leftHanded"] boolValue] ? CGAffineTransformMakeScale(-1.0, 1.0) : CGAffineTransformIdentity;
    [self updateVisibilityForLockState];
}

-(void)makeKeyAndVisible{
    [self attachToSceneIfNeeded];
    [super makeKeyAndVisible];
}
- (bool)_shouldCreateContextAsSecure{
    return YES;
}



- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    UIView *hitTestResult = [super hitTest:point withEvent:event];

    if ([controller isOpened]) {
        return hitTestResult;
    }else{
        if ([hitTestResult isKindOfClass:[POHandle class]]) {
            return controller.handle;
        }
        return nil;
    }
}


@end
