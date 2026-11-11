#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief 直播卡片自动跳转拦截器。
 *
 * 抖音推荐流刷到直播卡片（未点进直播间）时，直播预览播放约十余秒后会自动滚动到下一条视频。
 * 本类负责判断「这次编程式滚动是否属于该自动跳转」：命中时由 Hook 层丢弃本次滚动，
 * 使页面停留在当前直播卡片上，等待用户手动上滑。
 *
 * 判定为「三重条件同时成立」：
 *   1. 不是用户手势驱动的滚动（未拖拽、未减速、手势处于空闲态）
 *   2. 位移量接近一整屏（排除布局校正一类的小幅修正）
 *   3. 滚动容器属于推荐流，且当前可见区域存在直播卡片角标
 */
@interface DYYYLiveCardGuard : NSObject

/**
 * 判断本次编程式滚动是否应当被阻止。
 * @param scrollView   触发滚动的滚动视图
 * @param targetOffset 目标偏移量
 * @param animated     是否为动画滚动
 * @return YES 表示应丢弃本次滚动
 */
+ (BOOL)shouldBlockProgrammaticScroll:(UIScrollView *)scrollView
                         targetOffset:(CGPoint)targetOffset
                             animated:(BOOL)animated;

/** 开关当前是否开启（读取缓存值，不访问 NSUserDefaults） */
+ (BOOL)isEnabled;

/** 重新读取开关配置，开关关闭时同时复位内部状态 */
+ (void)reloadConfiguration;

@end

NS_ASSUME_NONNULL_END
