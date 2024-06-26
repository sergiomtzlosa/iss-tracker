#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TimeFormatter : NSObject

/// e.g. "Oct 19, 2026, 18:32:10" in the user's locale/time zone.
+ (NSString *)localDateTimeStringFromTimestamp:(NSTimeInterval)timestamp;

/// e.g. "18:32:10 UTC".
+ (NSString *)utcTimeStringFromTimestamp:(NSTimeInterval)timestamp;

/// e.g. "Oct 19, 18:32" for compact table rows.
+ (NSString *)shortDateTimeStringFromTimestamp:(NSTimeInterval)timestamp;

/// e.g. "1,234 km" with locale grouping.
+ (NSString *)distanceStringFromKilometers:(double)kilometers;

+ (NSString *)numberStringFromValue:(double)value fractionDigits:(NSInteger)digits;

@end

NS_ASSUME_NONNULL_END
