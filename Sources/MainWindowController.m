#import "MainWindowController.h"
#import "MapViewController.h"
#import "SidePanelViewController.h"
#import "PlaybackBarController.h"
#import "ISSDataProvider.h"
#import "LocationService.h"
#import "Trajectory.h"
#import "TimeFormatter.h"
#import <CoreLocation/CoreLocation.h>

static const NSTimeInterval kDefaultWindowHalfWidth = 45 * 60.0;   // ±45 minutes
static const NSTimeInterval kPassSearchHalfWindow = 3 * 3600.0;    // ±3 hours

static double DistanceKm(CLLocationCoordinate2D a, CLLocationCoordinate2D b) {
    double lat1 = a.latitude * M_PI / 180.0;
    double lat2 = b.latitude * M_PI / 180.0;
    double deltaLat = (b.latitude - a.latitude) * M_PI / 180.0;
    double deltaLon = (b.longitude - a.longitude) * M_PI / 180.0;
    double h = sin(deltaLat / 2) * sin(deltaLat / 2) +
               cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);
    return 6371.0 * 2.0 * asin(MIN(1.0, sqrt(h)));
}

static NSTimeInterval SampleIntervalForWindow(NSTimeInterval duration) {
    NSTimeInterval interval = 30;
    if (duration > 3 * 3600) interval = 60;
    if (duration > 8 * 3600) interval = 120;
    if (duration > 20 * 3600) interval = 240;
    NSTimeInterval minimumForCap = ceil(duration / 400.0 / 10.0) * 10.0;
    return MAX(interval, minimumForCap);
}

/// Debug helper (ISSTRACKER_DEBUG_LAYOUT): logs the frames of alignment-critical
/// controls (date fields and sliders) in window coordinates, so column alignment can
/// be verified without a screenshot.
static void ISSLogAlignmentFrames(NSView *view) {
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:[NSDatePicker class]] || [subview isKindOfClass:[NSSlider class]]) {
            NSRect inWindow = [subview convertRect:subview.bounds toView:nil];
            NSLog(@"[ISSTracker] %@ frame=%@", NSStringFromClass(subview.class), NSStringFromRect(inWindow));
        }
        ISSLogAlignmentFrames(subview);
    }
}

@interface MainWindowController () <MapViewControllerDelegate, SidePanelViewControllerDelegate,
                                    PlaybackBarControllerDelegate, LocationServiceDelegate,
                                    NSSplitViewDelegate>

@property (nonatomic, strong) MapViewController *mapViewController;
@property (nonatomic, strong) SidePanelViewController *sidePanelViewController;
@property (nonatomic, strong) PlaybackBarController *playbackBarController;
@property (nonatomic, strong) ISSDataProvider *dataProvider;
@property (nonatomic, strong) LocationService *locationService;
@property (nonatomic, strong) CLGeocoder *geocoder;
@property (nonatomic, strong) NSSplitView *splitView;

@property (nonatomic, strong, nullable) Trajectory *trajectory;
@property (nonatomic) CLLocationCoordinate2D referenceCoordinate;
@property (nonatomic, copy) NSString *referenceName;
@property (nonatomic) BOOL hasReferenceCoordinate;
@property (nonatomic) BOOL pendingDefaultLocation;
@property (nonatomic, strong, nullable) id keyMonitor;
@property (nonatomic) BOOL selftestMode;
@property (nonatomic) BOOL selftestStarted;

@property (nonatomic, strong, nullable) NSTimer *liveTimer;
@property (nonatomic) BOOL liveRefreshInFlight;
@property (nonatomic) BOOL liveTracking;
@property (nonatomic, strong, nullable) NSTimer *liveTrackingTimer;
@property (nonatomic, strong, nullable) ISSPosition *latestLivePosition;

@end

@implementation MainWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 830)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"ISS Tracker";
    window.minSize = NSMakeSize(1020, 660);
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _dataProvider = [[ISSDataProvider alloc] init];
        _locationService = [[LocationService alloc] init];
        _locationService.delegate = self;
        _geocoder = [[CLGeocoder alloc] init];
        _referenceName = @"";
        _selftestMode = getenv("ISSTRACKER_SELFTEST") != NULL;
        [self buildInterface];
        [self installKeyboardMonitor];
        [self startInitialLoad];
        [self startLiveUpdates];
    }
    return self;
}

