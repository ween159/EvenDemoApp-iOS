//
//  PcmConverter.h
//  Runner
//
//  Created by Hawk on 2024/3/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PcmConverter : NSObject
-(NSMutableData *)decode: (NSData *)lc3data;
@end

NS_ASSUME_NONNULL_END
