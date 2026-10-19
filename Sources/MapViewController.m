#import "MapViewController.h"
#import "ISSPosition.h"

#pragma mark - Annotation models

@interface ISSAnnotation : NSObject <MKAnnotation>
@property (nonatomic) CLLocationCoordinate2D coordinate;
@property (nonatomic, copy) NSString *title;
@end

@implementation ISSAnnotation
@end

@interface ReferenceAnnotation : NSObject <MKAnnotation>
@property (nonatomic) CLLocationCoordinate2D coordinate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@end

@implementation ReferenceAnnotation
@end

#pragma mark - Click-aware map view

@interface ISSMapView : MKMapView
@property (nonatomic, copy) void (^onMapClick)(NSPoint pointInView);
@end

@implementation ISSMapView {
    NSPoint _mouseDownPoint;
}

- (void)mouseDown:(NSEvent *)event {
    _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
    [super mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [super mouseUp:event];
    if (hypot(point.x - _mouseDownPoint.x, point.y - _mouseDownPoint.y) < 4.0) {
        if (self.onMapClick) {
            self.onMapClick(point);
        }
    }
}

@end

#pragma mark - MapViewController

static NSImage *TintedSymbol(NSString *symbolName, NSColor *color, CGFloat pointSize) {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:symbolName];
    if (!image) {
        return nil;
    }
    NSImageSymbolConfiguration *configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightSemibold];
    image = [image imageWithSymbolConfiguration:configuration];
    NSImage *tinted = [NSImage imageWithSize:image.size
                                      flipped:NO
                               drawingHandler:^BOOL(NSRect rect) {
        [image drawInRect:rect];
        [color set];
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
        return YES;
    }];
    return tinted;
}

@interface MapViewController () <MKMapViewDelegate>

@property (nonatomic, strong) ISSMapView *mapView;
@property (nonatomic, strong) ISSAnnotation *issAnnotation;
@property (nonatomic, strong) ReferenceAnnotation *referenceAnnotation;
@property (nonatomic, strong) MKCircle *radiusOverlay;

@property (nonatomic, strong) NSMutableArray<MKPolyline *> *trackOverlays;
@property (nonatomic, strong) NSMutableArray<MKPolyline *> *flownOverlays;
@property (nonatomic, strong) NSMutableArray<MKPolyline *> *highlightOverlays;

@property (nonatomic, strong, nullable) Trajectory *trajectory;
@property (nonatomic) NSUInteger lastFlownPointCount;
@property (nonatomic) BOOL hasCenteredOnISS;
@property (nonatomic) NSTimeInterval lastFollowUpdate;

@end