- (void)dealloc {
    if (_keyMonitor) {
        [NSEvent removeMonitor:_keyMonitor];
    }
    [_liveTimer invalidate];
    [_liveTrackingTimer invalidate];
}

#pragma mark - Window setup

- (void)buildInterface {
    NSView *contentView = self.window.contentView;

    self.mapViewController = [[MapViewController alloc] init];
    self.mapViewController.delegate = self;
    self.sidePanelViewController = [[SidePanelViewController alloc] init];
    self.sidePanelViewController.delegate = self;
    self.playbackBarController = [[PlaybackBarController alloc] init];
    self.playbackBarController.delegate = self;

    self.splitView = [[NSSplitView alloc] init];
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.delegate = self;
    [contentView addSubview:self.splitView];
    [NSLayoutConstraint activateConstraints:@[
        [self.splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.splitView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    // Left: map with the floating playback bar.
    NSView *mapContainer = [[NSView alloc] init];
    [self.splitView addArrangedSubview:mapContainer];

    NSView *mapView = self.mapViewController.view;
    mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [mapContainer addSubview:mapView];

    NSView *playbackBar = self.playbackBarController.view;
    playbackBar.translatesAutoresizingMaskIntoConstraints = NO;
    [mapContainer addSubview:playbackBar];

    NSLayoutConstraint *barWidth = [playbackBar.widthAnchor constraintEqualToConstant:620];
    barWidth.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [mapView.leadingAnchor constraintEqualToAnchor:mapContainer.leadingAnchor],
        [mapView.trailingAnchor constraintEqualToAnchor:mapContainer.trailingAnchor],
        [mapView.topAnchor constraintEqualToAnchor:mapContainer.topAnchor],
        [mapView.bottomAnchor constraintEqualToAnchor:mapContainer.bottomAnchor],

        [playbackBar.centerXAnchor constraintEqualToAnchor:mapContainer.centerXAnchor],
        [playbackBar.bottomAnchor constraintEqualToAnchor:mapContainer.bottomAnchor constant:-18],
        [playbackBar.heightAnchor constraintEqualToConstant:84],
        barWidth,
    ]];

    // Right: side panel.
    NSView *sidePanel = self.sidePanelViewController.view;
    [self.splitView addArrangedSubview:sidePanel];
    NSLayoutConstraint *panelWidth = [sidePanel.widthAnchor constraintEqualToConstant:364];
    panelWidth.priority = NSLayoutPriorityDefaultLow;
    panelWidth.active = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat position = MAX(660, contentView.bounds.size.width - 364);
        [self.splitView setPosition:position ofDividerAtIndex:0];
    });

    if (getenv("ISSTRACKER_DEBUG_LAYOUT")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[ISSTracker] layout window=%@ split=%@ mapContainer=%@ map=%@ sidebar=%@ playback=%@",
                  NSStringFromRect(contentView.bounds),
                  NSStringFromRect(self.splitView.frame),
                  NSStringFromRect(self.splitView.arrangedSubviews.firstObject.frame),
                  NSStringFromRect(self.mapViewController.view.frame),
                  NSStringFromRect(self.sidePanelViewController.view.frame),
                  NSStringFromRect(self.playbackBarController.view.frame));
            ISSLogAlignmentFrames(self.sidePanelViewController.view);
            ISSLogAlignmentFrames(self.playbackBarController.view);
        });
    }
}

#pragma mark - Startup

- (void)startInitialLoad {
    NSDate *now = [NSDate date];
    NSDate *start = [now dateByAddingTimeInterval:-kDefaultWindowHalfWidth];
    NSDate *end = [now dateByAddingTimeInterval:kDefaultWindowHalfWidth];
    [self.sidePanelViewController setTrajectoryRangeStartDate:start endDate:end];
    [self.sidePanelViewController setFollowISS:YES];
    self.mapViewController.followsISS = YES;
    [self.sidePanelViewController setBusy:YES];
    [self.sidePanelViewController setStatusText:@"Loading ISS position and trajectory…" isError:NO];
    [self loadTrajectoryFromDate:start toDate:end autoplay:NO playheadDate:now];

    __weak typeof(self) weakSelf = self;
    [self.dataProvider fetchCurrentPositionWithCompletion:^(ISSPosition *position, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (position && !self.trajectory) {
            [self.mapViewController updateCurrentPosition:position];
        } else if (error && !self.trajectory) {
            [self.sidePanelViewController setStatusText:error.localizedDescription isError:YES];
        }
    }];

    // Default the reference location to the user's current location. Skipped during the
    // headless selftest, which sets its own reference location.
    if (!getenv("ISSTRACKER_SELFTEST")) {
        self.pendingDefaultLocation = YES;
        [self.locationService requestCurrentLocation];
    }
}

