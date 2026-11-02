#import <rootless.h>
//
//  PullOverViewController.m
//  PullOverPro
//
//  Created by Will Smillie on 4/8/19.
//

#import "PullOverViewController.h"
#import "POLog.h"

#define HANDLE_MARGIN 50
#define HALF_OPEN_HEIGHT 400



@interface PullOverViewController (){
    NSString *pinnedBundleId;
    UIView *contextView;
    
    UIView *dragAndDropView;
    UIImageView *draggableImageView;
    UILabel *dragAndDropLabel;
    
    UIView *overlayView;
    UIActivityIndicatorView *activityIndicator;
}

@end

@implementation PullOverViewController
@synthesize scrollView, handleScrollView;

static CGRect  handleFrame;
static CGPoint handlePoint;
static float scale;
static bool showingCantHost = NO;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    scale = ([UIScreen mainScreen].bounds.size.width-HANDLE_MARGIN)/[UIScreen mainScreen].bounds.size.width;

    self.backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.backgroundView.alpha = 0;
    [self.view addSubview:self.backgroundView];
    
    
    UIImage *image = [UIImage imageWithContentsOfFile:ROOT_PATH_NS(@"/Library/Application Support/PullOverPro/rocket.png")];
    
    
    dragAndDropView = [[UIView alloc] initWithFrame:CGRectMake(0,0,100,100)];
    dragAndDropView.contentMode = UIViewContentModeScaleAspectFit;
    dragAndDropView.center = CGPointMake(self.backgroundView.center.x, self.backgroundView.center.y);
    dragAndDropView.alpha = 0;
    [self.backgroundView addSubview:dragAndDropView];
    
    CAShapeLayer *border = [CAShapeLayer layer];
    border.strokeColor = [UIColor whiteColor].CGColor;
    border.fillColor = nil;
    border.lineDashPattern = @[@4, @2];
    [dragAndDropView.layer addSublayer:border];
    
    border.path = [UIBezierPath bezierPathWithRect:dragAndDropView.bounds].CGPath;
    border.frame = dragAndDropView.bounds;


    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageView.tintColor = [UIColor whiteColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.center = CGPointMake(dragAndDropView.frame.size.width/2, dragAndDropView.frame.size.height/2);
    [dragAndDropView addSubview:imageView];
    
    
    dragAndDropLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,dragAndDropView.frame.size.height+dragAndDropView.frame.origin.y+16,200, 44)];
    dragAndDropLabel.textColor = [UIColor whiteColor];
    dragAndDropLabel.textAlignment = NSTextAlignmentCenter;
    dragAndDropLabel.numberOfLines = 2;
    dragAndDropLabel.text = @"Drag QuickSwitch Items\nHere To Open";
    [self.backgroundView addSubview:dragAndDropLabel];
    dragAndDropLabel.alpha = 0;
    dragAndDropLabel.center = CGPointMake(dragAndDropView.center.x, dragAndDropLabel.center.y);
    
    
    scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    [scrollView setContentSize:CGSizeMake((self.view.bounds.size.width*2)-HANDLE_MARGIN, self.view.bounds.size.height)];
    [scrollView setDecelerationRate:UIScrollViewDecelerationRateFast];
    [scrollView setBackgroundColor:[UIColor clearColor]];
    [scrollView setShowsHorizontalScrollIndicator:NO];
    [scrollView setPagingEnabled:YES];
    [scrollView setDelegate:self];
    [self.view addSubview:scrollView];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    [scrollView addGestureRecognizer:tap];
    
    handleScrollView = [[BaseScrollView alloc] initWithFrame:CGRectMake(self.view.frame.size.width-HANDLE_MARGIN, 0, HANDLE_MARGIN, [UIScreen mainScreen].bounds.size.height*scale)];
    [handleScrollView setContentSize:CGSizeMake(handleScrollView.frame.size.width, (([UIScreen mainScreen].bounds.size.height*scale)*2)-34)];
    [handleScrollView setShowsVerticalScrollIndicator:NO];
    [handleScrollView setBackgroundColor:[UIColor clearColor]];
    [handleScrollView setDecelerationRate:UIScrollViewDecelerationRateFast];
    [handleScrollView setClipsToBounds:NO];
    [handleScrollView setDelegate:self];
    id savedHandlePoint = [[POApplicationHelper state] valueForKey:@"handlePoint"];
    if ([savedHandlePoint isKindOfClass:[NSString class]]) {
        [handleScrollView setContentOffset:CGPointFromString(savedHandlePoint)];
    }
    handleScrollView.center = CGPointMake(handleScrollView.center.x, self.view.frame.size.height/2);
    [scrollView addSubview:handleScrollView];

    
    self.handle = [[POHandle alloc] initWithController:self];
    [self.handle setDelegate:self];
    CGRect r = self.handle.frame; r.origin.y = ([UIScreen mainScreen].bounds.size.height*scale)-self.handle.frame.size.height; self.handle.frame = r;
    handleFrame = self.handle.frame;
    handlePoint = handleScrollView.contentOffset;
    [handleScrollView addSubview:self.handle];
    
    self.quickSwitchTableView = [[QuickSwitchTableView alloc] initWithDarkMode:self.handle.darkMode];
    self.quickSwitchTableView.selectionDelegate = self;
    [handleScrollView addSubview:self.quickSwitchTableView];
    
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(self.view.frame.size.width, 20, [UIScreen mainScreen].bounds.size.width*scale, [UIScreen mainScreen].bounds.size.height*scale)];
    self.contentView.center = CGPointMake(self.contentView.center.x, self.view.frame.size.height/2);
    if (@available(iOS 13, *)){
        NSLog(@"iOS 13 bg color");
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }else{
        NSLog(@"pre 13 bg color");

        self.contentView.backgroundColor = [[POApplicationHelper settings][@"darkHandle"] boolValue] ? [UIColor darkGrayColor] : [UIColor whiteColor];
    }
    self.contentView.layer.cornerRadius = 12;
    self.contentView.clipsToBounds = YES;
    
    activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    activityIndicator.color = [UIColor whiteColor];
    activityIndicator.frame = CGRectMake(42, 54, 37, 37);
    activityIndicator.layer.shadowOpacity = 0.5;
    activityIndicator.layer.shadowRadius = 6;
    activityIndicator.layer.shadowOffset = CGSizeMake(0, 0);
    [activityIndicator startAnimating];

    [self.contentView addSubview:activityIndicator];

    
    [scrollView addSubview:self.contentView];
    
    if ([[POApplicationHelper state] stringForKey:@"lastPinnedBundleId"]) {
        pinnedBundleId = [[POApplicationHelper state] stringForKey:@"lastPinnedBundleId"];
        UIImage *image = [POApplicationHelper imageForBundleId:pinnedBundleId];
        self.handle.imageView.image = image;
    }else{
        pinnedBundleId = @"com.apple.MobileSMS";
        UIImage *image = [POApplicationHelper imageForBundleId:pinnedBundleId];
        self.handle.imageView.image = image;
    }
    
    if ([[POApplicationHelper settings][@"leftHanded"] boolValue]){
        imageView.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        dragAndDropLabel.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        self.handle.imageView.transform = CGAffineTransformMakeScale(-1.0, 1.0);
    }
    
    overlayView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    overlayView.backgroundColor = [UIColor clearColor];
    overlayView.userInteractionEnabled = NO;
    [self.view addSubview:overlayView];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

