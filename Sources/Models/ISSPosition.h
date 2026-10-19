#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A single sampled ISS position returned by the wheretheiss.at API.
@interface ISSPosition : NSObject

@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
@property (nonatomic) double altitude;      // kilometers
@property (nonatomic) double velocity;      // km/h
@property (nonatomic) NSTimeInterval timestamp; // seconds since 1970 (UTC)
@property (nonatomic, copy) NSString *visibility; // daylight / nighttime / eclipsed

@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;

+ (nullable instancetype)positionWithJSON:(NSDictionary *)json;
+ (instancetype)positionWithCoordinate:(CLLocationCoordinate2D)coordinate
                             timestamp:(NSTimeInterval)timestamp;

- (NSString *)visibilityDisplayName;

@end

NS_ASSUME_NONNULL_END