#pragma mark - Trajectory loading

- (void)loadTrajectoryFromDate:(NSDate *)startDate
                        toDate:(NSDate *)endDate
                      autoplay:(BOOL)autoplay
                  playheadDate:(NSDate *)playheadDate {
    NSTimeInterval duration = [endDate timeIntervalSinceDate:startDate];
    NSTimeInterval interval = SampleIntervalForWindow(duration);

    __weak typeof(self) weakSelf = self;
    [self.dataProvider fetchPositionsFromTime:startDate.timeIntervalSince1970
                                       toTime:endDate.timeIntervalSince1970
                                     interval:interval
                                   completion:^(NSArray<ISSPosition *> *positions, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.sidePanelViewController setBusy:NO];
            if (positions.count == 0) {
                NSString *message = error.localizedDescription ?: @"No ISS positions were returned for this window.";
                NSLog(@"[ISSTracker] Trajectory load failed: %@", message);
                [self.sidePanelViewController setStatusText:message isError:YES];
                return;
            }
            Trajectory *trajectory = [[Trajectory alloc] initWithPositions:positions];
            NSLog(@"[ISSTracker] Trajectory loaded: %lu positions", (unsigned long)positions.count);
            self.trajectory = trajectory;
            [self.mapViewController clearPassHighlights];
            [self.mapViewController showTrajectory:trajectory];
            [self.playbackBarController loadTrajectory:trajectory];
            if (playheadDate) {
                [self.playbackBarController seekToTime:playheadDate.timeIntervalSince1970];
            }
            if (autoplay) {
                [self.playbackBarController play];
            }
            [self.sidePanelViewController setTrajectoryRangeStartDate:startDate endDate:endDate];
            NSUInteger passes = [self updatePassesForCurrentTrajectory];
            [self.sidePanelViewController setClearEnabled:YES];
            NSString *message = [NSString stringWithFormat:@"Loaded %lu positions (%@ → %@).",
                                 (unsigned long)positions.count,
                                 [TimeFormatter shortDateTimeStringFromTimestamp:startDate.timeIntervalSince1970],
                                 [TimeFormatter shortDateTimeStringFromTimestamp:endDate.timeIntervalSince1970]];
            if (passes > 0) {
                message = [message stringByAppendingFormat:@" %lu pass%@ within %@.",
                           (unsigned long)passes, passes == 1 ? @"" : @"es",
                           [TimeFormatter distanceStringFromKilometers:self.sidePanelViewController.radiusKm]];
            } else if (self.hasReferenceCoordinate) {
                message = [message stringByAppendingFormat:@" No pass within %@ in this window.",
                           [TimeFormatter distanceStringFromKilometers:self.sidePanelViewController.radiusKm]];
            }
            [self.sidePanelViewController setStatusText:message isError:NO];

            ISSPosition *focus = [trajectory interpolatedPositionAtTime:self.playbackBarController.playheadTime];
            if (focus) {
                [self.mapViewController centerOnCoordinate:focus.coordinate longitudeSpan:140];
            }

            if (self.selftestMode && !self.selftestStarted) {
                self.selftestStarted = YES;
                [self runSelftest];
            }
        });
    }];
}

#pragma mark - Live position updates

/// Polls the current ISS position every 15 seconds.
- (void)startLiveUpdates {
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:15.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf refreshLivePosition];
    }];
    timer.tolerance = 2.0;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.liveTimer = timer;
}