-(void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    
    activityIndicator.center = CGPointMake(self.contentView.frame.size.width/2, self.contentView.frame.size.height/2);
}

-(BOOL)shouldAutorotate
{
    return NO;
}

static NSNumber *origOffset = nil;
-(void)keyboardWillShow:(NSNotification *)notification{
    if ([[POApplicationHelper settings][@"keyboardAvoiding"] boolValue]){
        CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
        
        if (handleScrollView.contentOffset.y+handleFrame.origin.x < keyboardSize.height) {
            origOffset = [NSNumber numberWithFloat:handleScrollView.contentOffset.y];
            [handleScrollView setContentOffset:CGPointMake(0, keyboardSize.height+44) animated:YES];
        }else{
            origOffset = nil;
        }
    }
}

-(void)keyboardWillHide:(NSNotification *)notification{
    if ([[POApplicationHelper settings][@"keyboardAvoiding"] boolValue]){
        if (origOffset) {
            [handleScrollView setContentOffset:CGPointMake(0, [origOffset floatValue]) animated:YES];
        }
    }
}


-(void)pinAppWithBundleId:(NSString *)bundleId{
    POLog(@"pin %@ (front=%@)", bundleId, [POApplicationHelper frontMostBundleId]);
    pinnedBundleId = bundleId;
    
    [[POApplicationHelper state] setObject:bundleId forKey:@"lastPinnedBundleId"];
    UIImage *image = [POApplicationHelper imageForBundleId:bundleId];
    self.handle.imageView.image = image;
    
    if ([[POApplicationHelper frontMostBundleId] isEqualToString:bundleId]) {
        // _returnToHomescreenWithCompletion: is gone on iOS 15+; a simulated Home press does the same (iOS 15-27).
        id sb = [UIApplication sharedApplication];
        if ([sb respondsToSelector:@selector(_simulateHomeButtonPressWithCompletion:)]) [sb _simulateHomeButtonPressWithCompletion:nil];
        else if ([sb respondsToSelector:@selector(_simulateHomeButtonPress)]) [sb _simulateHomeButtonPress];
    }else{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self open];
        });
    }
}

