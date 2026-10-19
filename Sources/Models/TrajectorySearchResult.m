#import "TrajectorySearchResult.h"

@implementation TrajectorySearchResult

- (NSTimeInterval)timestamp {
    return self.position.timestamp;
}

@end