- (void)refreshLivePosition {
    if (self.liveRefreshInFlight) {
        return;
    }
    self.liveRefreshInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [self.dataProvider fetchCurrentPositionWithCompletion:^(ISSPosition *position, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.liveRefreshInFlight = NO;
        if (!position) {
            NSLog(@"[ISSTracker] live position fetch failed: %@", error.localizedDescription);
            return;
        }
        self.latestLivePosition = position;
        BOOL applied = [self shouldApplyLivePosition:position];
        if (applied) {
            [self.mapViewController updateCurrentPosition:position];
        }
        NSLog(@"[ISSTracker] live position: %.3f,%.3f applied=%@",
              position.latitude, position.longitude, applied ? @"YES" : @"NO");
    }];
}

/// The live position drives the map when the user is not animating/scrubbing away from
/// "now" — or when no trajectory is loaded at all.
- (BOOL)shouldApplyLivePosition:(ISSPosition *)position {
    if (self.playbackBarController.isPlaying) {
        return NO;
    }
    if (!self.trajectory) {
        return YES;
    }
    return fabs(self.playbackBarController.playheadTime - position.timestamp) <= 300.0;
}

#pragma mark - Live tracking

/// Starts following the track near the current time: reloads the ±45 min window around
/// now, parks the playhead at "now" and keeps it fresh with a slow refresh timer.
- (void)startLiveTracking {
    self.liveTracking = YES;
    [self.sidePanelViewController setLiveTrackingActive:YES];
    [self.sidePanelViewController setFollowISS:YES];
    self.mapViewController.followsISS = YES;
    [self reloadLiveTrajectory];
    [self startLiveTrackingTimer];
}

- (void)stopLiveTracking {
    if (!self.liveTracking) {
        return;
    }
    self.liveTracking = NO;
    [self.liveTrackingTimer invalidate];
    self.liveTrackingTimer = nil;
    [self.sidePanelViewController setLiveTrackingActive:NO];
}

- (void)startLiveTrackingTimer {
    [self.liveTrackingTimer invalidate];
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:300.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf refreshLiveTrajectory];
    }];
    timer.tolerance = 15.0;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.liveTrackingTimer = timer;
}

/// Slides the tracked window forward so the track keeps ending at the current time.
- (void)refreshLiveTrajectory {
    if (!self.liveTracking) {
        return;
    }
    if (self.playbackBarController.isPlaying) {
        return; // never yank the playhead while the animation is running
    }
    [self reloadLiveTrajectory];
}

- (void)reloadLiveTrajectory {
    NSDate *now = [NSDate date];
    NSDate *start = [now dateByAddingTimeInterval:-kDefaultWindowHalfWidth];
    NSDate *end = [now dateByAddingTimeInterval:kDefaultWindowHalfWidth];
    [self.sidePanelViewController setBusy:YES];
    [self.sidePanelViewController setStatusText:@"Loading the live trajectory…" isError:NO];
    [self loadTrajectoryFromDate:start toDate:end autoplay:NO playheadDate:now];
}

#pragma mark - Headless self-test

/// Enabled with ISSTRACKER_SELFTEST=1. Exercises the animation clock, reference
/// location and pass-search pipeline, then quits. Useful for CI/headless checks.
- (void)runSelftest {
    NSLog(@"[ISSTracker] SELFTEST begin");
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // Playhead is still at "now" here, so this must be applied to the map.
        [self refreshLivePosition];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self.playbackBarController play];
        NSLog(@"[ISSTracker] SELFTEST playing from %.0f", self.playbackBarController.playheadTime);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSTimeInterval time = self.playbackBarController.playheadTime;
        ISSPosition *position = [self.trajectory interpolatedPositionAtTime:time];
        NSLog(@"[ISSTracker] SELFTEST playhead=%.1f position=%.3f,%.3f",
              time, position.latitude, position.longitude);
        [self.playbackBarController pause];
        [self setReferenceCoordinate:CLLocationCoordinate2DMake(51.5074, -0.1278) name:@"London"];
        [self performPassSearchAtDate:[NSDate date] radiusKm:1500];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(38.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self sidePanelDidRequestClear:self.sidePanelViewController];
        NSLog(@"[ISSTracker] SELFTEST cleared trajectory=%d playbackHasTrajectory=%d",
              self.trajectory != nil, self.playbackBarController.hasTrajectory);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(39.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self sidePanelDidRequestLiveTracking:self.sidePanelViewController];
        NSLog(@"[ISSTracker] SELFTEST live tracking started=%d", self.liveTracking);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(52.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSLog(@"[ISSTracker] SELFTEST live tracking=%d trajectory=%d playheadDelta=%.0f s",
              self.liveTracking, self.trajectory != nil,
              self.playbackBarController.playheadTime - [NSDate date].timeIntervalSince1970);
        NSLog(@"[ISSTracker] SELFTEST complete");
        [NSApp terminate:nil];
    });
}

