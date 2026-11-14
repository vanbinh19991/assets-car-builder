// TFAppCheck — khoá hạn dùng trong game (web Upload TestFlight tự chèn vào mọi game lúc ký).
// Mở game / quay lại game / mỗi 10 phút: hỏi web xem link game còn hạn không.
//   - "ok"      : chơi bình thường
//   - "warn"    : hiện thông báo 1 lần (sắp hết hạn / đang trong 24 giờ đếm ngược), vẫn cho chơi
//   - "expired" : hiện thông báo + nút "Gia hạn" (mở web) rồi TẮT game
// Mất mạng / web không trả lời -> cho chơi tiếp (không khoá oan).
// Địa chỉ web + mã link đọc từ Info.plist của game: TFCheckURL, TFCheckToken (web ghi vào lúc ký).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TFAppCheck : NSObject
@end

static BOOL tfShowing = NO;
static BOOL tfWarned = NO;

@implementation TFAppCheck

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [TFAppCheck check];
        [NSTimer scheduledTimerWithTimeInterval:600 target:[TFAppCheck class] selector:@selector(check) userInfo:nil repeats:YES];
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) { [TFAppCheck check]; }];
}

+ (void)check {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *base = info[@"TFCheckURL"];
    NSString *token = info[@"TFCheckToken"];
    if (![base isKindOfClass:[NSString class]] || ![token isKindOfClass:[NSString class]] || base.length == 0 || token.length == 0) return;
    NSString *build = [info[@"CFBundleVersion"] isKindOfClass:[NSString class]] ? info[@"CFBundleVersion"] : @"";
    NSString *b = [build stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/pub/check?t=%@&b=%@", base, token, b]];
    if (!url) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) return; // mất mạng / web không trả lời -> cho chơi tiếp
        id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![j isKindOfClass:[NSDictionary class]]) return;
        NSString *status = j[@"status"];
        NSString *msg = [j[@"message"] isKindOfClass:[NSString class]] ? j[@"message"] : @"";
        NSString *link = [j[@"link"] isKindOfClass:[NSString class]] ? j[@"link"] : nil;
        if (![status isKindOfClass:[NSString class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([status isEqualToString:@"expired"]) {
                [TFAppCheck alert:msg link:link critical:YES tries:0];
            } else if ([status isEqualToString:@"warn"] && !tfWarned) {
                tfWarned = YES;
                [TFAppCheck alert:msg link:link critical:NO tries:0];
            }
        });
    }] resume];
}

+ (UIViewController *)topViewController {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (!win && ((UIWindowScene *)scene).windows.count > 0) win = ((UIWindowScene *)scene).windows.firstObject;
            if (win) break;
        }
    }
    if (!win) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        win = [UIApplication sharedApplication].keyWindow;
        if (!win) win = [UIApplication sharedApplication].windows.firstObject;
#pragma clang diagnostic pop
    }
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)alert:(NSString *)msg link:(NSString *)link critical:(BOOL)critical tries:(int)tries {
    if (tfShowing) return;
    UIViewController *vc = [TFAppCheck topViewController];
    if (!vc) {
        // game chưa có màn hình -> thử lại sau 1 giây (tối đa 60 lần); hết hạn mà vẫn không có màn hình thì tắt luôn
        if (tries < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [TFAppCheck alert:msg link:link critical:critical tries:tries + 1];
            });
        } else if (critical) {
            exit(0);
        }
        return;
    }
    tfShowing = YES;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:(critical ? @"Link game đã hết hạn" : @"Thông báo")
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    NSURL *u = link.length ? [NSURL URLWithString:link] : nil;
    if (u) {
        [a addAction:[UIAlertAction actionWithTitle:@"Gia hạn" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok) {
                tfShowing = NO;
                if (critical) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
                }
            }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:(critical ? @"Thoát" : @"Đã hiểu")
                                          style:(critical ? UIAlertActionStyleDestructive : UIAlertActionStyleCancel)
                                        handler:^(UIAlertAction *act) {
        tfShowing = NO;
        if (critical) exit(0);
    }]];
    [vc presentViewController:a animated:YES completion:nil];
}

@end
