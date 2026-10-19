#import <Foundation/Foundation.h>
#import "ISSPosition.h"

NS_ASSUME_NONNULL_BEGIN

/// An ordered set of ISS samples covering a time window.
@interface Trajectory : NSObject

@property (nonatomic, copy, readonly) NSArray<ISSPosition *> *positions;

- (instancetype)initWithPositions:(NSArray<ISSPosition *> *)positions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSTimeInterval startTime;
@property (nonatomic, readonly) NSTimeInterval endTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSUInteger count;

/// Position at an arbitrary time, linearly interpolated (longitude unwrapped at ±180°).
- (nullable ISSPosition *)interpolatedPositionAtTime:(NSTimeInterval)time;

/// The closest stored sample to the given time.
- (nullable ISSPosition *)positionClosestToTime:(NSTimeInterval)time;

/// Splits samples into runs that do not cross the antimeridian.
- (NSArray<NSArray<ISSPosition *> *> *)segmentsSplitAtAntimeridian;
+ (NSArray<NSArray<ISSPosition *> *> *)segmentsForPositions:(NSArray<ISSPosition *> *)positions;

@end

NS_ASSUME_NONNULL_END
