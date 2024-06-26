#import "ISSDataProvider.h"

NSString * const ISSDataProviderErrorDomain = @"ISSDataProviderErrorDomain";

static NSString * const ISSAPIBaseURL = @"https://api.wheretheiss.at/v1/satellites/25544";
static const NSUInteger ISSAPITimestampsPerRequest = 10;

typedef NS_ENUM(NSInteger, ISSDataProviderErrorCode) {
    ISSDataProviderErrorInvalidInput = 1,
    ISSDataProviderErrorNetwork = 2,
    ISSDataProviderErrorParsing = 3,
    ISSDataProviderErrorHTTP = 4,
};

@interface ISSDataProvider ()

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation ISSDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 20;
        configuration.HTTPAdditionalHeaders = @{@"User-Agent": @"ISSTracker/1.0 (macOS)"};
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

#pragma mark - Current position

- (void)fetchCurrentPositionWithCompletion:(ISSDataCompletion)completion {
    NSURL *url = [NSURL URLWithString:[ISSAPIBaseURL stringByAppendingString:@"?units=kilometers"]];
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        ISSPosition *position = nil;
        NSError *resultError = nil;
        if (error) {
            resultError = error;
        } else {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? [(NSHTTPURLResponse *)response statusCode] : 200;
            if (status >= 400) {
                resultError = [self errorWithCode:ISSDataProviderErrorHTTP
                                          message:[NSString stringWithFormat:@"Server responded with HTTP %ld.", (long)status]];
            } else {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&resultError];
                if ([json isKindOfClass:[NSDictionary class]]) {
                    position = [ISSPosition positionWithJSON:json];
                }
                if (!position && !resultError) {
                    resultError = [self errorWithCode:ISSDataProviderErrorParsing
                                              message:@"Could not parse the current ISS position."];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(position, resultError);
        });
    }];
    [task resume];
}

#pragma mark - Trajectory

- (void)fetchPositionsFromTime:(NSTimeInterval)startTime
                        toTime:(NSTimeInterval)endTime
                      interval:(NSTimeInterval)interval
                    completion:(ISSTrajectoryCompletion)completion {
    if (endTime <= startTime || interval < 1) {
        if (completion) {
            completion(nil, [self errorWithCode:ISSDataProviderErrorInvalidInput
                                        message:@"The trajectory time window is invalid."]);
        }
        return;
    }

    NSMutableArray<NSNumber *> *timestamps = [NSMutableArray array];
    for (double t = startTime; t <= endTime + 0.5; t += interval) {
        [timestamps addObject:@(round(t))];
    }
    if (timestamps.count > 2000) {
        if (completion) {
            completion(nil, [self errorWithCode:ISSDataProviderErrorInvalidInput
                                        message:@"The requested time window is too large. Choose a shorter range."]);
        }
        return;
    }

    NSMutableArray<NSArray<NSNumber *> *> *batches = [NSMutableArray array];
    for (NSUInteger index = 0; index < timestamps.count; index += ISSAPITimestampsPerRequest) {
        NSUInteger length = MIN(ISSAPITimestampsPerRequest, timestamps.count - index);
        [batches addObject:[timestamps subarrayWithRange:NSMakeRange(index, length)]];
    }

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.name = @"com.sid.ISSTracker.trajectory";
    queue.maxConcurrentOperationCount = 3;
    queue.qualityOfService = NSQualityOfServiceUserInitiated;

    NSMutableArray<ISSPosition *> *allPositions = [NSMutableArray array];
    __block NSError *firstError = nil;

    for (NSArray<NSNumber *> *batch in batches) {
        [queue addOperationWithBlock:^{
            // Be polite to the public API.
            usleep(80 * 1000);
            NSError *batchError = nil;
            NSArray<ISSPosition *> *positions = [self fetchPositionsSynchronouslyForTimestamps:batch error:&batchError];
            @synchronized (allPositions) {
                if (positions.count > 0) {
                    [allPositions addObjectsFromArray:positions];
                }
                if (batchError && !firstError) {
                    firstError = batchError;
                    NSLog(@"[ISSTracker] Position batch failed: %@", batchError.localizedDescription);
                }
            }
        }];
    }

    [queue addBarrierBlock:^{
        NSArray<ISSPosition *> *sorted = [allPositions sortedArrayUsingComparator:^NSComparisonResult(ISSPosition *a, ISSPosition *b) {
            if (a.timestamp < b.timestamp) return NSOrderedAscending;
            if (a.timestamp > b.timestamp) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSLog(@"[ISSTracker] trajectory request finished with %lu positions",
              (unsigned long)sorted.count);
        NSError *error = sorted.count > 0 ? nil : (firstError ?: [self errorWithCode:ISSDataProviderErrorNetwork
                                                                             message:@"No positions were returned for this time window."]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(sorted, error);
        });
    }];
}

- (NSArray<ISSPosition *> *)fetchPositionsSynchronouslyForTimestamps:(NSArray<NSNumber *> *)timestamps
                                                               error:(NSError **)error {
    NSMutableArray<NSString *> *timestampStrings = [NSMutableArray arrayWithCapacity:timestamps.count];
    for (NSNumber *timestamp in timestamps) {
        [timestampStrings addObject:[NSString stringWithFormat:@"%.0f", timestamp.doubleValue]];
    }
    NSString *urlString = [NSString stringWithFormat:@"%@/positions?timestamps=%@&units=kilometers",
                           ISSAPIBaseURL, [timestampStrings componentsJoinedByString:@","]];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) *error = [self errorWithCode:ISSDataProviderErrorInvalidInput message:@"Invalid API URL."];
        return @[];
    }

    __block NSArray<ISSPosition *> *positions = nil;
    __block NSError *taskError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) {
            taskError = networkError;
        } else {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? [(NSHTTPURLResponse *)response statusCode] : 200;
            if (status >= 400) {
                taskError = [self errorWithCode:ISSDataProviderErrorHTTP
                                        message:[NSString stringWithFormat:@"Server responded with HTTP %ld.", (long)status]];
            } else {
                NSError *parseError = nil;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                if (parseError) {
                    taskError = parseError;
                } else {
                    NSArray *rows = [json isKindOfClass:[NSArray class]] ? json : @[json];
                    NSMutableArray<ISSPosition *> *parsed = [NSMutableArray array];
                    for (id row in rows) {
                        if (![row isKindOfClass:[NSDictionary class]]) continue;
                        ISSPosition *position = [ISSPosition positionWithJSON:row];
                        if (position) {
                            [parsed addObject:position];
                        }
                    }
                    positions = parsed;
                }
            }
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long result = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (result != 0) {
        [task cancel];
        taskError = [self errorWithCode:ISSDataProviderErrorNetwork
                                message:@"The ISS API request timed out."];
    }
    if (taskError && error) {
        *error = taskError;
    }
    return positions ?: @[];
}

#pragma mark - Helpers

- (NSError *)errorWithCode:(ISSDataProviderErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:ISSDataProviderErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

@end
