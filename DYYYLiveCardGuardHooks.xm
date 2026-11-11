#import <UIKit/UIKit.h>
#import "DYYYLiveCardGuard.h"

// ============================================================
// 诊断版 A：只加载、不安装任何 hook
//
// 目的：把「文件本身能否安全加载」和「hook UIScrollView 是否有问题」
//      这两件事切开。
//   - 若本版注入后抖音仍卡死 → 问题在文件加载/链接/初始化，与 hook 无关
//   - 若本版正常 → 问题定位到 UIScrollView 的 hook
// ============================================================

%ctor {
    NSLog(@"[DYYY] LiveCardGuard 诊断版 A 已加载（未安装任何 hook）");
    [DYYYLiveCardGuard reloadConfiguration];
}
