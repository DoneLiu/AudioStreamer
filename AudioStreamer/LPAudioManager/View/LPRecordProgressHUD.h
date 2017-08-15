//
//  LPRecordProgressHUD.h
//  ShuaLian
//
//  Created by Done.L on 2017/8/15.
//  Copyright © 2017年 EvanCai. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, LPRecordStatus) {
    LPRecordStatusTooShort = 1<<1,          // 时间太短了
    LPRecordStatusRecording = 1<<2,         // 正在录音
    LPRecordStatusLooseToCancel = 1<<3,     // 松开手指取消
    LPRecordStatusSuccess = 1<<4,           // 录制完成
    LPRecordStatusCancel = 1<<5             // 取消录制
};

@interface LPRecordProgressHUD : UIView

/**
 显示状态视图
 */
+ (void)show;

/**
 设置录音状态
 
 @param status 录音状态
 */
+ (void)setRecordStatus:(LPRecordStatus)status;

/**
 设置语音剩余时间
 
 @param time 时间最大10秒
 */
+ (void)setRemainTime:(NSInteger)time;

/**
 设置音量大小
 
 @param level 音量等级从小到大，范围[0~7]
 */
+ (void)recordVolumeChangeLevel:(NSInteger)level;

@end