@implementation MapViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    self.view.wantsLayer = YES;

    ISSMapView *mapView = [[ISSMapView alloc] initWithFrame:self.view.bounds];
    mapView.translatesAutoresizingMaskIntoConstraints = NO;
    mapView.delegate = self;
    mapView.mapType = MKMapTypeMutedStandard;
    mapView.showsCompass = YES;
    mapView.showsScale = YES;
    mapView.showsZoomControls = YES;
    mapView.region = MKCoordinateRegionMake(CLLocationCoordinate2DMake(20.0, 0.0),
                                            MKCoordinateSpanMake(80.0, 140.0));
    __weak typeof(self) weakSelf = self;
    mapView.onMapClick = ^(NSPoint point) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
        [self.delegate mapViewController:self didClickCoordinate:coordinate];
    };
    [self.view addSubview:mapView];
    self.mapView = mapView;

    [NSLayoutConstraint activateConstraints:@[
        [mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.issAnnotation = [[ISSAnnotation alloc] init];
    self.issAnnotation.title = @"ISS";
    self.issAnnotation.coordinate = CLLocationCoordinate2DMake(0, 0);
    self.trackOverlays = [NSMutableArray array];
    self.flownOverlays = [NSMutableArray array];
    self.highlightOverlays = [NSMutableArray array];
    self.followsISS = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.mapView addAnnotation:self.issAnnotation];
}

#pragma mark - Trajectory

- (void)showTrajectory:(Trajectory *)trajectory {
    [self clearTrajectory];
    self.trajectory = trajectory;

    if (trajectory.count > 0) {
        NSArray<MKPolyline *> *polylines = [self polylinesForPositions:trajectory.positions];
        [self.trackOverlays addObjectsFromArray:polylines];
        if (polylines.count > 0) {
            [self.mapView addOverlays:polylines level:MKOverlayLevelAboveRoads];
        }
    }
}

/// Removes the track, flown segment and pass highlights from the map.
- (void)clearTrajectory {
    NSUInteger total = self.trackOverlays.count + self.flownOverlays.count + self.highlightOverlays.count;
    if (total > 0) {
        NSLog(@"[ISSTracker] clearing trajectory overlays: %lu track, %lu flown, %lu highlight",
              (unsigned long)self.trackOverlays.count,
              (unsigned long)self.flownOverlays.count,
              (unsigned long)self.highlightOverlays.count);
    }
    if (self.trackOverlays.count > 0) {
        [self.mapView removeOverlays:self.trackOverlays];
        [self.trackOverlays removeAllObjects];
    }
    if (self.flownOverlays.count > 0) {
        [self.mapView removeOverlays:self.flownOverlays];
        [self.flownOverlays removeAllObjects];
    }
    [self clearPassHighlights];
    self.trajectory = nil;
    self.lastFlownPointCount = 0;
}

- (void)updatePlayheadTime:(NSTimeInterval)time trajectory:(Trajectory *)trajectory {
    self.trajectory = trajectory;
    ISSPosition *position = [trajectory interpolatedPositionAtTime:time];
    if (!position) {
        return;
    }
    self.issAnnotation.coordinate = position.coordinate;

    NSMutableArray<ISSPosition *> *flown = [NSMutableArray array];
    for (ISSPosition *sample in trajectory.positions) {
        if (sample.timestamp > time) break;
        [flown addObject:sample];
    }
    [flown addObject:position];

    if (flown.count != self.lastFlownPointCount || self.flownOverlays.count == 0) {
        self.lastFlownPointCount = flown.count;
        if (self.flownOverlays.count > 0) {
            [self.mapView removeOverlays:self.flownOverlays];
            [self.flownOverlays removeAllObjects];
        }
        if (flown.count > 1) {
            NSArray<MKPolyline *> *polylines = [self polylinesForPositions:flown];
            [self.flownOverlays addObjectsFromArray:polylines];
            if (polylines.count > 0) {
                [self.mapView addOverlays:polylines level:MKOverlayLevelAboveLabels];
            }
        }
    }

    if (self.followsISS) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - self.lastFollowUpdate >= 0.2) {
            self.lastFollowUpdate = now;
            [self.mapView setCenterCoordinate:position.coordinate animated:NO];
        }
    }
}

- (void)updateCurrentPosition:(ISSPosition *)position {
    self.issAnnotation.coordinate = position.coordinate;
    if (!self.hasCenteredOnISS) {
        self.hasCenteredOnISS = YES;
        [self centerOnCoordinate:position.coordinate longitudeSpan:140.0];
    } else if (self.followsISS && self.trajectory == nil) {
        [self.mapView setCenterCoordinate:position.coordinate animated:YES];
    }
}

#pragma mark - Reference pin & pass highlights

- (void)showReferenceCoordinate:(CLLocationCoordinate2D)coordinate
                           name:(NSString *)name
                       radiusKm:(double)radiusKm {
    if (self.referenceAnnotation) {
        [self.mapView removeAnnotation:self.referenceAnnotation];
    }
    if (self.radiusOverlay) {
        [self.mapView removeOverlay:self.radiusOverlay];
        self.radiusOverlay = nil;
    }

    ReferenceAnnotation *annotation = [[ReferenceAnnotation alloc] init];
    annotation.coordinate = coordinate;
    annotation.title = name.length > 0 ? name : @"Selected Location";
    annotation.subtitle = [NSString stringWithFormat:@"%.4f, %.4f",
                           coordinate.latitude, coordinate.longitude];
    self.referenceAnnotation = annotation;
    [self.mapView addAnnotation:annotation];

    if (radiusKm > 0) {
        MKCircle *circle = [MKCircle circleWithCenterCoordinate:coordinate
                                                         radius:radiusKm * 1000.0];
        self.radiusOverlay = circle;
        [self.mapView addOverlay:circle level:MKOverlayLevelAboveRoads];
    }
}

