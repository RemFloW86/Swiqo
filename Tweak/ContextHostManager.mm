#import "ContextHostManager.h"
#import "POLog.h"

static NSString *const kPresenterID = @"com.pulloverpro.ios26";

@implementation ContextHostManager {
    NSString *_bundleId;
    __weak FBScene *_scene;
    _UIScenePresenter *_presenter;
    BOOL _weForegrounded;   // only send the app back if we brought it forward
}

+ (instancetype)sharedInstance {
    static ContextHostManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

// The app's main scene. Its identifier looks like "sceneID:<bundle id>-default";
// prefer that one when an app has several scenes.
- (FBScene *)sceneForBundleId:(NSString *)bundleId {
    if (!bundleId) return nil;

    Class managerClass = NSClassFromString(@"FBSceneManager");
    if ([managerClass respondsToSelector:@selector(sharedInstance)]) {
        id manager = [managerClass sharedInstance];
        NSSet *scenes = nil;
        @try {
            if ([manager respondsToSelector:@selector(scenesPassingTest:)]) {
                scenes = [manager scenesPassingTest:^BOOL(FBScene *scene) {
                    @try {
                        return [scene.clientProcess.bundleIdentifier isEqualToString:bundleId];
                    } @catch (NSException *exception) {
                        return NO;
                    }
                }];
            } else if ([manager respondsToSelector:@selector(scenes)]) {
                scenes = [manager scenes];
            } else {
                // Older/other FrontBoard builds expose the scene dictionary instead.
                NSDictionary *byID = [manager valueForKey:@"_scenesByID"];
                if ([byID isKindOfClass:[NSDictionary class]]) scenes = [NSSet setWithArray:byID.allValues];
            }
        } @catch (NSException *exception) {
            POLog(@"scenesPassingTest exception: %@", exception);
        }

        if ([scenes isKindOfClass:[NSSet class]] || [scenes isKindOfClass:[NSArray class]]) {
            FBScene *best = nil;
            for (FBScene *scene in scenes) {
                if (![scene isKindOfClass:NSClassFromString(@"FBScene")]) continue;
                if ([[scene identifier] hasSuffix:@"-default"]) return scene;
                if (!best) best = scene;
            }
            if (best) return best;
        }
        POLog(@"no FBSceneManager scene for %@", bundleId);
    } else {
        POLog(@"FBSceneManager unavailable");
    }

    // iOS 26 fallback: SpringBoard's SBApplication can hand out the app's main
    // scene directly, without walking FrontBoard's private scene list.
    @try {
        id controller = [NSClassFromString(@"SBApplicationController") sharedInstance];
        if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
            id app = [controller applicationWithBundleIdentifier:bundleId];
            if ([app respondsToSelector:@selector(mainScene)]) {
                FBScene *scene = [app mainScene];
                if (scene) {
                    POLog(@"scene for %@ via SBApplication.mainScene", bundleId);
                    return scene;
                }
            }
        }
    } @catch (NSException *exception) {
        POLog(@"SBApplication mainScene exception: %@", exception);
    }

    return nil;
}

- (void)openApplication:(NSString *)bundleId suspended:(BOOL)suspended {
    if (!bundleId) return;

    Class service = NSClassFromString(@"FBSSystemService");
    if ([service respondsToSelector:@selector(sharedService)]) {
        id sharedService = [service sharedService];
        if ([sharedService respondsToSelector:@selector(openApplication:options:withResult:)]) {
            NSDictionary *options = suspended ? @{@"__ActivateSuspended": @YES} : @{@"__UnlockDevice": @YES};
            @try {
                [sharedService openApplication:bundleId options:options withResult:^(NSError *error) {
                    POLog(@"open %@ suspended=%d -> %@", bundleId, suspended, error ?: @"ok");
                }];
                return;
            } @catch (NSException *exception) {
                POLog(@"FBSSystemService open exception: %@", exception);
            }
        }
    }

    // iOS 26 fallback. This opens the app full screen rather than suspended, but
    // it is better than doing nothing if the private option key changed.
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        id workspace = [workspaceClass defaultWorkspace];
        if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
            @try {
                [workspace openApplicationWithBundleID:bundleId];
                POLog(@"open %@ via LSApplicationWorkspace", bundleId);
            } @catch (NSException *exception) {
                POLog(@"LSApplicationWorkspace open exception: %@", exception);
            }
        }
    }
}

