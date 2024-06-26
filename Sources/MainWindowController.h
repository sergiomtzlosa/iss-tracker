#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MapViewController, SidePanelViewController, PlaybackBarController, ISSDataProvider,
       LocationService, Trajectory;

/// Coordinates map, side panel and playback bar; owns networking and the reference location.
@interface MainWindowController : NSWindowController

- (void)togglePlayPause;
- (void)replayTrajectory;
- (void)reloadTrajectory;

@end

NS_ASSUME_NONNULL_END
