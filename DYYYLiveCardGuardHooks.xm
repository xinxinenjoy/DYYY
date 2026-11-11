#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AwemeHeaders.h"
#import "DYYYLiveCardGuard.h"
#import "DYYYUtils.h"

/// 每次启动仅提示一次，避免反复弹窗
static BOOL gDYYYLiveCardGuardDidNotify = NO;
/// 日志节流，防止抖音重试时刷屏
static NSTimeInterval gDYYYLiveCardGuardLastLogTime = 0;

static void DYYYLiveCardGuardDidBlock(BOOL animated) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gDYYYLiveCardGuardLastLogTime > 1.0) {
        gDYYYLiveCardGuardLastLogTime = now;
        NSLog(@"[DYYY] 已阻止直播卡片自动跳转（animated=%d）", animated);
    }

    if (gDYYYLiveCardGuardDidNotify) {
        return;
    }
    gDYYYLiveCardGuardDidNotify = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        [DYYYUtils showToast:@"已阻止直播卡片自动跳转"];
    });
}

// ============================================================
// 直播卡片防自动跳转：拦截 UIScrollView 的编程式滚动
//
// 采用「分组 + %ctor 内 %init」安装，与项目其余 hook 保持一致。
// 早期版本使用无分组 %hook，由 Logos 在 constructor 阶段自动安装，
// 实测会导致抖音启动卡死；改为分组安装后正常。
// 注意：切换开关后需重启抖音才生效。
// ============================================================

%group DYYYLiveCardGuardGroup

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
    if ([DYYYLiveCardGuard shouldBlockProgrammaticScroll:self targetOffset:contentOffset animated:NO]) {
        DYYYLiveCardGuardDidBlock(NO);
        return;
    }
    %orig;
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if ([DYYYLiveCardGuard shouldBlockProgrammaticScroll:self targetOffset:contentOffset animated:animated]) {
        DYYYLiveCardGuardDidBlock(animated);
        return;
    }
    %orig;
}

%end

%end

%ctor {
    [DYYYLiveCardGuard reloadConfiguration];

    Class scrollViewClass = objc_getClass("UIScrollView");
    if (scrollViewClass) {
        %init(DYYYLiveCardGuardGroup);
    }
}