- (void)launchInBackground:(NSString *)bundleId {
    if ([self sceneForBundleId:bundleId]) return;
    [self openApplication:bundleId suspended:YES];
}

- (void)openFullScreen:(NSString *)bundleId {
    [self openApplication:bundleId suspended:NO];
}

- (void)setScene:(FBScene *)scene foreground:(BOOL)foreground {
    if (![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
        POLog(@"scene does not support updateSettingsWithBlock:");
        return;
    }
    @try {
        [scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            if ([settings respondsToSelector:@selector(setForeground:)]) settings.foreground = foreground;
        }];
    } @catch (NSException *exception) {
        POLog(@"setScene foreground exception: %@", exception);
    }
}

- (UIView *)hostViewForBundleID:(NSString *)bundleId {
    if (_presenter && [_bundleId isEqualToString:bundleId] &&
        (![_presenter respondsToSelector:@selector(isInvalidated)] || !_presenter.invalidated)) {
        return _presenter.presentationView;
    }
    if (_bundleId) [self stopHostingForBundleID:_bundleId];

    FBScene *scene = [self sceneForBundleId:bundleId];
    POLog(@"host %@: scene=%@", bundleId, scene.identifier);
    if (!scene || ![scene respondsToSelector:@selector(uiPresentationManager)]) return nil;

    UIScenePresentationManager *manager = scene.uiPresentationManager;
    if (!manager || ![manager respondsToSelector:@selector(createPresenterWithIdentifier:)]) {
        POLog(@"no uiPresentationManager for %@", bundleId);
        return nil;
    }

    _weForegrounded = !scene.settings.foreground;
    if (_weForegrounded) [self setScene:scene foreground:YES];

    _UIScenePresenter *presenter = nil;
    @try {
        presenter = [manager createPresenterWithIdentifier:kPresenterID];
    } @catch (NSException *exception) {
        POLog(@"createPresenter exception: %@", exception);
    }
    if (!presenter) {
        POLog(@"createPresenter returned nil for %@", bundleId);
        return nil;
    }

    @try {
        if ([presenter respondsToSelector:@selector(modifyPresentationContext:)]) {
            [presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
                @try {
                    if ([context respondsToSelector:@selector(setAppearanceStyle:)]) context.appearanceStyle = 2;   // live content, not a snapshot
                    if ([context respondsToSelector:@selector(setBackgroundColorWhileNotHosting:)]) {
                        context.backgroundColorWhileNotHosting = UIColor.clearColor;
                    }
                } @catch (NSException *exception) {
                    POLog(@"presentation context exception: %@", exception);
                }
            }];
        }
        if ([presenter respondsToSelector:@selector(activate)]) [presenter activate];
    } @catch (NSException *exception) {
        POLog(@"presenter configure exception: %@", exception);
    }

    UIView *presentationView = [presenter respondsToSelector:@selector(presentationView)] ? presenter.presentationView : nil;
    POLog(@"host %@: presenter=%@ view=%@ wasForeground=%d", bundleId, presenter, presentationView, !_weForegrounded);
    if (!presentationView) return nil;

    _bundleId = [bundleId copy];
    _scene = scene;
    _presenter = presenter;
    return presentationView;
}

- (void)stopHostingForBundleID:(NSString *)bundleId {
    if (!_presenter) return;
    @try {
        if ([_presenter respondsToSelector:@selector(deactivate)]) [_presenter deactivate];
        if ([_presenter respondsToSelector:@selector(invalidate)]) [_presenter invalidate];
    } @catch (NSException *exception) {
        POLog(@"stopHosting exception: %@", exception);
    }
    _presenter = nil;

    FBScene *scene = _scene;
    if (scene && _weForegrounded) [self setScene:scene foreground:NO];
    _scene = nil;
    _bundleId = nil;
    _weForegrounded = NO;
}

- (BOOL)isHostViewHosting:(UIView *)hostView {
    if (!hostView || !_presenter) return NO;
    if ([_presenter respondsToSelector:@selector(isInvalidated)] && _presenter.invalidated) return NO;
    UIView *presentationView = [_presenter respondsToSelector:@selector(presentationView)] ? _presenter.presentationView : nil;
    return hostView == presentationView;
}

@end
