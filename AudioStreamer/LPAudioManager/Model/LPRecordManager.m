//
//  LPRecordManager.m
//  ShuaLian
//
//  Created by Done.L on 2017/8/15.
//  Copyright © 2017年 EvanCai. All rights reserved.
//

#import "LPRecordManager.h"

#ifdef DEBUG
#   define DDLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define DDLog(...)
#endif

#import "lame.h"
#import <AVFoundation/AVFoundation.h>

#import "LPRecordHelper.h"
#import "AudioStreamer.h"

static NSInteger kRecordDuration = 0;

@interface LPRecordManager () <AVAudioRecorderDelegate, AVAudioPlayerDelegate>

// 录音器
@property (nonatomic, strong) AVAudioRecorder *recorder;

// 播放器
@property (nonatomic, strong) AVAudioPlayer *player;

// 流媒体播放器
@property (nonatomic, strong) AudioStreamer *streamer;

// 录音计时器
@property (nonatomic, strong) NSTimer *recordTimer;

// 音量检测
@property (nonatomic, strong) NSTimer *meterTimer;

// 远程音频进度检测
@property (nonatomic, strong) NSTimer *remoteProgressUpdateTimer;

// 本地播放完成回调
@property (nonatomic, copy) void(^isPlayFinishBlock)(BOOL);

@end

@implementation LPRecordManager

+ (instancetype)manager {
    static LPRecordManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 输出设备变更的通知
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outputDeviceChanged:) name:AVAudioSessionRouteChangeNotification object:[AVAudioSession sharedInstance]];
    }
    return self;
}

- (BOOL)isPlaying {
    return _player ? _player.isPlaying : NO;
}

#pragma mark - 停止语音服务

- (void)stopAudioService {
    [[LPRecordManager manager] cancelRecord];
    [[LPRecordManager manager] cancelPlayRecord];
    [LPRecordManager manager].delegate = nil;
    [[LPRecordManager manager] cancelPlayRemoteAudio];
}

#pragma mark - 录音

/**
 * 获取录音权限
 */
- (void)fetchMicroPhoneRight:(void(^)(BOOL haveRecordRight))completion {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    BOOL haveRecordRight = NO;
    switch (status) {
        case AVAuthorizationStatusNotDetermined: {
            if([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
                [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {}];
            }
        }
            break;
            
        case AVAuthorizationStatusRestricted:
        case AVAuthorizationStatusDenied: {
            [[[UIAlertView alloc] initWithTitle:@"无法录音" message:@"是否允许访问麦克风" delegate:nil cancelButtonTitle:@"我知道了" otherButtonTitles:nil] show];
        }
            break;
            
        case AVAuthorizationStatusAuthorized: {
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error:&error];
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            
            haveRecordRight = YES;
        }
            break;
            
        default:
            break;
    }
    
    completion(haveRecordRight);
}

/**
 * 开始录音
 */
- (void)startRecord {
#if TARGET_IPHONE_SIMULATOR
    DDLog(@"开始录音！！！");
    
    // 初始化录音器
    [self initAudioRecorder];
    
    [_recorder record];
#else
    [self fetchMicroPhoneRight:^(BOOL haveRecordRight) {
        if (haveRecordRight) {
            DDLog(@"开始录音！！！");
            
            // 初始化录音器
            [self initAudioRecorder];
            
            [_recorder record];
        } else {
            DDLog(@"没有录音权限！！！");
        }
    }];
#endif
}

/**
 * 完成录音（包括录音时长不够的情况）
 */
- (void)completeRecord {
    double duration = 0;
    duration = (double)_recorder.currentTime;
    
    if (duration > 1.f) {
        // 转换录音格式
        [self record_PCMtoMP3];
    } else {
        // 提示
        if ([_delegate respondsToSelector:@selector(lp_recordFail)]) {
            [_delegate lp_recordFail];
        }
    }
    
    [self cancelRecord];
}

/**
 * 取消录音
 */
- (void)cancelRecord {
    [_recorder deleteRecording];
    [self destroyAudioRecorder];
}

// 销毁录音器
- (void)destroyAudioRecorder {
    if (_recorder) {
        if ([_recorder isRecording]) {
            [_recorder stop];
        }
        _recorder = nil;
        
        // 销毁定时器
        [_recordTimer invalidate];
        _recordTimer = nil;
        
        [_meterTimer invalidate];
        _meterTimer = nil;
        
        // 重置录音计数
        kRecordDuration = 0;
        
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
    }
}