- (void)reloadTrajectory {
    [self stopLiveTracking];
    NSDate *now = [NSDate date];
    NSDate *start = [now dateByAddingTimeInterval:-kDefaultWindowHalfWidth];
    NSDate *end = [now dateByAddingTimeInterval:kDefaultWindowHalfWidth];
    [self.sidePanelViewController setBusy:YES];
    [self.sidePanelViewController setStatusText:@"Reloading trajectory…" isError:NO];
    [self loadTrajectoryFromDate:start toDate:end autoplay:NO playheadDate:now];
}

#pragma mark - Pass search

- (void)performPassSearchAtDate:(NSDate *)date radiusKm:(double)radiusKm {
    NSDate *start = [date dateByAddingTimeInterval:-kPassSearchHalfWindow];
    NSDate *end = [date dateByAddingTimeInterval:kPassSearchHalfWindow];
    [self.sidePanelViewController setBusy:YES];
    [self.sidePanelViewController setStatusText:[NSString stringWithFormat:@"Searching passes around %@…",
                                                 [TimeFormatter shortDateTimeStringFromTimestamp:date.timeIntervalSince1970]]
                                        isError:NO];

    __weak typeof(self) weakSelf = self;
    [self.dataProvider fetchPositionsFromTime:start.timeIntervalSince1970
                                       toTime:end.timeIntervalSince1970
                                     interval:60
                                   completion:^(NSArray<ISSPosition *> *positions, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.sidePanelViewController setBusy:NO];
            if (positions.count == 0) {
                [self.sidePanelViewController setStatusText:error.localizedDescription ?: @"The pass search returned no data."
                                                    isError:YES];
                return;
            }

            Trajectory *trajectory = [[Trajectory alloc] initWithPositions:positions];
            self.trajectory = trajectory;
            [self.mapViewController clearPassHighlights];
            [self.mapViewController showTrajectory:trajectory];
            [self.playbackBarController loadTrajectory:trajectory];
            [self.sidePanelViewController setTrajectoryRangeStartDate:start endDate:end];

            NSArray<TrajectorySearchResult *> *results = nil;
            NSArray<NSArray<ISSPosition *> *> *highlights = nil;
            [self computePassesForTrajectory:trajectory
                                      radius:radiusKm
                                     results:&results
                                  highlights:&highlights];
            NSLog(@"[ISSTracker] Pass search: %lu result(s) within %.0f km",
                  (unsigned long)results.count, radiusKm);

            [self.mapViewController showReferenceCoordinate:self.referenceCoordinate
                                                       name:self.referenceName
                                                   radiusKm:radiusKm];
            [self.mapViewController showPassHighlights:highlights];
            [self.sidePanelViewController setPassResults:results];
            [self.sidePanelViewController setClearEnabled:YES];

            if (results.count > 0) {
                [self.playbackBarController seekToTime:results.firstObject.timestamp];
                [self.playbackBarController pause];
            }

            double span = MAX(20.0, radiusKm / 111.0 * 3.0);
            [self.mapViewController centerOnCoordinate:self.referenceCoordinate longitudeSpan:span];

            if (results.count == 0 || !results.firstObject.withinRadius) {
                TrajectorySearchResult *closest = results.firstObject;
                NSString *message = closest
                    ? [NSString stringWithFormat:@"No pass within %@. Closest approach: %@ at %@.",
                       [TimeFormatter distanceStringFromKilometers:radiusKm],
                       [TimeFormatter distanceStringFromKilometers:closest.distanceKm],
                       [TimeFormatter shortDateTimeStringFromTimestamp:closest.timestamp]]
                    : @"The pass search returned no data.";
                [self.sidePanelViewController setStatusText:message isError:NO];
            } else {
                [self.sidePanelViewController setStatusText:
                    [NSString stringWithFormat:@"Found %lu pass%@ within %@.",
                     (unsigned long)results.count, results.count == 1 ? @"" : @"es",
                     [TimeFormatter distanceStringFromKilometers:radiusKm]]
                                                    isError:NO];
            }
        });
    }];
}

