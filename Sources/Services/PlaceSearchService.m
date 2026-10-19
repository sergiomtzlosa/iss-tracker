#import "PlaceSearchService.h"

@interface PlaceSearchService () <MKLocalSearchCompleterDelegate>
@property (nonatomic, strong) MKLocalSearchCompleter *completer;
@property (nonatomic, strong) MKLocalSearch *activeSearch;
@property (nonatomic, copy, readwrite) NSArray<MKLocalSearchCompletion *> *results;
@end

@implementation PlaceSearchService

- (instancetype)init {
    self = [super init];
    if (self) {
        _completer = [[MKLocalSearchCompleter alloc] init];
        _completer.delegate = self;
        if (@available(macOS 10.15, *)) {
            _completer.resultTypes = MKLocalSearchCompleterResultTypeAddress |
                                     MKLocalSearchCompleterResultTypePointOfInterest |
                                     MKLocalSearchCompleterResultTypeQuery;
        }
        _results = @[];
    }
    return self;
}

- (void)updateQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 2) {
        [self.completer cancel];
        self.results = @[];
        [self.delegate placeSearchServiceDidUpdateResults:self];
        return;
    }
    self.completer.queryFragment = trimmed;
}

- (void)resolveCompletion:(MKLocalSearchCompletion *)searchCompletion
               completion:(void (^)(MKMapItem * _Nullable, NSError * _Nullable))completion {
    [self.activeSearch cancel];

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:searchCompletion];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    self.activeSearch = search;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (completion) {
            completion(item, error);
        }
    }];
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    self.results = completer.results;
    [self.delegate placeSearchServiceDidUpdateResults:self];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    self.results = @[];
    [self.delegate placeSearchServiceDidUpdateResults:self];
}

@end