// 初始化录音器
- (BOOL)initAudioRecorder {
    // 如果有播放器，先停止播放器
    [self destroyAudioPlayer];
    
    // 销毁可能存在的录音器
    [self destroyAudioRecorder];
    
    NSError *recorderSetupError = nil;
    
    // 录音本地缓存地址
    NSURL *tmpUrl = [NSURL fileURLWithPath:[LPRecordHelper tmpCafLocalPath]];
    
    // 配置录音参数
    NSDictionary *settings = [LPRecordHelper getRecordSettings];
    
    _recorder = [[AVAudioRecorder alloc] initWithURL:tmpUrl settings:settings error:&recorderSetupError];
    _recorder.meteringEnabled = YES;
    _recorder.delegate = self;
    
    // 录音计时器
    _recordTimer = [NSTimer scheduledTimerWithTimeInterval:1.f target:self selector:@selector(recordTimerAction) userInfo:nil repeats:YES];
    
    // 音量检测
    _meterTimer = [NSTimer scheduledTimerWithTimeInterval:0.01f target:self selector:@selector(volumeDetectorAction) userInfo:nil repeats:YES];
    
    if (recorderSetupError) {
        DDLog(@"recorderSetupError = %@", recorderSetupError);
    }
    
    // 录音器是否能准备录音
    return _recorder && [_recorder prepareToRecord];
}

// 录音器计时
- (void)recordTimerAction {
    kRecordDuration ++;
    
    if (kRecordDuration >= 60) {
        // 完成录音
        [self completeRecord];
    } else if (kRecordDuration >= 50) {
        // 提示剩余录音时长
        if ([_delegate respondsToSelector:@selector(lp_recordTimeRemain:)]) {
            [_delegate lp_recordTimeRemain:60 - kRecordDuration];
        }
    }
}

// 环境音量检测
- (void)volumeDetectorAction {
    if ([_recorder isRecording]) {
        [_recorder updateMeters];
        
        float lowPassResults;
        float minDecibels = -80.f;
        float decibels = [_recorder averagePowerForChannel:0];
        
        if (decibels < minDecibels) {
            lowPassResults = 0.0f;
        } else if (decibels >= 0.0f) {
            lowPassResults = 1.0f;
        } else {
            float root = 2.0f;
            float minAmp  = powf(10.0f, 0.05f * minDecibels);
            float inverseAmpRange = 1.0f / (1.0f - minAmp);
            float amp = powf(10.0f, 0.05f * decibels);
            float adjAmp = (amp - minAmp) * inverseAmpRange;
            
            lowPassResults = powf(adjAmp, 1.0f / root);
        }
        DDLog(@"%f",lowPassResults);
        
        NSInteger level = 0;
        if (lowPassResults <= 0.1) {
            level = 0;
        } else if (0.1 < lowPassResults <= 0.27) {
            level = 1;
        } else if (0.27 < lowPassResults <= 0.34) {
            level = 2;
        } else if (0.34 < lowPassResults <= 0.48) {
            level = 3;
        } else if (0.48 < lowPassResults <= 0.55) {
            level = 4;
        } else if (0.55 < lowPassResults <= 0.66) {
            level = 5;
        } else if (0.66 < lowPassResults <= 0.75) {
            level = 6;
        } else {
            level = 7;
        }
        
        if ([_delegate respondsToSelector:@selector(lp_recordVolumeChanged:)]) {
            [_delegate lp_recordVolumeChanged:level];
        }
    }
}

- (void)record_PCMtoMP3 {
    NSString *cafPath = [LPRecordHelper tmpCafLocalPath];
    NSString *mp3Path = [LPRecordHelper tmpMp3LocalPath];
    
    // 删除旧的mp3缓存
    [LPRecordHelper deleteFileAtPath:mp3Path];
    
    DDLog(@"MP3转换开始!!!");
    
    @try {
        unsigned long read;
        unsigned long write;
        
        FILE *pcm = fopen([cafPath cStringUsingEncoding:1], "rb");  // source 被转换的音频文件位置
        fseek(pcm, 4 * 1024, SEEK_CUR);                             // 跳过文件头
        FILE *mp3 = fopen([mp3Path cStringUsingEncoding:1], "wb");  // output 输出生成的mp3文件位置
        
        const int PCM_SIZE = 8192; // 8M
        const int MP3_SIZE = 8192; // 8M
        short int pcm_buffer[PCM_SIZE * 2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, 11025.0);
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        do {
            read = fread(pcm_buffer, 2 * sizeof(short int), PCM_SIZE, pcm);
            if (read == 0)
                write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            else
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, (int)read, mp3_buffer, MP3_SIZE);
            
            fwrite(mp3_buffer, write, 1, mp3);
            
        } while (read != 0);
        
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
    }
    
    @catch (NSException *exception) {
        DDLog(@"%@",[exception description]);
    }
    
    // 删除caf缓存
    [LPRecordHelper deleteFileAtPath:cafPath];
    
    DDLog(@"MP3转换结束!!!");
    
    if (_delegate && [_delegate respondsToSelector:@selector(lp_recordCompleteWithData:recordDuration:)]) {
        NSData *recordData = [NSData dataWithContentsOfFile:mp3Path];
        [_delegate lp_recordCompleteWithData:recordData recordDuration:kRecordDuration];
    }
}