- (void)computePassesForTrajectory:(Trajectory *)trajectory
                            radius:(double)radiusKm
                           results:(NSArray<TrajectorySearchResult *> **)outResults
                        highlights:(NSArray<NSArray<ISSPosition *> *> **)outHighlights {
    NSArray<ISSPosition *> *positions = trajectory.positions;
    NSMutableArray<NSNumber *> *matchIndexes = [NSMutableArray array];
    NSInteger closestIndex = -1;
    double closestDistance = DBL_MAX;

    for (NSUInteger index = 0; index < positions.count; index++) {
        double distance = DistanceKm(positions[index].coordinate, self.referenceCoordinate);
        if (distance < closestDistance) {
            closestDistance = distance;
            closestIndex = (NSInteger)index;
        }
        if (distance <= radiusKm) {
            [matchIndexes addObject:@(index)];
        }
    }

    NSMutableArray<NSArray<NSNumber *> *> *indexGroups = [NSMutableArray array];
    NSMutableArray<NSNumber *> *currentGroup = nil;
    NSInteger lastIndex = -10;
    for (NSNumber *boxedIndex in matchIndexes) {
        NSInteger index = boxedIndex.integerValue;
        if (index != lastIndex + 1) {
            currentGroup = [NSMutableArray array];
            [indexGroups addObject:currentGroup];
        }
        [currentGroup addObject:boxedIndex];
        lastIndex = index;
    }

    NSMutableArray<TrajectorySearchResult *> *results = [NSMutableArray array];
    NSMutableArray<NSArray<ISSPosition *> *> *highlights = [NSMutableArray array];

    if (indexGroups.count > 0) {
        for (NSArray<NSNumber *> *group in indexGroups) {
            NSInteger bestIndex = group.firstObject.integerValue;
            double bestDistance = DBL_MAX;
            for (NSNumber *boxedIndex in group) {
                NSInteger index = boxedIndex.integerValue;
                double distance = DistanceKm(positions[index].coordinate, self.referenceCoordinate);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestIndex = index;
                }
            }
            TrajectorySearchResult *result = [[TrajectorySearchResult alloc] init];
            result.position = positions[bestIndex];
            result.distanceKm = bestDistance;
            result.withinRadius = YES;
            [results addObject:result];

            NSInteger lower = MAX(0, group.firstObject.integerValue - 1);
            NSInteger upper = MIN((NSInteger)positions.count - 1, group.lastObject.integerValue + 1);
            [highlights addObject:[positions subarrayWithRange:NSMakeRange(lower, upper - lower + 1)]];
        }
    } else if (closestIndex >= 0) {
        TrajectorySearchResult *result = [[TrajectorySearchResult alloc] init];
        result.position = positions[closestIndex];
        result.distanceKm = closestDistance;
        result.withinRadius = NO;
        [results addObject:result];

        NSInteger lower = MAX(0, closestIndex - 2);
        NSInteger upper = MIN((NSInteger)positions.count - 1, closestIndex + 2);
        [highlights addObject:[positions subarrayWithRange:NSMakeRange(lower, upper - lower + 1)]];
    }

    if (outResults) *outResults = [results copy];
    if (outHighlights) *outHighlights = [highlights copy];
}

/// Lists the passes of the loaded trajectory over the reference location, so loading a
/// trajectory also fills the results list. Returns the number of passes found.
- (NSUInteger)updatePassesForCurrentTrajectory {
    if (!self.hasReferenceCoordinate || self.trajectory.positions.count == 0) {
        [self.sidePanelViewController setPassResults:@[]];
        [self.mapViewController clearPassHighlights];
        return 0;
    }

    NSArray<TrajectorySearchResult *> *results = nil;
    NSArray<NSArray<ISSPosition *> *> *highlights = nil;
    [self computePassesForTrajectory:self.trajectory
                              radius:self.sidePanelViewController.radiusKm
                             results:&results
                          highlights:&highlights];
    [self.mapViewController showPassHighlights:highlights];
    [self.sidePanelViewController setPassResults:results];

    NSUInteger passes = 0;
    for (TrajectorySearchResult *result in results) {
        if (result.withinRadius) {
            passes++;
        }
    }
    NSLog(@"[ISSTracker] trajectory passes: %lu within %.0f km (%lu list row%@)",
          (unsigned long)passes, self.sidePanelViewController.radiusKm,
          (unsigned long)results.count, results.count == 1 ? @"" : @"s");
    return passes;
}

