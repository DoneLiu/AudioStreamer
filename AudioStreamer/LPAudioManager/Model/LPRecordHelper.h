//
//  LPRecordHelper.h
//  ShuaLian
//
//  Created by Done.L on 2017/8/15.
//  Copyright © 2017年 EvanCai. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LPRecordHelper : NSObject

/**
 **	@description    获取录音文件名(以当前时间戳格式生成的字符串)
 **	@returns        录音文件名
 */
+ (NSString *)recordSavedPath;

/**
 ** @description    录音文件是否存在
 **	@param          录音文件路径
 **	@returns        结果
 */
+ (BOOL)fileExistsAtPath:(NSString *)path;

/**
 ** @description    创建文件
 **	@param          录音文件路径
 **	@returns        结果
 */
+ (BOOL)createFileAtPath:(NSString *)path;

/**
 ** @description    删除文件
 **	@param          录音文件路径
 **	@returns        结果
 */
+ (BOOL)deleteFileAtPath:(NSString *)path;

/**
 ** @description    录音tmpCaf文件路径
 */
+ (NSString *)tmpCafLocalPath;

/**
 ** @description    录音tmpMp3文件路径
 */
+ (NSString *)tmpMp3LocalPath;

/**
 ** @description    录音参数设置字典
 **	@returns        设置参数
 */
+ (NSDictionary *)getRecordSettings;

@end
