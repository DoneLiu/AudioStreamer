//
//  LPRecordManager.h
//  ShuaLian
//
//  Created by Done.L on 2017/8/15.
//  Copyright © 2017年 EvanCai. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum : NSUInteger {
    REMOTE_AUDIO_STATE_BUFFERING = 0,   // 正在缓冲
    REMOTE_AUDIO_STATE_PLAYING,         // 正在播放
    REMOTE_AUDIO_STATE_PAUSE,           // 播放暂停
    REMOTE_AUDIO_STATE_STOP             // 播放停止
} REMOTE_AUDIO_STATE;

@protocol LPRecordManagerDelegate <NSObject>

@optional

/**
 * 音量变化
 */
- (void)lp_recordVolumeChanged:(NSInteger)volume;

/**
 * 录音剩余时长
 */
- (void)lp_recordTimeRemain:(NSInteger)remain;

/**
 * 录音完成
 */
- (void)lp_recordCompleteWithData:(NSData *)recordData recordDuration:(NSInteger)recordDuration;

/**
 * 录音失败
 */
- (void)lp_recordFail;

/**
 * 远程流媒体状态
 */
- (void)lp_remoteAudioStateChanged:(REMOTE_AUDIO_STATE)state;

/**
 * 远程流媒体进度检测
 */
- (void)lp_remoteAudioProgressChanged:(double)progress duration:(double)duration;

@end

@interface LPRecordManager : NSObject

/**
 * 单例
 */
+ (instancetype)manager;

@property (nonatomic, assign) id<LPRecordManagerDelegate> delegate;

/**
 * 播放模式 (0 表示扬声器，1 表示听筒)
 */
@property (nonatomic, assign) BOOL recordPlayMode;

/**
 * 是否正在播放录音
 */
@property (nonatomic, assign, readonly) BOOL isPlaying;

/**
 扩展变量 (为了刷脸添加)
 */
@property (nonatomic, assign) long messageId;

#pragma mark - 录音

/**
 * 开始录音
 */
- (void)startRecord;

/**
 * 完成录音（包括录音时长不够的情况）
 */
- (void)completeRecord;

/**
 * 取消录音
 */
- (void)cancelRecord;


#pragma mark - 本地录音播放

/*
 * 播放录音（从本地路径播放）
 */
- (void)startPlayRecordWithPath:(NSString *)recordPath completion:(void(^)(BOOL isFinish))completion;

/*
 * 播放录音（从data播放）
 */
- (void)startPlayRecordWithData:(NSData *)data completion:(void(^)(BOOL isFinish))completion;

/*
 * 停止播放
 */
- (void)cancelPlayRecord;

/*
 * 删除录音
 */
- (void)deleteRecordAtPath:(NSString *)path;


#pragma mark - 远程流媒体播放

/**
 播放远程音频
 
 @param remoteURL 音频链接
 */
- (void)startPlayRecordWithRemoteURL:(NSString *)remoteURL;

/**
 继续播放远程音频
 */
- (void)reStartPlayRemoteAudio;

/**
 暂停播放远程音频
 */
- (void)pausePlayRemoteAudio;

/**
 停止播放远程音频
 */
- (void)cancelPlayRemoteAudio;

/**
 停止播放远程音频
 */
- (void)remoteAudioSeekToTime:(float)time;

#pragma mark - 停止语音服务

- (void)stopAudioService;

@end