-(void)open{
    CGRect frame = scrollView.frame; frame.origin.y = 0;
    frame.origin.x = frame.size.width * 1;
    [scrollView scrollRectToVisible:frame animated:YES];
}

-(void)close{
    CGRect frame = scrollView.frame; frame.origin.y = 0;
    frame.origin.x = frame.size.width * 0;
    [scrollView scrollRectToVisible:frame animated:YES];
}
     

#pragma mark - MHHandleDelegate

-(void)handle:(POHandle *)handle didReceiveTap:(UIGestureRecognizer *)recognizer{
    if (!self.isOpened) {
        [self open];
    }else{
        [self close];
    }
}

-(void)handle:(POHandle *)handle didLongPress:(UILongPressGestureRecognizer *)recognizer{
    if (!self.isOpened) {
        if (self.handle.isNubbed) {
            self.handle.isNubbed = NO;
        }

        [self.quickSwitchTableView presentFromHandle:handle withRecognizer:recognizer];
        
        [UIView animateWithDuration:0.3 animations:^{
            if (recognizer.state == UIGestureRecognizerStateBegan) {
                self.backgroundView.alpha = 1;
            }else if (recognizer.state != UIGestureRecognizerStateChanged){
                self.backgroundView.alpha = 0;
            }
        }];
    }
}


#pragma mark - QuickSwitch

-(void)quickSwitchTableView:(QuickSwitchTableView *)quickSwitchTableView didSelectBundleId:(NSString *)bundleId{
    [self pinAppWithBundleId:bundleId];
}

-(void)quickSwitchTableViewWillAppear:(QuickSwitchTableView *)quickSwitchTableView{
    dragAndDropView.alpha = 1;
    if (![[POApplicationHelper settings][@"hideLabels"] boolValue]){
        dragAndDropLabel.alpha = 1;
    }
}

-(void)quickSwitchTableView:(QuickSwitchTableView *)quickSwitchTableView draggingDidChangeForQuickSwitchItem:(SBApplication *)app withPoint:(CGPoint)point{
    
    if (!draggableImageView) {
        draggableImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
        draggableImageView.image = [POApplicationHelper imageForBundleId:app.bundleIdentifier];
        draggableImageView.contentMode = UIViewContentModeScaleAspectFill;
        draggableImageView.center = [self.backgroundView convertPoint:point fromView:quickSwitchTableView];
        [self.backgroundView addSubview:draggableImageView];
        
        if ([[POApplicationHelper settings][@"leftHanded"] boolValue]){
            draggableImageView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(-1.0, 1.0), CGAffineTransformMakeScale(0.01, 0.01));
            [UIView animateWithDuration:0.2 animations:^{
                draggableImageView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(-1.0, 1.0), CGAffineTransformMakeScale(1, 1));
            }];
        }else{
            draggableImageView.transform = CGAffineTransformMakeScale(0.01, 0.01);
            [UIView animateWithDuration:0.2 animations:^{
                draggableImageView.transform = CGAffineTransformMakeScale(1, 1);
            }];
        }
    }
    
    draggableImageView.center = [self.backgroundView convertPoint:point fromView:quickSwitchTableView];

    CGPoint locationInView = [dragAndDropView convertPoint:point fromView:quickSwitchTableView];
    if (CGRectContainsPoint(dragAndDropView.bounds, locationInView) ) {
        [UIView animateWithDuration:0.3f animations:^{
            dragAndDropLabel.text = [NSString stringWithFormat:@"Open %@", app.displayName];
            dragAndDropView.transform = CGAffineTransformMakeScale(1.3, 1.3);
        }];
    }else{
        [UIView animateWithDuration:0.3f animations:^{
            dragAndDropLabel.text = @"Drag QuickSwitch Items\nHere To Open";
            dragAndDropView.transform = CGAffineTransformMakeScale(1, 1);
        }];
    }
}