- (void)showPassHighlights:(NSArray<NSArray<ISSPosition *> *> *)segments {
    [self clearPassHighlights];
    for (NSArray<ISSPosition *> *segment in segments) {
        NSArray<MKPolyline *> *polylines = [self polylinesForPositions:segment];
        if (polylines.count > 0) {
            [self.highlightOverlays addObjectsFromArray:polylines];
        }
    }
    if (self.highlightOverlays.count > 0) {
        [self.mapView addOverlays:self.highlightOverlays level:MKOverlayLevelAboveLabels];
    }
}

- (void)clearPassHighlights {
    if (self.highlightOverlays.count > 0) {
        [self.mapView removeOverlays:self.highlightOverlays];
        [self.highlightOverlays removeAllObjects];
    }
}

#pragma mark - Camera

- (void)centerOnCoordinate:(CLLocationCoordinate2D)coordinate longitudeSpan:(double)longitudeSpan {
    double lonSpan = MAX(4.0, MIN(340.0, longitudeSpan));
    double latSpan = MAX(4.0, MIN(160.0, lonSpan * 0.62));
    MKCoordinateRegion region = MKCoordinateRegionMake(coordinate, MKCoordinateSpanMake(latSpan, lonSpan));
    [self.mapView setRegion:[self.mapView regionThatFits:region] animated:YES];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[ISSAnnotation class]]) {
        MKAnnotationView *view = [mapView dequeueReusableAnnotationViewWithIdentifier:@"ISSAnnotation"];
        if (!view) {
            view = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"ISSAnnotation"];
            view.canShowCallout = NO;
            view.displayPriority = MKFeatureDisplayPriorityRequired;
            NSImage *image = TintedSymbol(@"satellite.fill", [NSColor systemOrangeColor], 22);
            if (!image) {
                image = TintedSymbol(@"circle.fill", [NSColor systemOrangeColor], 22);
            }
            view.image = image;
        }
        view.annotation = annotation;
        return view;
    }

    if ([annotation isKindOfClass:[ReferenceAnnotation class]]) {
        MKAnnotationView *view = [mapView dequeueReusableAnnotationViewWithIdentifier:@"ReferencePin"];
        if (!view) {
            view = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"ReferencePin"];
            view.canShowCallout = YES;
            view.image = TintedSymbol(@"mappin.circle.fill", [NSColor systemRedColor], 24);
            view.centerOffset = NSMakePoint(0, 10);
        }
        view.annotation = annotation;
        return view;
    }

    return nil;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKCircle class]] && overlay == self.radiusOverlay) {
        MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle *)overlay];
        renderer.fillColor = [[NSColor systemYellowColor] colorWithAlphaComponent:0.10];
        renderer.strokeColor = [[NSColor systemYellowColor] colorWithAlphaComponent:0.55];
        renderer.lineWidth = 1.0;
        return renderer;
    }

    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolyline *polyline = (MKPolyline *)overlay;
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:polyline];
        renderer.lineJoin = kCGLineJoinRound;
        renderer.lineCap = kCGLineCapRound;
        if ([self.highlightOverlays containsObject:polyline]) {
            renderer.strokeColor = [[NSColor systemYellowColor] colorWithAlphaComponent:0.95];
            renderer.lineWidth = 6.0;
        } else if ([self.flownOverlays containsObject:polyline]) {
            renderer.strokeColor = [[NSColor systemOrangeColor] colorWithAlphaComponent:0.95];
            renderer.lineWidth = 3.5;
        } else {
            renderer.strokeColor = [[NSColor systemBlueColor] colorWithAlphaComponent:0.55];
            renderer.lineWidth = 3.0;
        }
        return renderer;
    }

    return nil;
}

#pragma mark - Polyline helpers

- (NSArray<MKPolyline *> *)polylinesForPositions:(NSArray<ISSPosition *> *)positions {
    NSArray<NSArray<ISSPosition *> *> *segments = [Trajectory segmentsForPositions:positions];
    NSMutableArray<MKPolyline *> *polylines = [NSMutableArray array];
    for (NSArray<ISSPosition *> *segment in segments) {
        NSUInteger count = segment.count;
        if (count < 2) continue;
        CLLocationCoordinate2D *coordinates = malloc(sizeof(CLLocationCoordinate2D) * count);
        for (NSUInteger index = 0; index < count; index++) {
            coordinates[index] = segment[index].coordinate;
        }
        MKPolyline *polyline = [MKPolyline polylineWithCoordinates:coordinates count:count];
        free(coordinates);
        if (polyline) {
            [polylines addObject:polyline];
        }
    }
    return polylines;
}

@end