#pragma mark - Reference location

- (void)setReferenceCoordinate:(CLLocationCoordinate2D)coordinate name:(NSString *)name {
    self.referenceCoordinate = coordinate;
    self.hasReferenceCoordinate = YES;
    self.referenceName = name.length > 0 ? name : @"Dropped Pin";
    [self.sidePanelViewController setReferenceLocationName:self.referenceName coordinate:coordinate];
    [self updatePassesForCurrentTrajectory];
    [self.mapViewController showReferenceCoordinate:coordinate name:self.referenceName radiusKm:0];

    __weak typeof(self) weakSelf = self;
    CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
    [self.geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || placemarks.count == 0) return;
            CLPlacemark *placemark = placemarks.firstObject;
            NSString *resolved = placemark.name;
            if (resolved.length == 0) {
                resolved = placemark.locality;
            }
            if (resolved.length == 0) {
                resolved = placemark.country;
            }
            if (resolved.length > 0 && [self.referenceName isEqualToString:@"Dropped Pin"]) {
                self.referenceName = resolved;
                [self.sidePanelViewController setReferenceLocationName:resolved coordinate:self.referenceCoordinate];
            }
        });
    }];
}

#pragma mark - MapViewControllerDelegate

- (void)mapViewController:(MapViewController *)controller didClickCoordinate:(CLLocationCoordinate2D)coordinate {
    [self setReferenceCoordinate:coordinate name:nil];
    [self.sidePanelViewController setStatusText:@"Location set from map click."
                                        isError:NO];
}

#pragma mark - SidePanelViewControllerDelegate

- (void)sidePanel:(SidePanelViewController *)panel didSelectCoordinate:(CLLocationCoordinate2D)coordinate
             name:(NSString *)name {
    [self setReferenceCoordinate:coordinate name:name];
    [self.mapViewController centerOnCoordinate:coordinate longitudeSpan:12.0];
    [self.sidePanelViewController setStatusText:[NSString stringWithFormat:@"Selected: %@", name] isError:NO];
}

- (void)sidePanelDidRequestCurrentLocation:(SidePanelViewController *)panel {
    [self.sidePanelViewController setStatusText:@"Requesting your location…" isError:NO];
    [self.locationService requestCurrentLocation];
}

- (void)sidePanel:(SidePanelViewController *)panel
    didRequestTrajectoryFromDate:(NSDate *)startDate
                          toDate:(NSDate *)endDate {
    [self stopLiveTracking];
    [self.sidePanelViewController setBusy:YES];
    [self.sidePanelViewController setStatusText:@"Loading trajectory…" isError:NO];
    [self loadTrajectoryFromDate:startDate toDate:endDate autoplay:YES playheadDate:nil];
}

- (void)sidePanel:(SidePanelViewController *)panel
    didRequestPassSearchAtDate:(NSDate *)date
                      radiusKm:(double)radiusKm {
    [self stopLiveTracking];
    [self performPassSearchAtDate:date radiusKm:radiusKm];
}

- (void)sidePanelDidRequestLiveTracking:(SidePanelViewController *)panel {
    if (self.liveTracking) {
        [self stopLiveTracking];
        [self.sidePanelViewController setStatusText:@"Live tracking stopped." isError:NO];
        return;
    }
    [self startLiveTracking];
}

- (void)sidePanelDidRequestClear:(SidePanelViewController *)panel {
    [self stopLiveTracking];
    [self.playbackBarController unloadTrajectory];
    self.trajectory = nil;
    [self.mapViewController clearTrajectory];
    [self.sidePanelViewController setPassResults:@[]];
    [self.sidePanelViewController setClearEnabled:NO];
    [self.sidePanelViewController setStatusText:@"Trajectory cleared from the map and the list." isError:NO];
}

