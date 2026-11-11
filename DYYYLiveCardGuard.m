#import "DYYYLiveCardGuard.h"
#import "AwemeHeaders.h"
#import "DYYYUtils.h"

static NSString *const kDYYYDisableLiveCardAutoJumpKey = @"DYYYDisableLiveCardAutoJump";

/// 开关缓存值，避免滚动回调里反复读取 NSUserDefaults
static BOOL gLiveCardGuardEnabled = NO;

/// 诊断模式：忽略开关强制生效，并把判定细节用 Toast 暴露出来
static NSInteger gDiagShownCount = 0;
static NSTimeInterval gDiagLastShownTime = 0;
static const NSInteger kDYYYDiagMaxCount = 12;

@interface DYYYLiveCardGuard ()

+ (BOOL)dyyy_isUserDrivenScroll:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isFeedScrollView:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isLiveCardVisibleInScrollView:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isPreStreamControllerPresentForScrollView:(UIScrollView *)scrollView;
+ (void)dyyy_diagToast:(NSString *)text;

@end

@implementation DYYYLiveCardGuard

#pragma mark - Configuration (配置)

+ (void)reloadConfiguration {
    gLiveCardGuardEnabled = DYYYGetBool(kDYYYDisableLiveCardAutoJumpKey);
}

+ (BOOL)isEnabled {
    return gLiveCardGuardEnabled;
}

#pragma mark - Main Judgment (主判定)

+ (BOOL)shouldBlockProgrammaticScroll:(UIScrollView *)scrollView
                         targetOffset:(CGPoint)targetOffset
                             animated:(BOOL)animated {
    // 诊断版：忽略开关，强制生效，便于直接观察判定过程
    if (!scrollView) {
        return NO;
    }

    // 1. 用户手势驱动的滚动一律放行，避免影响正常翻页手感
    if ([self dyyy_isUserDrivenScroll:scrollView]) {
        return NO;
    }

    // 2. 只有接近一整屏的位移才视为「翻到下一条」，
    //    借此排除全屏切换、横竖屏适配等布局校正产生的小幅偏移
    CGFloat pageHeight = CGRectGetHeight(scrollView.bounds);
    if (pageHeight <= 1.0) {
        return NO;
    }
    CGFloat deltaY = targetOffset.y - scrollView.contentOffset.y;
    if (fabs(deltaY) < pageHeight * 0.5) {
        return NO;
    }

    // ★ 能走到这里，说明发生了一次「非手势驱动 + 整屏位移」的滚动，
    //   这正是自动跳转的特征，开始判定它是否属于直播卡片场景
    BOOL isFeed = [self dyyy_isFeedScrollView:scrollView];
    BOOL isLive = [self dyyy_isLiveCardVisibleInScrollView:scrollView];

    UIViewController *hostController = [DYYYUtils firstAvailableViewControllerFromView:scrollView];
    NSString *controllerName = hostController ? NSStringFromClass([hostController class]) : @"nil";
    if (controllerName.length > 16) {
        controllerName = [controllerName substringToIndex:16];
    }

    [self dyyy_diagToast:[NSString stringWithFormat:@"F%d L%d dy=%.0f %@",
                          isFeed ? 1 : 0,
                          isLive ? 1 : 0,
                          deltaY,
                          controllerName]];

    return isFeed && isLive;
}

#pragma mark - Diagnostics (诊断)

+ (void)dyyy_diagToast:(NSString *)text {
    if (gDiagShownCount >= kDYYYDiagMaxCount) {
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gDiagLastShownTime < 0.8) {
        return;
    }
    gDiagLastShownTime = now;
    gDiagShownCount++;

    NSLog(@"[DYYY][LiveCardDiag] %@", text);

    NSString *message = [NSString stringWithFormat:@"诊断%ld/%ld  %@",
                         (long)gDiagShownCount,
                         (long)kDYYYDiagMaxCount,
                         text];
    [DYYYUtils showToast:message];
}

#pragma mark - Detectors (判定细节)

/// 是否由用户手势驱动（拖拽中、减速中、手势未结束）
+ (BOOL)dyyy_isUserDrivenScroll:(UIScrollView *)scrollView {
    if (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) {
        return YES;
    }

    UIGestureRecognizerState panState = scrollView.panGestureRecognizer.state;
    switch (panState) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            return YES;
        default:
            return NO;
    }
}

/// 沿响应链与控制器父链判断滚动容器是否属于推荐流
+ (BOOL)dyyy_isFeedScrollView:(UIScrollView *)scrollView {
    Class feedClass = NSClassFromString(@"AWEFeedTableViewController");
    Class containerClass = NSClassFromString(@"AWEFeedContainerViewController");

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:scrollView];
    NSInteger depth = 0;

    while (viewController && depth < 12) {
        if (feedClass && [viewController isKindOfClass:feedClass]) {
            return YES;
        }
        if (containerClass && [viewController isKindOfClass:containerClass]) {
            return YES;
        }

        NSString *className = NSStringFromClass([viewController class]);
        if ([className containsString:@"Feed"] && [className containsString:@"ViewController"]) {
            return YES;
        }

        viewController = viewController.parentViewController;
        depth++;
    }

    return NO;
}

/// 当前可见区域内是否存在处于显示状态的直播卡片角标
+ (BOOL)dyyy_isLiveCardVisibleInScrollView:(UIScrollView *)scrollView {
    Class markClass = NSClassFromString(@"AWEFeedLiveMarkView");

    if (markClass) {
        NSArray<__kindof UIView *> *markViews = [DYYYUtils findAllSubviewsOfClass:markClass inContainer:scrollView];
        CGRect visibleRect = CGRectMake(scrollView.contentOffset.x,
                                        scrollView.contentOffset.y,
                                        CGRectGetWidth(scrollView.bounds),
                                        CGRectGetHeight(scrollView.bounds));

        for (UIView *markView in markViews) {
            if (markView.hidden || markView.alpha < 0.05f || !markView.window) {
                continue;
            }

            CGRect frameInScrollView = [markView convertRect:markView.bounds toView:scrollView];
            if (CGRectGetHeight(frameInScrollView) <= 0 || CGRectGetWidth(frameInScrollView) <= 0) {
                continue;
            }
            if (CGRectIntersectsRect(frameInScrollView, visibleRect)) {
                return YES;
            }
        }

        // 找到过角标类但都不在可见区，说明当前不是直播卡片
        if (markViews.count > 0) {
            return NO;
        }
    }

    // 角标类缺失时的兜底：检查控制器链上是否存在直播预览流容器
    return [self dyyy_isPreStreamControllerPresentForScrollView:scrollView];
}

/// 兜底判定：控制器父链上存在直播预览流控制器
+ (BOOL)dyyy_isPreStreamControllerPresentForScrollView:(UIScrollView *)scrollView {
    Class preStreamClass = NSClassFromString(@"AWELiveNewPreStreamViewController");
    if (!preStreamClass) {
        return NO;
    }

    UIViewController *viewController = [DYYYUtils firstAvailableViewControllerFromView:scrollView];
    NSInteger depth = 0;

    while (viewController && depth < 12) {
        if ([viewController isKindOfClass:preStreamClass] && viewController.view.window) {
            return YES;
        }
        viewController = viewController.parentViewController;
        depth++;
    }

    return NO;
}

@end
