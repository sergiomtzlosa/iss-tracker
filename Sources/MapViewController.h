#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
#import "Trajectory.h"

NS_ASSUME_NONNULL_BEGIN

@class MapViewController;

@protocol MapViewControllerDelegate <NSObject>
- (void)mapViewController:(MapViewController *)controller didClickCoordinate:(CLLocationCoordinate2D)coordinate;
@end

/// Owns the MKMapView, ISS/reference annotations and all trajectory overlays.
@interface MapViewController : NSViewController

@property (nonatomic, weak) id<MapViewControllerDelegate> delegate;
@property (nonatomic) BOOL followsISS;

- (void)showTrajectory:(Trajectory *)trajectory;
- (void)clearTrajectory;
- (void)updatePlayheadTime:(NSTimeInterval)time trajectory:(Trajectory *)trajectory;
- (void)updateCurrentPosition:(ISSPosition *)position;
- (void)showReferenceCoordinate:(CLLocationCoordinate2D)coordinate
                           name:(NSString *)name
                       radiusKm:(double)radiusKm;
- (void)showPassHighlights:(NSArray<NSArray<ISSPosition *> *> *)segments;
- (void)clearPassHighlights;
- (void)centerOnCoordinate:(CLLocationCoordinate2D)coordinate longitudeSpan:(double)longitudeSpan;

@end

NS_ASSUME_NONNULL_END