#pragma mark - 本地录音播放

/**
 * 播放录音（从本地路径播放）
 */
- (void)startPlayRecordWithPath:(NSString *)recordPath completion:(void (^)(BOOL))completion {
    if (!recordPath) {
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:recordPath options:NSDataReadingMappedIfSafe error:nil];
    
    [self startPlayRecordWithData:data completion:completion];
}

/**
 * 播放录音（从data播放）
 */
- (void)startPlayRecordWithData:(NSData *)data completion:(void(^)(BOOL isFinish))completion {
    // 初始化播放器
    [self initAudioPlayer:data];
    
    _isPlayFinishBlock = completion;
    
    BOOL canPlay = [_player play];
    
    // 处理不能成功播放的情况
    if (!canPlay) {
        [self performSelector:@selector(stopPlayingUnusefulRecord) withObject:nil afterDelay:0.6f];
    }
}

- (void)stopPlayingUnusefulRecord {
    if (_isPlayFinishBlock) {
        _isPlayFinishBlock(YES);
    }
}

/**
 * 停止播放
 */
- (void)cancelPlayRecord {
    [self destroyAudioPlayer];
}

// 销毁播放器
- (void)destroyAudioPlayer {
    if (_player) {
        if ([_player isPlaying]) {
            [_player stop];
        }
        
        [self closeProximityMonitoringEnabled];
        
        _player = nil;
        
        _isPlayFinishBlock = nil;
    }
}

// 初始化播放器
- (BOOL)initAudioPlayer:(NSData *)data {
    // 如果有录音器，先停止录音器
    [self destroyAudioRecorder];
    
    // 销毁可能存在的播放器
    [self destroyAudioPlayer];
    
    // 声音播放模式
    if (_recordPlayMode) {
        // 听筒
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    } else {
        // 扬声器
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        
        // 扬声器模式下才需要打开光感传感器监听
        [self openProximityMonitoringEnabled];
    }
    
    NSError *playError = nil;
    
    _player = [[AVAudioPlayer alloc] initWithData:data error:&playError];
    _player.delegate = self;
    
    if (playError) {
        DDLog(@"playError = %@", playError);
    }
    
    // 播放器是否能准备播放
    return _player && [_player prepareToPlay];
}

/**
 * 删除录音
 */
- (void)deleteRecordAtPath:(NSString *)path {
    if ([LPRecordHelper fileExistsAtPath:path]) {
        [LPRecordHelper deleteFileAtPath:path];
    }
}

#pragma mark - Proximity Monitoring Setting

- (void)openProximityMonitoringEnabled {
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sensorStateChanged:) name:UIDeviceProximityStateDidChangeNotification object:nil];
}

- (void)closeProximityMonitoringEnabled {
    [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceProximityStateDidChangeNotification object:nil];
}

#pragma mark - Notification

// 光感触发器，调整语音播放方式
- (void)sensorStateChanged:(NSNotification *)notify {
    if ([[UIDevice currentDevice] proximityState]) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    } else {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    }
}