- (void)sidePanel:(SidePanelViewController *)panel didSelectSearchResult:(TrajectorySearchResult *)result {
    [self stopLiveTracking];
    [self.playbackBarController pause];
    [self.playbackBarController seekToTime:result.timestamp];
    [self.mapViewController centerOnCoordinate:result.position.coordinate longitudeSpan:30.0];
    NSString *message = [NSString stringWithFormat:@"%@ — distance %@, altitude %@ km, %@.",
                         [TimeFormatter shortDateTimeStringFromTimestamp:result.timestamp],
                         [TimeFormatter distanceStringFromKilometers:result.distanceKm],
                         [TimeFormatter numberStringFromValue:result.position.altitude fractionDigits:0],
                         [result.position visibilityDisplayName]];
    [self.sidePanelViewController setStatusText:message isError:NO];
}

- (void)sidePanel:(SidePanelViewController *)panel didChangeFollowISS:(BOOL)followISS {
    self.mapViewController.followsISS = followISS;
}

#pragma mark - PlaybackBarControllerDelegate

- (void)playbackBar:(PlaybackBarController *)bar didUpdatePlayheadTime:(NSTimeInterval)time {
    if (self.trajectory) {
        [self.mapViewController updatePlayheadTime:time trajectory:self.trajectory];
    }
}

#pragma mark - LocationServiceDelegate

- (void)locationService:(LocationService *)service didUpdateLocation:(CLLocation *)location {
    BOOL wasDefaultRequest = self.pendingDefaultLocation;
    self.pendingDefaultLocation = NO;
    NSLog(@"[ISSTracker] current location: %.3f,%.3f default=%d",
          location.coordinate.latitude, location.coordinate.longitude, wasDefaultRequest);
    [self setReferenceCoordinate:location.coordinate name:@"My Location"];
    if (wasDefaultRequest) {
        // Don't steal the camera from the ISS view; the pin and the panel label update.
        [self.sidePanelViewController setStatusText:@"Using your current location as the default location."
                                            isError:NO];
    } else {
        [self.mapViewController centerOnCoordinate:location.coordinate longitudeSpan:12.0];
        [self.sidePanelViewController setStatusText:@"Centered on your location." isError:NO];
    }
}

- (void)locationService:(LocationService *)service didFailWithError:(NSError *)error {
    BOOL wasDefaultRequest = self.pendingDefaultLocation;
    self.pendingDefaultLocation = NO;
    NSString *message = error.localizedDescription;
    if (wasDefaultRequest) {
        message = [NSString stringWithFormat:@"Current location unavailable (%@). Search for a place or click the map.",
                   error.localizedDescription];
    }
    NSLog(@"[ISSTracker] location unavailable: %@ (default=%d)", error.localizedDescription, wasDefaultRequest);
    [self.sidePanelViewController setStatusText:message isError:YES];
}

#pragma mark - Keyboard shortcuts

- (void)installKeyboardMonitor {
    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                           handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return event;

        NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        if (modifiers & NSEventModifierFlagCommand) {
            NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
            if ([characters isEqualToString:@"r"]) {
                [self replayTrajectory];
                return nil;
            }
            if ([characters isEqualToString:@"l"]) {
                [self reloadTrajectory];
                return nil;
            }
            return event;
        }

        // Space toggles playback unless the user is typing.
        if (event.keyCode == 49 && (modifiers & (NSEventModifierFlagOption | NSEventModifierFlagControl)) == 0) {
            NSResponder *firstResponder = self.window.firstResponder;
            if ([firstResponder isKindOfClass:[NSTextView class]]) {
                return event;
            }
            [self togglePlayPause];
            return nil;
        }
        return event;
    }];
}

- (void)togglePlayPause {
    [self.playbackBarController togglePlayPause];
}

- (void)replayTrajectory {
    [self.playbackBarController replay];
}

#pragma mark - NSSplitViewDelegate

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view {
    return view != self.sidePanelViewController.view;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return MAX(proposedMinimumPosition, 600);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return MIN(proposedMaximumPosition, splitView.bounds.size.width - 340);
}

@end
