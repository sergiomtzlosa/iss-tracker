#import "TimeFormatter.h"

@implementation TimeFormatter

+ (NSDateFormatter *)localFormatterWithStyle:(NSDateFormatterStyle)dateStyle timeStyle:(NSDateFormatterStyle)timeStyle {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = dateStyle;
    formatter.timeStyle = timeStyle;
    return formatter;
}

+ (NSString *)localDateTimeStringFromTimestamp:(NSTimeInterval)timestamp {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [self localFormatterWithStyle:NSDateFormatterMediumStyle
                                        timeStyle:NSDateFormatterMediumStyle];
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

+ (NSString *)utcTimeStringFromTimestamp:(NSTimeInterval)timestamp {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss 'UTC'";
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

+ (NSString *)shortDateTimeStringFromTimestamp:(NSTimeInterval)timestamp {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MMM d, HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

+ (NSString *)distanceStringFromKilometers:(double)kilometers {
    return [NSString stringWithFormat:@"%@ km", [self numberStringFromValue:kilometers fractionDigits:0]];
}

+ (NSString *)numberStringFromValue:(double)value fractionDigits:(NSInteger)digits {
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = 0;
        formatter.minimumFractionDigits = 0;
    });
    formatter.maximumFractionDigits = MAX(0, digits);
    formatter.minimumFractionDigits = MAX(0, digits);
    return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%.0f", value];
}

@end
