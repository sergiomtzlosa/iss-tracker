#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PlaceSearchService;

@protocol PlaceSearchServiceDelegate <NSObject>
- (void)placeSearchServiceDidUpdateResults:(PlaceSearchService *)service;
@end

/// Wraps MKLocalSearchCompleter (live suggestions) and MKLocalSearch (resolution).
@interface PlaceSearchService : NSObject

@property (nonatomic, weak) id<PlaceSearchServiceDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray<MKLocalSearchCompletion *> *results;

- (void)updateQuery:(NSString *)query;

- (void)resolveCompletion:(MKLocalSearchCompletion *)searchCompletion
               completion:(void (^)(MKMapItem * _Nullable item, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
