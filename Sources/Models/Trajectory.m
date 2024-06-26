#import "Trajectory.h"

@interface Trajectory ()
@property (nonatomic, copy, readwrite) NSArray<ISSPosition *> *positions;
@end

@implementation Trajectory

- (instancetype)initWithPositions:(NSArray<ISSPosition *> *)positions {
    self = [super init];
    if (self) {
        _positions = [positions sortedArrayUsingComparator:^NSComparisonResult(ISSPosition *a, ISSPosition *b) {
            if (a.timestamp < b.timestamp) return NSOrderedAscending;
            if (a.timestamp > b.timestamp) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    }
    return self;
}

- (NSTimeInterval)startTime {
    return self.positions.firstObject ? self.positions.firstObject.timestamp : 0;
}

- (NSTimeInterval)endTime {
    return self.positions.lastObject ? self.positions.lastObject.timestamp : 0;
}

- (NSTimeInterval)duration {
    return MAX(0, self.endTime - self.startTime);
}

- (NSUInteger)count {
    return self.positions.count;
}

- (ISSPosition *)interpolatedPositionAtTime:(NSTimeInterval)time {
    NSArray<ISSPosition *> *positions = self.positions;
    if (positions.count == 0) {
        return nil;
    }
    if (positions.count == 1 || time <= positions.firstObject.timestamp) {
        return positions.firstObject;
    }
    if (time >= positions.lastObject.timestamp) {
        return positions.lastObject;
    }

    NSUInteger low = 0;
    NSUInteger high = positions.count - 1;
    while (low + 1 < high) {
        NSUInteger mid = (low + high) / 2;
        if (positions[mid].timestamp <= time) {
            low = mid;
        } else {
            high = mid;
        }
    }

    ISSPosition *before = positions[low];
    ISSPosition *after = positions[high];
    double span = after.timestamp - before.timestamp;
    double fraction = span > 0 ? (time - before.timestamp) / span : 0.0;

    double lonDelta = after.longitude - before.longitude;
    if (lonDelta > 180) lonDelta -= 360;
    if (lonDelta < -180) lonDelta += 360;

    double longitude = before.longitude + lonDelta * fraction;
    while (longitude > 180) longitude -= 360;
    while (longitude < -180) longitude += 360;

    ISSPosition *result = [[ISSPosition alloc] init];
    result.latitude = before.latitude + (after.latitude - before.latitude) * fraction;
    result.longitude = longitude;
    result.altitude = before.altitude + (after.altitude - before.altitude) * fraction;
    result.velocity = before.velocity + (after.velocity - before.velocity) * fraction;
    result.timestamp = time;
    result.visibility = fraction < 0.5 ? before.visibility : after.visibility;
    return result;
}

- (ISSPosition *)positionClosestToTime:(NSTimeInterval)time {
    if (self.positions.count == 0) {
        return nil;
    }
    NSUInteger index = 0;
    NSUInteger count = self.positions.count;
    NSUInteger low = 0;
    NSUInteger high = count - 1;
    while (low < high) {
        NSUInteger mid = (low + high) / 2;
        if (self.positions[mid].timestamp < time) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    index = low;
    ISSPosition *candidate = self.positions[index];
    if (index > 0) {
        ISSPosition *previous = self.positions[index - 1];
        if (fabs(previous.timestamp - time) <= fabs(candidate.timestamp - time)) {
            candidate = previous;
        }
    }
    return candidate;
}

+ (NSArray<NSArray<ISSPosition *> *> *)segmentsForPositions:(NSArray<ISSPosition *> *)positions {
    NSMutableArray<NSArray<ISSPosition *> *> *segments = [NSMutableArray array];
    NSMutableArray<ISSPosition *> *current = [NSMutableArray array];
    ISSPosition *previous = nil;
    for (ISSPosition *position in positions) {
        if (previous) {
            double delta = position.longitude - previous.longitude;
            if (fabs(delta) > 180.0) {
                if (current.count > 1) {
                    [segments addObject:[current copy]];
                }
                [current removeAllObjects];
            }
        }
        [current addObject:position];
        previous = position;
    }
    if (current.count > 1) {
        [segments addObject:[current copy]];
    }
    if (segments.count == 0 && positions.count == 1) {
        [segments addObject:positions];
    }
    return [segments copy];
}

- (NSArray<NSArray<ISSPosition *> *> *)segmentsSplitAtAntimeridian {
    return [Trajectory segmentsForPositions:self.positions];
}

@end
