#import "DYYYLiveCardGuard.h"
#import "AwemeHeaders.h"
#import "DYYYUtils.h"

static NSString *const kDYYYDisableLiveCardAutoJumpKey = @"DYYYDisableLiveCardAutoJump";

/// 开关缓存值，避免滚动回调里反复读取 NSUserDefaults
static BOOL gLiveCardGuardEnabled = NO;

@interface DYYYLiveCardGuard ()

+ (BOOL)dyyy_isUserDrivenScroll:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isFeedScrollView:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isLiveCardVisibleInScrollView:(UIScrollView *)scrollView;
+ (BOOL)dyyy_hasVisibleViewOfClass:(Class)targetClass inScrollView:(UIScrollView *)scrollView;
+ (BOOL)dyyy_isPreStreamControllerPresentForScrollView:(UIScrollView *)scrollView;

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
    // 开关关闭时仅有一次布尔判断，对滚动性能无影响
    if (!gLiveCardGuardEnabled || !scrollView) {
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

    // 3. 滚动容器必须属于推荐流
    if (![self dyyy_isFeedScrollView:scrollView]) {
        return NO;
    }

    // 4. 当前可见区域必须正在展示直播卡片
    if (![self dyyy_isLiveCardVisibleInScrollView:scrollView]) {
        return NO;
    }

    return YES;
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

/// 当前可见区域内是否存在处于显示状态的直播卡片
///
/// 识别依据来自真机实测（抖音 41.1.0）：
///   主依据 AWEFeedLiveStreamTableViewCell      —— 直播预览卡片的 cell 本体
///   辅依据 AWELivePreStream4LayerContainerView —— 预览流四层容器
///   辅依据 AWEFeedLiveMarkView                 —— 直播角标（部分版本使用）
+ (BOOL)dyyy_isLiveCardVisibleInScrollView:(UIScrollView *)scrollView {
    NSArray<NSString *> *liveClassNames = @[
        @"AWEFeedLiveStreamTableViewCell",
        @"AWELivePreStream4LayerContainerView",
        @"AWEFeedLiveMarkView"
    ];

    for (NSString *className in liveClassNames) {
        Class liveClass = NSClassFromString(className);
        if (liveClass && [self dyyy_hasVisibleViewOfClass:liveClass inScrollView:scrollView]) {
            return YES;
        }
    }

    // 以上视图标识都取不到时的兜底：控制器链上存在直播预览流容器
    return [self dyyy_isPreStreamControllerPresentForScrollView:scrollView];
}

/// 指定类在滚动视图内是否存在「真正可见」的实例
+ (BOOL)dyyy_hasVisibleViewOfClass:(Class)targetClass inScrollView:(UIScrollView *)scrollView {
    NSArray<__kindof UIView *> *views = [DYYYUtils findAllSubviewsOfClass:targetClass inContainer:scrollView];
    if (views.count == 0) {
        return NO;
    }

    CGRect visibleRect = CGRectMake(scrollView.contentOffset.x,
                                    scrollView.contentOffset.y,
                                    CGRectGetWidth(scrollView.bounds),
                                    CGRectGetHeight(scrollView.bounds));

    for (UIView *view in views) {
        if (view.hidden || view.alpha < 0.05f || !view.window) {
            continue;
        }

        CGRect frameInScrollView = [view convertRect:view.bounds toView:scrollView];
        if (CGRectGetHeight(frameInScrollView) <= 0 || CGRectGetWidth(frameInScrollView) <= 0) {
            continue;
        }
        if (CGRectIntersectsRect(frameInScrollView, visibleRect)) {
            return YES;
        }
    }

    return NO;
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
