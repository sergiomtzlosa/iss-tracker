#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@class LocationService;

@protocol LocationServiceDelegate <NSObject>
- (void)locationService:(LocationService *)service didUpdateLocation:(CLLocation *)location;
- (void)locationService:(LocationService *)service didFailWithError:(NSError *)error;
@end

@interface LocationService : NSObject

@property (nonatomic, weak) id<LocationServiceDelegate> delegate;

/// Requests "when in use" authorization if needed and then a single fix.
- (void)requestCurrentLocation;

@end

NS_ASSUME_NONNULL_END