// 输出设备变更通知
- (void)outputDeviceChanged:(NSNotification *)notification {
    if (notification && notification.userInfo) {
        NSUInteger routeChangeReason = [[notification.userInfo objectForKey:AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
        
        switch (routeChangeReason) {
            case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
                [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
            }
                break;
                
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
                [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
            }
                break;
                
            case AVAudioSessionRouteChangeReasonCategoryChange:
                break;
                
            case AVAudioSessionRouteChangeReasonOverride: {
                if ([self hasHeadphone]) {
                    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
                } else {
                    if (_recordPlayMode) {
                        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
                    } else {
                        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
                    }
                }
            }
                break;
                
            default:
                break;
        }
    }
}

/**
 * 获取设备状态,是否插入耳机,如果插入耳机,返回YES
 */
- (BOOL)hasHeadphone {
    NSArray *inputsArys = [[AVAudioSession sharedInstance] availableInputs];
    for (AVAudioSessionPortDescription *portDsecription in inputsArys) {
        if ([portDsecription.portType isEqualToString:@"MicrophoneWired"]) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - AVAudioRecorderDelegate and AVAudioPlayerDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    DDLog(@"录音完成！！！");
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    DDLog(@"录音错误！！！ = %@", error);
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (_isPlayFinishBlock) {
        DDLog(@"播放完成！！！");
        _isPlayFinishBlock(flag);
    }
    
    // 停止播放
    [self cancelPlayRecord];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    DDLog(@"播放错误！！！ = %@", error);
}


#pragma mark - 远程流媒体播放

/*
 * 播放录音（从远程URL播放）
 */
- (void)startPlayRecordWithRemoteURL:(NSString *)remoteURL {
    // 初始化流媒体播放器
    [self initAudioStreamerPlayerWithRemoteURL:remoteURL];
    
    if (_streamer) {
        [_streamer start];
    }
}

- (void)reStartPlayRemoteAudio {
    if (_streamer) {
        [_streamer start];
        
        // 重新开启进度更新计时器
        [_remoteProgressUpdateTimer setFireDate:[NSDate date]];
    }
}

- (void)pausePlayRemoteAudio {
    if (_streamer) {
        [_streamer pause];
        
        // 停止进度更新计时器
        [_remoteProgressUpdateTimer setFireDate:[NSDate distantFuture]];
    }
}

- (void)cancelPlayRemoteAudio {
    [self destroyStreamer];
}

- (void)remoteAudioSeekToTime:(float)time {
    if ([_streamer isPlaying] || [_streamer isPaused]) {
        if (_streamer.duration) {
            [_streamer seekToTime:time];
        }
    }
}

- (void)destroyStreamer {
    if (_streamer) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:ASStatusChangedNotification object:_streamer];
        
        [_remoteProgressUpdateTimer invalidate];
        _remoteProgressUpdateTimer = nil;
        
        [_streamer stop];
        _streamer = nil;
    }
}

- (void)initAudioStreamerPlayerWithRemoteURL:(NSString *)remoteURL {
    // 如果有流媒体播放器，先停止播放器
    [self destroyStreamer];
    
    NSString *escapedValue = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(nil, (CFStringRef)remoteURL, NULL, NULL, kCFStringEncodingUTF8)) ;
    ;
    
    NSURL *url = [NSURL URLWithString:escapedValue];
    _streamer = [[AudioStreamer alloc] initWithURL:url];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioStreamerStatusChanged:) name:ASStatusChangedNotification object:nil];
    
    // 进度检测
    _remoteProgressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1f target:self selector:@selector(remoteAudioProgressUpdate) userInfo:nil repeats:YES];
}

/**
 远程音频播放进度检测
 */
- (void)remoteAudioProgressUpdate {
    if (_streamer.bitRate != 0.0) {
        double progress = _streamer.progress;
        double duration = _streamer.duration;
        
        if (duration > 0) {
            if (self.delegate && [self.delegate respondsToSelector:@selector(lp_remoteAudioProgressChanged:duration:)]) {
                [self.delegate lp_remoteAudioProgressChanged:progress duration:duration];
            }
        } else {
            DDLog(@"远程音频总时长为0!");
        }
    } else {
        
    }
}

/**
 远程播放状态变化检测
 
 @param notify 通知
 */
- (void)audioStreamerStatusChanged:(NSNotification *)notify {
    if ([_streamer isWaiting]) {
        DDLog(@"音频正在缓冲...");
        if (self.delegate && [self.delegate respondsToSelector:@selector(lp_remoteAudioStateChanged:)]) {
            [self.delegate lp_remoteAudioStateChanged:REMOTE_AUDIO_STATE_BUFFERING];
        }
    } else if ([_streamer isPlaying]) {
        DDLog(@"音频正在播放...");
        if (self.delegate && [self.delegate respondsToSelector:@selector(lp_remoteAudioStateChanged:)]) {
            [self.delegate lp_remoteAudioStateChanged:REMOTE_AUDIO_STATE_PLAYING];
        }
    } else if ([_streamer isPaused]) {
        DDLog(@"音频暂停播放...");
        if (self.delegate && [self.delegate respondsToSelector:@selector(lp_remoteAudioStateChanged:)]) {
            [self.delegate lp_remoteAudioStateChanged:REMOTE_AUDIO_STATE_PAUSE];
        }
    } else if ([_streamer isIdle]) {
        DDLog(@"音频播放完成...");
        if (self.delegate && [self.delegate respondsToSelector:@selector(lp_remoteAudioStateChanged:)]) {
            [self.delegate lp_remoteAudioStateChanged:REMOTE_AUDIO_STATE_STOP];
        }
    }
}

@end
