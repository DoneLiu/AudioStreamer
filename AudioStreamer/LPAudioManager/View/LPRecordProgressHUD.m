//
//  LPRecordProgressHUD.m
//  ShuaLian
//
//  Created by Done.L on 2017/8/15.
//  Copyright © 2017年 EvanCai. All rights reserved.
//

#import "LPRecordProgressHUD.h"

static LPRecordStatus kRecordStatus;
static NSInteger kRemainTime;

@interface LPRecordProgressHUD ()

@property (nonatomic, strong) UIWindow *overlayWindow;

@property (nonatomic, strong) UILabel *message;

@property (nonatomic, strong) UIImageView *micPhoneVolume;

@end

@implementation LPRecordProgressHUD

+ (LPRecordProgressHUD *)sharedView {
    static dispatch_once_t once;
    static LPRecordProgressHUD *sharedView;
    dispatch_once(&once, ^ {
        sharedView = [[LPRecordProgressHUD alloc] initWithFrame:CGRectMake((screenWidth - 145) / 2, (screenHeight - 145) / 2, 145, 145)];
        sharedView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        sharedView.layer.cornerRadius = 5.f;
        sharedView.layer.masksToBounds = YES;
    });
    return sharedView;
}

+ (void)show {
    [[LPRecordProgressHUD sharedView] show];
}

+ (void)setRecordStatus:(LPRecordStatus)status {
    kRecordStatus = status;
    NSString *title = @"取消";
    NSString *imgName;
    switch (status) {
        case LPRecordStatusRecording:
            imgName = @"icon_chat_voice_record_0";
            if (kRemainTime > 0) {
                title = [NSString stringWithFormat:@"还可以说%ld秒", kRemainTime];
            } else {
                title = @"手指上滑，取消发送";
            }
            break;
            
        case LPRecordStatusLooseToCancel:
            imgName = @"icon_chat_voice_record_cancel";
            title = @"松开手指取消发送";
            break;
            
        case LPRecordStatusTooShort:
            title = @"说话时间太短";
            imgName = @"icon_chat_voice_record_tooshort";
            break;
            
        case LPRecordStatusSuccess:
            title = @"完成";
            break;
            
        case LPRecordStatusCancel:
            break;
            
        default:
            break;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (imgName) {
            [LPRecordProgressHUD sharedView].micPhoneVolume.image = [UIImage imageNamed:imgName];
        }
        
        [LPRecordProgressHUD sharedView].message.text = title;
        if (status & (LPRecordStatusCancel | LPRecordStatusTooShort | LPRecordStatusSuccess)) {
            [[LPRecordProgressHUD sharedView] dismiss:title];
        }
    });
}

+ (void)setRemainTime:(NSInteger)time {
    kRemainTime = MAX(MIN(time, 11), -1);
    if (kRecordStatus == LPRecordStatusRecording) {
        [LPRecordProgressHUD sharedView].message.text = [NSString stringWithFormat:@"还可以说%ld秒", kRemainTime];
    }
}

+ (void)recordVolumeChangeLevel:(NSInteger)level {
    if (kRecordStatus == LPRecordStatusRecording) {
        UIImageView *micPhoneImageView = [LPRecordProgressHUD sharedView].micPhoneVolume;
        micPhoneImageView.image = [UIImage imageNamed:[NSString stringWithFormat:@"icon_chat_voice_record_%ld", level]];
    }
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        [LPRecordProgressHUD sharedView].hidden = NO;
        kRecordStatus = LPRecordStatusRecording;
        
        if (!self.superview) {
            [self.overlayWindow addSubview:self];
        }
        
        [self addSubview:self.micPhoneVolume];
        [self addSubview:self.message];
        
        [UIView animateWithDuration:0.5f
                              delay:0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             self.alpha = 1;
                         }
                         completion:nil];
        
        [self setNeedsDisplay];
    });
}

- (void)dismiss:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        kRemainTime = -1;
        CGFloat timeLonger = 0;
        if ([title isEqualToString:@"说话时间太短"]) {
            timeLonger = 0.6;
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeLonger * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [_micPhoneVolume removeFromSuperview];
            _micPhoneVolume = nil;
            
            [_message removeFromSuperview];
            _message = nil;
            
            NSMutableArray *windows = [[NSMutableArray alloc] initWithArray:[UIApplication sharedApplication].windows];
            [windows removeObject:_overlayWindow];
            _overlayWindow = nil;
            
            [LPRecordProgressHUD sharedView].hidden = YES;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:LPChatUUVoiceHUDBtnEnableNotification object:nil];
            
            [windows enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(UIWindow *window, NSUInteger idx, BOOL *stop) {
                if([window isKindOfClass:[UIWindow class]] && window.windowLevel == UIWindowLevelNormal) {
                    [window makeKeyWindow];
                    *stop = YES;
                }
            }];
        });
    });
}

- (UIImageView *)micPhoneVolume {
    if (!_micPhoneVolume) {
        _micPhoneVolume = [[UIImageView alloc] initWithFrame:CGRectMake((self.width - 36)/2, (self.height - 60 - 16 - 20) / 2, 36, 60)];
        _micPhoneVolume.contentMode = UIViewContentModeScaleAspectFit;
        _micPhoneVolume.image = [UIImage imageNamed:@"icon_chat_voice_record_0"];
    }
    return _micPhoneVolume;
}

- (UILabel *)message {
    if (!_message) {
        _message = [[UILabel alloc]initWithFrame:CGRectMake(0, _micPhoneVolume.bottom + 16, self.width, 20)];
        self.message.text = @"手向上滑，取消发送";
        self.message.textAlignment = NSTextAlignmentCenter;
        self.message.font = [UIFont boldSystemFontOfSize:13.f];
        self.message.textColor = LPColorWhite;
    }
    return _message;
}

- (UIWindow *)overlayWindow {
    if(!_overlayWindow) {
        _overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _overlayWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _overlayWindow.userInteractionEnabled = YES;
        [_overlayWindow makeKeyAndVisible];
    }
    return _overlayWindow;
}

@end
