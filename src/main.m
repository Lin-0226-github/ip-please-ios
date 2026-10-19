//
//  IP, PLEASE — iOS 壳
//  把纯静态网页游戏打包成原生 App：内置一个只监听 127.0.0.1 的静态文件服务器，
//  用 WKWebView 以 http:// 源加载，保证 localStorage 存档、WebAudio 音效与页面行为
//  和浏览器里完全一致。
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "httpserver.h"
#import "saves.h"

static NSString *const kWebRootDirectory = @"www";
static const int kFirstPort = 48123;
static const int kPortTries = 12;

#pragma mark - View Controller

@interface GameViewController : UIViewController <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) SaveManager *saveManager;
@property (nonatomic, copy) NSURL *httpURL;
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, copy) NSURL *fileAccessURL;
@property (nonatomic, assign) BOOL didFallBackToFile;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0x16 / 255.0
                                               green:0x13 / 255.0
                                                blue:0x13 / 255.0
                                               alpha:1.0];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    config.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    config.suppressesIncrementalRendering = NO;

    // 注入：禁止选中文字 / 长按菜单 / 点击高亮，并让画面与右上角按钮避开刘海
    NSString *css = @"html,body{-webkit-user-select:none!important;-webkit-touch-callout:none!important;"
                    @"-webkit-tap-highlight-color:transparent!important;}"
                    @"body{box-sizing:border-box;padding:env(safe-area-inset-top) env(safe-area-inset-right) "
                    @"env(safe-area-inset-bottom) env(safe-area-inset-left);}"
                    @".ui{top:calc(6px + env(safe-area-inset-top));right:calc(8px + env(safe-area-inset-right));}";
    NSString *js = [NSString stringWithFormat:
        @"(function(){var s=document.createElement('style');s.textContent=%@;"
        @"(document.head||document.documentElement).appendChild(s);})();",
        [self jsStringLiteral:css]];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [config.userContentController addUserScript:script];

    // 右上角加一个「存档」按钮，点了交给原生弹菜单
    WKUserScript *saveButton = [[WKUserScript alloc] initWithSource:[self saveButtonScript]
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                       forMainFrameOnly:YES];
    [config.userContentController addUserScript:saveButton];
    [config.userContentController addScriptMessageHandler:self name:@"saveBridge"];

    CGRect bounds = self.view.bounds;
    WKWebView *web = [[WKWebView alloc] initWithFrame:bounds configuration:config];
    web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    web.navigationDelegate = self;
    web.UIDelegate = self;
    web.opaque = NO;
    web.backgroundColor = self.view.backgroundColor;
    web.scrollView.scrollEnabled = NO;
    web.scrollView.bounces = NO;
    web.scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    web.allowsBackForwardNavigationGestures = NO;
    web.allowsLinkPreview = NO;
    [self.view addSubview:web];
    self.webView = web;
    self.saveManager = [SaveManager managerWithViewController:self webView:web];

    [self loadGame];
}

- (NSString *)jsStringLiteral:(NSString *)text {
    NSMutableString *out = [NSMutableString stringWithString:@"'"];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\'' || c == '\\') {
            [out appendFormat:@"\\%C", c];
        } else if (c == '\n') {
            [out appendString:@"\\n"];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"'"];
    return out;
}

- (NSString *)saveButtonScript {
    return @"(function(){"
           @"if (window.__ipSaveInstalled) return; window.__ipSaveInstalled = true;"
           @"var tries = 0;"
           @"function add(){"
           @"  var host = document.querySelector('.ui');"
           @"  if (!host) { if (++tries < 20) setTimeout(add, 200); return; }"
           @"  if (document.getElementById('ip-save-btn')) return;"
           @"  var b = document.createElement('button');"
           @"  b.type = 'button'; b.id = 'ip-save-btn'; b.textContent = '存档';"
           @"  b.addEventListener('click', function(e){"
           @"    e.preventDefault(); e.stopPropagation();"
           @"    try { window.webkit.messageHandlers.saveBridge.postMessage('menu'); } catch (err) {}"
           @"  });"
           @"  host.appendChild(b);"
           @"}"
           @"if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add();"
           @"})();";
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"saveBridge"]) {
        [self.saveManager presentMenu];
    }
}

- (void)loadGame {
    NSURL *httpURL = self.httpURL;
    if (httpURL) {
        NSURLRequest *request = [NSURLRequest requestWithURL:httpURL
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:15.0];
        [self.webView loadRequest:request];
        return;
    }
    if (self.fileURL) {
        self.didFallBackToFile = YES;
        [self.webView loadFileURL:self.fileURL allowingReadAccessToURL:self.fileAccessURL];
    }
}

#pragma mark - 布局 / 外观

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
     withError:(NSError *)error {
    if (!self.didFallBackToFile && self.httpURL && self.fileURL) {
        NSLog(@"[IP PLEASE] http load failed (%@), falling back to file://", error.localizedDescription);
        self.httpURL = nil;  // 避免 file:// 回退时又绕回 http
        [self loadGame];
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    NSLog(@"[IP PLEASE] web content process terminated, reloading");
    [self loadGame];
}

#pragma mark - WKUIDelegate

// 关掉长按链接预览与上下文菜单，避免游戏里误触
- (void)webView:(WKWebView *)webView
        contextMenuConfigurationForElement:(WKContextMenuElementInfo *)elementInfo
                             completionHandler:(void (^)(UIContextMenuConfiguration *_Nullable))completionHandler {
    completionHandler(nil);
}

@end

#pragma mark - App Delegate

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) GameViewController *game;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSString *root = [[[NSBundle mainBundle] resourcePath]
                      stringByAppendingPathComponent:kWebRootDirectory];

    int port = hs_start(root.UTF8String, kFirstPort, kPortTries);
    NSURL *httpURL = nil;
    if (port > 0) {
        NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%d/index.html", port];
        httpURL = [NSURL URLWithString:urlString];
        NSLog(@"[IP PLEASE] serving %@ on port %d", root, port);
    } else {
        NSLog(@"[IP PLEASE] local server unavailable, using file://");
    }

    GameViewController *game = [[GameViewController alloc] init];
    game.httpURL = httpURL;
    game.fileURL = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"index.html"]];
    game.fileAccessURL = [NSURL fileURLWithPath:root isDirectory:YES];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = game;
    [self.window makeKeyAndVisible];
    self.game = game;

    // 长时间游玩不要自动锁屏
    application.idleTimerDisabled = YES;
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    application.idleTimerDisabled = NO;
}

@end

#pragma mark - main

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
