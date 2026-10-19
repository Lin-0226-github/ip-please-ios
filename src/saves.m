//
//  存档导入导出
//  游戏把进度存在 localStorage['ip-please-save-v1'] 里。这里用 JS 桥把那份 JSON
//  取出来写成文件（系统分享面板 → 存储到「文件」），或者从「文件」里挑一份 JSON
//  写回 localStorage 再刷新页面。
//

#import "saves.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kSaveKey = @"ip-please-save-v1";
static NSString *const kSaveFormat = @"ip-please-save";

@interface SaveManager () <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, weak) WKWebView *webView;
@end

@implementation SaveManager

+ (instancetype)managerWithViewController:(UIViewController *)host webView:(WKWebView *)webView {
    SaveManager *m = [[SaveManager alloc] init];
    m.host = host;
    m.webView = webView;
    return m;
}

#pragma mark - 菜单

- (void)presentMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"存档"
                                                                  message:@"进度存在本机，卸载或重签会一起清掉。建议导出备份。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出存档到文件"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) { [weakSelf exportSave]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从文件导入存档"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) { [weakSelf importSave]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.host.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.host.view.bounds),
                                                                   60, 1, 1);
        sheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self.host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 导出

- (void)exportSave {
    NSString *probe = [NSString stringWithFormat:
        @"(function(){try{var v=localStorage.getItem('%@');return v||'';}catch(e){return '';}})()",
        kSaveKey];

    __weak typeof(self) weakSelf = self;
    [self.webView evaluateJavaScript:probe completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSString *raw = [result isKindOfClass:[NSString class]] ? (NSString *)result : @"";
        if (raw.length == 0) {
            [self alertTitle:@"还没有存档"
                     message:@"玩到第 2 天才会有存档。这一局还没开始，没什么可导出的。"];
            return;
        }

        NSError *jsonError = nil;
        id saveObj = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                     options:0
                                                       error:&jsonError];
        if (![saveObj isKindOfClass:[NSDictionary class]]) {
            [self alertTitle:@"导出失败" message:@"本机存档不是合法的 JSON，无法导出。"];
            return;
        }

        static NSISO8601DateFormatter *iso = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            iso = [[NSISO8601DateFormatter alloc] init];
            iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        });

        NSDictionary *wrapper = @{
            @"format": kSaveFormat,
            @"version": @1,
            @"game": @"IP, PLEASE",
            @"exportedAt": [iso stringFromDate:[NSDate date]],
            @"save": saveObj,
        };

        NSData *out = [NSJSONSerialization dataWithJSONObject:wrapper
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:NULL];
        if (!out) {
            [self alertTitle:@"导出失败" message:@"存档序列化失败。"];
            return;
        }

        NSInteger day = [saveObj[@"day"] isKindOfClass:[NSNumber class]] ? [saveObj[@"day"] integerValue] : 0;
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyyMMdd-HHmm";
        NSString *name = [NSString stringWithFormat:@"ip-please-save-day%ld-%@.json",
                          (long)day, [df stringFromDate:[NSDate date]]];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        if (![out writeToFile:path atomically:YES]) {
            [self alertTitle:@"导出失败" message:@"写临时文件失败，可能是空间不足。"];
            return;
        }

        UIActivityViewController *share = [[UIActivityViewController alloc]
                                           initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                           applicationActivities:nil];
        share.excludedActivityTypes = @[UIActivityTypeAssignToContact];
        if (share.popoverPresentationController) {
            share.popoverPresentationController.sourceView = self.host.view;
            share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.host.view.bounds),
                                                                        60, 1, 1);
            share.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        [self.host presentViewController:share animated:YES completion:nil];
    }];
}

#pragma mark - 导入

- (void)importSave {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypeText]
                                                                  asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    [self.host presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
        didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (data.length == 0) {
        [self showResult:@"导入失败" message:@"这个文件读不出来。" delay:0.4];
        return;
    }

    NSError *jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        [self showResult:@"" message:@"这个文件不是存档 JSON。" delay:0.4];
        return;
    }

    NSDictionary *dict = (NSDictionary *)parsed;
    NSDictionary *save = [dict[@"save"] isKindOfClass:[NSDictionary class]] ? dict[@"save"] : dict;

    NSNumber *day = [save[@"day"] isKindOfClass:[NSNumber class]] ? save[@"day"] : nil;
    if (!day) {
        [self showResult:@"" message:@"文件里没有 day 字段，不像是 IP, PLEASE 的存档。" delay:0.4];
        return;
    }

    NSData *compact = [NSJSONSerialization dataWithJSONObject:save options:0 error:NULL];
    NSString *json = compact ? [[NSString alloc] initWithData:compact encoding:NSUTF8StringEncoding] : nil;
    if (!json) {
        [self showResult:@"" message:@"存档无法解析。" delay:0.4];
        return;
    }

    NSString *js = [NSString stringWithFormat:
        @"(function(){try{localStorage.setItem('%@', %@);return 'ok';}catch(e){return 'ERR:'+e.message;}})()",
        kSaveKey, [self jsStringLiteral:json]];

    __weak typeof(self) weakSelf = self;
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL ok = [result isKindOfClass:[NSString class]] && [result isEqualToString:@"ok"];
        if (!ok) {
            NSString *detail = [result isKindOfClass:[NSString class]] ? result : @"未知错误";
            [self showResult:@"导入失败" message:detail delay:0.4];
            return;
        }
        NSInteger d = day.integerValue;
        NSString *note = d <= 1 ? @"（这份存档在第 1 天，游戏会从头开始）" : @"";
        [self showResult:@"导入成功"
                 message:[NSString stringWithFormat:@"已恢复到第 %ld 天%@，正在重新载入。", (long)d, note]
                   delay:0.4
                  reload:YES];
    }];
}

- (NSString *)jsStringLiteral:(NSString *)text {
    NSMutableString *out = [NSMutableString stringWithString:@"'"];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\'' || c == '\\') {
            [out appendFormat:@"\\%C", c];
        } else if (c == '\n') {
            [out appendString:@"\\n"];
        } else if (c == '\r') {
            [out appendString:@"\\r"];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"'"];
    return out;
}

#pragma mark - 提示

- (void)alertTitle:(NSString *)title message:(NSString *)message {
    [self showResult:title message:message delay:0 reload:NO];
}

- (void)showResult:(NSString *)title message:(NSString *)message delay:(NSTimeInterval)delay {
    [self showResult:title message:message delay:delay reload:NO];
}

- (void)showResult:(NSString *)title message:(NSString *)message
             delay:(NSTimeInterval)delay reload:(BOOL)reload {
    void (^present)(void) = ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a) {
            if (reload) [self.webView reload];
        }]];
        [self.host presentViewController:alert animated:YES completion:nil];
    };
    if (delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), present);
    } else {
        present();
    }
}

@end
