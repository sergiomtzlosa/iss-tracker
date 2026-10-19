#import "LocationService.h"

@interface LocationService () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic) BOOL waitingForAuthorization;
@end

@implementation LocationService

- (instancetype)init {
    self = [super init];
    if (self) {
        _manager = [[CLLocationManager alloc] init];
        _manager.delegate = self;
        _manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    }
    return self;
}

- (void)requestCurrentLocation {
    CLAuthorizationStatus status = self.manager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        self.waitingForAuthorization = YES;
        [self.manager requestWhenInUseAuthorization];
        return;
    }
    [self startIfAuthorized:status];
}

- (void)startIfAuthorized:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.manager startUpdatingLocation];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        NSError *error = [NSError errorWithDomain:kCLErrorDomain
                                             code:kCLErrorDenied
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        @"Location access is not allowed. Enable it in System Settings › Privacy & Security › Location Services."}];
        [self.delegate locationService:self didFailWithError:error];
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (!location) {
        return;
    }
    [manager stopUpdatingLocation];
    [self.delegate locationService:self didUpdateLocation:location];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [manager stopUpdatingLocation];
    [self.delegate locationService:self didFailWithError:error];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (!self.waitingForAuthorization) {
        return;
    }
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status != kCLAuthorizationStatusNotDetermined) {
        self.waitingForAuthorization = NO;
        [self startIfAuthorized:status];
    }
}

@end
