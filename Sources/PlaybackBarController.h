#import <Cocoa/Cocoa.h>
#import "Trajectory.h"

NS_ASSUME_NONNULL_BEGIN

@class PlaybackBarController;

@protocol PlaybackBarControllerDelegate <NSObject>
- (void)playbackBar:(PlaybackBarController *)bar didUpdatePlayheadTime:(NSTimeInterval)time;
@end

/// Transport controls and animation clock for a trajectory.
@interface PlaybackBarController : NSViewController

@property (nonatomic, weak) id<PlaybackBarControllerDelegate> delegate;
@property (nonatomic, readonly) NSTimeInterval playheadTime;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) BOOL hasTrajectory;

- (void)loadTrajectory:(Trajectory *)trajectory;
- (void)unloadTrajectory;
- (void)seekToTime:(NSTimeInterval)time;

- (void)play;
- (void)pause;
- (void)stop;
- (void)replay;
- (void)togglePlayPause;

@end

NS_ASSUME_NONNULL_END
