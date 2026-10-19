#import <Foundation/Foundation.h>
#import "ISSPosition.h"

NS_ASSUME_NONNULL_BEGIN

/// One ISS pass (or closest approach) found near a reference location.
@interface TrajectorySearchResult : NSObject

@property (nonatomic, strong) ISSPosition *position;
@property (nonatomic) double distanceKm;
@property (nonatomic) BOOL withinRadius;

@property (nonatomic, readonly) NSTimeInterval timestamp;

@end

NS_ASSUME_NONNULL_END