-(void)quickSwitchTableView:(QuickSwitchTableView *)quickSwitchTableView didDropApp:(SBApplication *)app atPoint:(CGPoint)point{
    [self removeDraggableImageViewAnimated];
    
    if (CGRectContainsPoint(dragAndDropView.bounds, [dragAndDropView convertPoint:point fromView:quickSwitchTableView]) ) {
        [[ContextHostManager sharedInstance] openFullScreen:app.bundleIdentifier];
    }
}

-(void)draggingDidEnterBoundsOfQuickSwitchTableView:(QuickSwitchTableView *)quickSwitchTableView{
    [self removeDraggableImageViewAnimated];
}

-(void)removeDraggableImageViewAnimated{
    [draggableImageView.layer removeAllAnimations];

    
    if ([[POApplicationHelper settings][@"leftHanded"] boolValue]){
        draggableImageView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(-1.0, 1.0), CGAffineTransformMakeScale(1, 1));
        [UIView animateWithDuration:0.2 animations:^{
            draggableImageView.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(-1.0, 1.0), CGAffineTransformMakeScale(0.01, 0.01));
        }completion:^(BOOL finished) {
            [draggableImageView removeFromSuperview];
            draggableImageView = nil;
        }];

    }else{
        draggableImageView.transform = CGAffineTransformMakeScale(1, 1);
        [UIView animateWithDuration:0.2 animations:^{
            draggableImageView.transform = CGAffineTransformMakeScale(0.01, 0.01);
        }completion:^(BOOL finished) {
            [draggableImageView removeFromSuperview];
            draggableImageView = nil;
        }];
    }

    
    [UIView animateWithDuration:0.3f animations:^{
        dragAndDropLabel.text = @"Drag QuickSwitch Items\nHere To Open";
        dragAndDropView.transform = CGAffineTransformMakeScale(1, 1);
    }];
}

-(void)quickSwitchTableViewDidDisappear:(QuickSwitchTableView *)quickSwitchTableView{
    dragAndDropView.alpha = 0;
    dragAndDropLabel.alpha = 0;
}



#pragma mark - UIScrollViewDelegate

-(void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate{
    float progress = scrollView.contentOffset.x / (scrollView.frame.size.width-HANDLE_MARGIN);
    if (progress == 0) {
        handleFrame = self.handle.frame;
        handlePoint = handleScrollView.contentOffset;
        [[POApplicationHelper state] setValue:NSStringFromCGPoint(handlePoint) forKey:@"handlePoint"];
    }
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)sv{
    float progress = scrollView.contentOffset.x / (scrollView.frame.size.width-HANDLE_MARGIN);
    if (progress == 0) {
        handleFrame = self.handle.frame;
        handlePoint = handleScrollView.contentOffset;
        [[POApplicationHelper state] setValue:NSStringFromCGPoint(handlePoint) forKey:@"handlePoint"];
    }else if (progress == 1){
        [self beginHosting];
    }
}

-(void)scrollViewDidScroll:(UIScrollView *)sv{
    float progress = scrollView.contentOffset.x / (scrollView.frame.size.width-HANDLE_MARGIN);
    
    if (sv == scrollView) {
        self.backgroundView.alpha = progress;
        
        if (progress == 0) {
            self.isOpened = NO;
        }else{
            self.isOpened = YES;
        }
        
        
        if (progress < 0) {
            if (!self.handle.isNubbed) {
                self.handle.isNubbed = YES;
            }
        }else if (progress > 0){
            if (self.handle.isNubbed) {
                self.handle.isNubbed = NO;
            }
        }
    }
}

-(void)setIsOpened:(BOOL)isOpened{
    _isOpened = isOpened;
    
    overlayView.userInteractionEnabled = NO;
    if (isOpened) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoNubAfterDelay) object:nil];
        [self beginHosting];
    }else{
        [self endHosting];
        if ([[POApplicationHelper settings][@"autoNub"] boolValue]){
            [self performSelector:@selector(autoNubAfterDelay) withObject:nil afterDelay:[[POApplicationHelper settings][@"autoNub-time"] intValue]];
        }
    }
}

