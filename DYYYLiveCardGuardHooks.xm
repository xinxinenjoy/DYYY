#import <UIKit/UIKit.h>
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

%ctor {
    [DYYYLiveCardGuard reloadConfiguration];

    // 设置页切换开关后无需重启抖音即可生效
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
                                                    [DYYYLiveCardGuard reloadConfiguration];
                                                  }];
}
