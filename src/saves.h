#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 存档导入 / 导出：从 WKWebView 的 localStorage 取出存档写成 JSON 文件分享出去，
/// 或者从「文件」里选一份 JSON 写回 localStorage。
@interface SaveManager : NSObject

+ (instancetype)managerWithViewController:(UIViewController *)host webView:(WKWebView *)webView;
- (void)presentMenu;

@end

NS_ASSUME_NONNULL_END
