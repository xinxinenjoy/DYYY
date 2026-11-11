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
// 诊断版 B：改为「分组 + %ctor 内 %init」安装，与项目其余 hook 一致
//
// 原写法使用无分组 %hook，会由 Logos 在 constructor 阶段自动安装，
// 安装时机不受控；项目本体所有 hook 都走 %group + %init。
// 同时移除了 %ctor 里对 NSUserDefaultsDidChangeNotification 的监听，
// 避免在 dylib 加载早期注册通知观察者带来的风险。
// 代价：切换开关后需重启抖音才生效。
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
        NSLog(@"[DYYY] LiveCardGuard 诊断版 C：安装 UIScrollView hook");
        %init(DYYYLiveCardGuardGroup);
    } else {
        NSLog(@"[DYYY] LiveCardGuard 诊断版 C：UIScrollView 尚未加载，跳过安装");
    }

    // 启动提示：确认 hook 活着，并报告三个关键识别类是否存在（诊断用）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *markState = objc_getClass("AWEFeedLiveMarkView") ? @"1" : @"0";
        NSString *feedState = objc_getClass("AWEFeedTableViewController") ? @"1" : @"0";
        NSString *preState = objc_getClass("AWELiveNewPreStreamViewController") ? @"1" : @"0";
        [DYYYUtils showToast:[NSString stringWithFormat:@"诊断C mark%@ feed%@ pre%@",
                               markState, feedState, preState]];
    });
}
