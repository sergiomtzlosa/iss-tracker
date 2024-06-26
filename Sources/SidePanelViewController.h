#import <Cocoa/Cocoa.h>
#import <CoreLocation/CoreLocation.h>
#import "TrajectorySearchResult.h"

NS_ASSUME_NONNULL_BEGIN

@class SidePanelViewController;

@protocol SidePanelViewControllerDelegate <NSObject>
- (void)sidePanel:(SidePanelViewController *)panel didSelectCoordinate:(CLLocationCoordinate2D)coordinate
             name:(NSString *)name;
- (void)sidePanelDidRequestCurrentLocation:(SidePanelViewController *)panel;
- (void)sidePanel:(SidePanelViewController *)panel
    didRequestTrajectoryFromDate:(NSDate *)startDate
                          toDate:(NSDate *)endDate;
- (void)sidePanel:(SidePanelViewController *)panel
    didRequestPassSearchAtDate:(NSDate *)date
                      radiusKm:(double)radiusKm;
- (void)sidePanel:(SidePanelViewController *)panel didSelectSearchResult:(TrajectorySearchResult *)result;
- (void)sidePanelDidRequestClear:(SidePanelViewController *)panel;
- (void)sidePanelDidRequestLiveTracking:(SidePanelViewController *)panel;
- (void)sidePanel:(SidePanelViewController *)panel didChangeFollowISS:(BOOL)followISS;
@end

@interface SidePanelViewController : NSViewController

@property (nonatomic, weak) id<SidePanelViewControllerDelegate> delegate;

/// Search radius currently selected in the panel, in kilometers.
@property (nonatomic, readonly) double radiusKm;

- (void)setReferenceLocationName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (void)setStatusText:(NSString *)text isError:(BOOL)isError;
- (void)setBusy:(BOOL)busy;
- (void)setClearEnabled:(BOOL)enabled;
- (void)setLiveTrackingActive:(BOOL)active;
- (void)setPassResults:(NSArray<TrajectorySearchResult *> *)results;
- (void)setTrajectoryRangeStartDate:(NSDate *)startDate endDate:(NSDate *)endDate;
- (void)setFollowISS:(BOOL)followISS;

@end

NS_ASSUME_NONNULL_END
