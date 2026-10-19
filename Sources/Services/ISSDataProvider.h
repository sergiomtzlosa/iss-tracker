#import <Foundation/Foundation.h>
#import "ISSPosition.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ISSDataCompletion)(ISSPosition * _Nullable position, NSError * _Nullable error);
typedef void (^ISSTrajectoryCompletion)(NSArray<ISSPosition *> * _Nullable positions, NSError * _Nullable error);

extern NSString * const ISSDataProviderErrorDomain;

/// Client for the wheretheiss.at public ISS API.
///
/// Trajectory requests are split into batches of at most 10 timestamps (API limit)
/// and fetched with limited concurrency.
@interface ISSDataProvider : NSObject

- (void)fetchCurrentPositionWithCompletion:(ISSDataCompletion)completion;

- (void)fetchPositionsFromTime:(NSTimeInterval)startTime
                        toTime:(NSTimeInterval)endTime
                      interval:(NSTimeInterval)interval
                    completion:(ISSTrajectoryCompletion)completion;

@end

NS_ASSUME_NONNULL_END