-(void)autoNubAfterDelay{
    [self.handle setIsNubbed:YES];
}


-(void)beginHosting{
    [activityIndicator stopAnimating];

    if (![[POApplicationHelper frontMostBundleId] isEqualToString:pinnedBundleId]) {
        if (pinnedBundleId && ![[ContextHostManager sharedInstance] isHostViewHosting:contextView]) {
            [activityIndicator startAnimating];

            [[ContextHostManager sharedInstance] launchInBackground:pinnedBundleId];
            
            contextView = [[ContextHostManager sharedInstance] hostViewForBundleID:pinnedBundleId];
            
            if (contextView) {
                contextView.alpha = 0;
                [self layoutContextView];
            }
            
            POLog(@"beginHosting %@ -> view=%@", pinnedBundleId, contextView);
            
            [self performSelector:@selector(beginHosting) withObject:nil afterDelay:1];
        }
    }else{
        if (!showingCantHost) {
            [self showCantHostView];
        }
    }
}

-(void)layoutContextView{
    contextView.transform = CGAffineTransformScale(CGAffineTransformIdentity, scale, scale);
    if ([[POApplicationHelper settings][@"leftHanded"] boolValue]){
        contextView.transform = CGAffineTransformConcat(contextView.transform, CGAffineTransformMakeScale(-1.0, 1.0));
    }
    
    [self.contentView addSubview:contextView];
    
    CGRect frame = contextView.frame;
    frame.origin.x = 0;
    frame.origin.y = 0;
    frame.size.width = self.contentView.frame.size.width;
    frame.size.height = self.contentView.frame.size.height;
    contextView.frame = frame;
    

    [UIView animateWithDuration:0.3 animations:^{
        contextView.alpha = 1;
    }];

    
}

-(void)cleanUpSubviews{
    for (UIView *v in self.contentView.subviews) {
        if (![v isKindOfClass:[UIActivityIndicatorView class]]) {
            [v removeFromSuperview];
        }
    }
}

-(void)endHosting{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginHosting) object:nil];
    
    if (pinnedBundleId && [[ContextHostManager sharedInstance] isHostViewHosting:contextView]) {
        [self cleanUpSubviews];
        [[ContextHostManager sharedInstance] stopHostingForBundleID:pinnedBundleId];
    }
    
    [contextView removeFromSuperview];
    for (UIView *v in overlayView.subviews) {
        [v removeFromSuperview];
    }
    contextView = nil;

    showingCantHost = NO;
}

-(void)showCantHostView{
    showingCantHost = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CGPoint p = [self.scrollView convertPoint:self.contentView.center toView:self.contentView];
        UILabel *wontHostLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.contentView.frame.size.width-32, 80)];
        wontHostLabel.numberOfLines = 3;
        [wontHostLabel setTextAlignment:NSTextAlignmentCenter];
        wontHostLabel.text = @"This app is already open on screen, so it can't be pulled over right now.";
        wontHostLabel.center = CGPointMake(p.x, p.y+60);
        [self.contentView addSubview:wontHostLabel];
        
        p = [self.scrollView convertPoint:self.contentView.center toView:self.contentView];
        UIImageView *animation = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"rectangle.on.rectangle.slash"]];
        animation.tintColor = [UIColor secondaryLabelColor];
        animation.frame = CGRectMake(0, 0, 120, 120);
        [animation setContentMode:UIViewContentModeScaleAspectFit];
        animation.center = CGPointMake(p.x, p.y-60);
        [self.contentView addSubview:animation];
        
        if ([[POApplicationHelper settings][@"leftHanded"] boolValue]){
            wontHostLabel.transform = CGAffineTransformMakeScale(-1.0, 1.0);
            animation.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        }
    });
}

-(void)retryHostingIfNeeded{
    if (pinnedBundleId && ![[ContextHostManager sharedInstance] isHostViewHosting:contextView]) {
        [self setIsOpened:YES];
    }
}


@end
