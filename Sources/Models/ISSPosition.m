#import "ISSPosition.h"

@implementation ISSPosition

+ (instancetype)positionWithJSON:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id lat = json[@"latitude"];
    id lon = json[@"longitude"];
    if (!lat || !lon) {
        return nil;
    }
    ISSPosition *position = [[ISSPosition alloc] init];
    position.latitude = [lat doubleValue];
    position.longitude = [lon doubleValue];
    position.altitude = [json[@"altitude"] doubleValue];
    position.velocity = [json[@"velocity"] doubleValue];
    position.timestamp = [json[@"timestamp"] doubleValue];
    NSString *visibility = json[@"visibility"];
    position.visibility = [visibility isKindOfClass:[NSString class]] ? visibility : @"unknown";
    return position;
}

+ (instancetype)positionWithCoordinate:(CLLocationCoordinate2D)coordinate
                             timestamp:(NSTimeInterval)timestamp {
    ISSPosition *position = [[ISSPosition alloc] init];
    position.latitude = coordinate.latitude;
    position.longitude = coordinate.longitude;
    position.timestamp = timestamp;
    position.visibility = @"unknown";
    return position;
}

- (CLLocationCoordinate2D)coordinate {
    return CLLocationCoordinate2DMake(self.latitude, self.longitude);
}

- (NSString *)visibilityDisplayName {
    if ([self.visibility isEqualToString:@"daylight"]) {
        return @"Daylight";
    }
    if ([self.visibility isEqualToString:@"nighttime"]) {
        return @"Nighttime";
    }
    if ([self.visibility isEqualToString:@"eclipsed"]) {
        return @"Eclipsed";
    }
    return @"Unknown";
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<ISSPosition %.2f, %.2f @ %.0f>",
            self.latitude, self.longitude, self.timestamp];
}

@end
