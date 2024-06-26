#import "SidePanelViewController.h"
#import "PlaceSearchService.h"
#import "TimeFormatter.h"
#import <QuartzCore/QuartzCore.h>

@interface FlippedView : NSView
@end

@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface SidePanelViewController () <NSSearchFieldDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate,
                                      PlaceSearchServiceDelegate, NSPopoverDelegate>

@property (nonatomic, strong) PlaceSearchService *placeSearch;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTextField *referenceLabel;
@property (nonatomic, strong) NSButton *followCheckbox;
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSDatePicker *rangeStartPicker;
@property (nonatomic, strong) NSDatePicker *rangeEndPicker;
@property (nonatomic, strong) NSDatePicker *passDatePicker;
@property (nonatomic, strong) NSSlider *radiusSlider;
@property (nonatomic, strong) NSTextField *radiusValueLabel;
@property (nonatomic, strong) NSButton *loadButton;
@property (nonatomic, strong) NSButton *passButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSButton *liveButton;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTableView *resultsTable;
@property (nonatomic, strong) NSArray<TrajectorySearchResult *> *results;

@property (nonatomic, strong) NSPopover *suggestionsPopover;
@property (nonatomic, strong) NSTableView *suggestionsTable;

@property (nonatomic) BOOL hasReferenceCoordinate;

@end

@implementation SidePanelViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    return self;
}

#pragma mark - View construction

- (void)loadView {
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 364, 800)];
    effectView.material = NSVisualEffectMaterialSidebar;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    self.view = effectView;

    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    [effectView addSubview:scrollView];

    FlippedView *documentView = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 364, 800)];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = documentView;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.spacing = 10;
    [documentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:effectView.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:effectView.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:effectView.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:effectView.bottomAnchor],

        [documentView.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
        [documentView.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-18],
    ]];

    // Header
    NSImageView *headerIcon = [[NSImageView alloc] init];
    headerIcon.translatesAutoresizingMaskIntoConstraints = NO;
    headerIcon.image = [NSImage imageWithSystemSymbolName:@"satellite" accessibilityDescription:@"ISS"];
    headerIcon.contentTintColor = [NSColor systemOrangeColor];
    [headerIcon.widthAnchor constraintEqualToConstant:26].active = YES;
    [headerIcon.heightAnchor constraintEqualToConstant:26].active = YES;

    NSTextField *titleLabel = [self labelWithString:@"ISS Tracker"
                                               font:[NSFont systemFontOfSize:20 weight:NSFontWeightBold]
                                              color:[NSColor labelColor]];
    NSTextField *subtitleLabel = [self labelWithString:@"International Space Station"
                                                  font:[NSFont systemFontOfSize:11]
                                                 color:[NSColor secondaryLabelColor]];
    NSStackView *titleStack = [self verticalStackWithViews:@[titleLabel, subtitleLabel] spacing:1];

    NSStackView *headerRow = [[NSStackView alloc] init];
    headerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    headerRow.alignment = NSLayoutAttributeCenterY;
    headerRow.spacing = 10;
    [headerRow addArrangedSubview:headerIcon];
    [headerRow addArrangedSubview:titleStack];
    [stack addArrangedSubview:headerRow];
    [stack setCustomSpacing:16 afterView:headerRow];

    // Location section
    [stack addArrangedSubview:[self sectionHeader:@"LOCATION"]];
    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = @"Search for a place…";
    self.searchField.delegate = self;
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [stack addArrangedSubview:self.searchField];
    [stack setCustomSpacing:6 afterView:self.searchField];

    NSButton *currentLocationButton = [NSButton buttonWithTitle:@"Use My Location"
                                                         target:self
                                                         action:@selector(currentLocationPressed:)];
    currentLocationButton.bezelStyle = NSBezelStyleRounded;
    currentLocationButton.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:currentLocationButton];

    self.followCheckbox = [NSButton checkboxWithTitle:@"Follow ISS during playback"
                                               target:self
                                               action:@selector(followCheckboxChanged:)];
    self.followCheckbox.state = NSControlStateValueOn;
    [stack addArrangedSubview:self.followCheckbox];

    self.referenceLabel = [self wrappingLabelWithString:@"No location selected.\nSearch above or click the map."
                                                   font:[NSFont systemFontOfSize:11]
                                                  color:[NSColor secondaryLabelColor]];
    [stack addArrangedSubview:self.referenceLabel];
    [stack setCustomSpacing:14 afterView:self.referenceLabel];

    // Trajectory section
    [stack addArrangedSubview:[self sectionHeader:@"TRAJECTORY"]];
    self.presetPopup = [[NSPopUpButton alloc] init];
    self.presetPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.presetPopup addItemsWithTitles:@[
        @"Around now (±45 min)",
        @"Past 90 minutes",
        @"Next 90 minutes",
        @"Past 24 hours",
        @"Next 24 hours",
        @"Custom range"
    ]];
    [self.presetPopup selectItemAtIndex:0];
    self.presetPopup.target = self;
    self.presetPopup.action = @selector(presetChanged:);
    [stack addArrangedSubview:self.presetPopup];

    self.rangeStartPicker = [self datePickerWithDate:[NSDate dateWithTimeIntervalSinceNow:-45 * 60]];
    self.rangeEndPicker = [self datePickerWithDate:[NSDate dateWithTimeIntervalSinceNow:45 * 60]];
    self.rangeStartPicker.target = self;
    self.rangeStartPicker.action = @selector(rangeDateChanged:);
    self.rangeEndPicker.target = self;
    self.rangeEndPicker.action = @selector(rangeDateChanged:);
    [stack addArrangedSubview:[self labeledRow:@"From" control:self.rangeStartPicker]];
    [stack addArrangedSubview:[self labeledRow:@"To" control:self.rangeEndPicker]];

    self.loadButton = [NSButton buttonWithTitle:@"Load Trajectory" target:self action:@selector(loadPressed:)];
    self.loadButton.bezelStyle = NSBezelStyleRounded;
    [stack addArrangedSubview:self.loadButton];
    [stack setCustomSpacing:14 afterView:self.loadButton];

    // Pass search section
    [stack addArrangedSubview:[self sectionHeader:@"FIND ISS PASSES"]];
    NSTextField *passHint = [self wrappingLabelWithString:@"Find when the station passes near your selected location."
                                                     font:[NSFont systemFontOfSize:11]
                                                    color:[NSColor secondaryLabelColor]];
    [stack addArrangedSubview:passHint];

    self.passDatePicker = [self datePickerWithDate:[NSDate date]];
    [stack addArrangedSubview:[self labeledRow:@"At" control:self.passDatePicker]];

    // Keep the three date fields on the same vertical line and same width.
    [NSLayoutConstraint activateConstraints:@[
        [self.rangeStartPicker.widthAnchor constraintEqualToAnchor:self.rangeEndPicker.widthAnchor],
        [self.rangeEndPicker.widthAnchor constraintEqualToAnchor:self.passDatePicker.widthAnchor],
    ]];

    self.radiusSlider = [[NSSlider alloc] init];
    self.radiusSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.radiusSlider.minValue = 100;
    self.radiusSlider.maxValue = 3000;
    self.radiusSlider.doubleValue = 1000;
    self.radiusSlider.continuous = YES;
    self.radiusSlider.target = self;
    self.radiusSlider.action = @selector(radiusChanged:);
    self.radiusValueLabel = [self labelWithString:@"1,000 km"
                                             font:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular]
                                            color:[NSColor secondaryLabelColor]];
    [self.radiusValueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    NSStackView *radiusRow = [[NSStackView alloc] init];
    radiusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    radiusRow.alignment = NSLayoutAttributeCenterY;
    radiusRow.distribution = NSStackViewDistributionFill;
    radiusRow.spacing = 8;
    NSTextField *radiusTitleLabel = [self labelWithString:@"Radius"
                                                     font:[NSFont systemFontOfSize:12]
                                                    color:[NSColor labelColor]];
    [radiusRow addArrangedSubview:radiusTitleLabel];
    [radiusRow addArrangedSubview:self.radiusSlider];
    [radiusRow addArrangedSubview:self.radiusValueLabel];
    [radiusTitleLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.radiusSlider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.radiusValueLabel setContentHuggingPriority:NSLayoutPriorityRequired
                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [stack addArrangedSubview:radiusRow];

    NSView *passButtonRow = [[NSView alloc] init];
    self.passButton = [NSButton buttonWithTitle:@"Search Passes" target:self action:@selector(passSearchPressed:)];
    self.passButton.bezelStyle = NSBezelStyleRounded;
    self.passButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.spinner.hidden = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [passButtonRow addSubview:self.passButton];
    [passButtonRow addSubview:self.spinner];

    // The button fills the whole row; the spinner floats over its trailing end while a
    // search runs and is hidden otherwise, so the button width never changes.
    [NSLayoutConstraint activateConstraints:@[
        [self.passButton.leadingAnchor constraintEqualToAnchor:passButtonRow.leadingAnchor],
        [self.passButton.trailingAnchor constraintEqualToAnchor:passButtonRow.trailingAnchor],
        [self.passButton.topAnchor constraintEqualToAnchor:passButtonRow.topAnchor],
        [self.passButton.bottomAnchor constraintEqualToAnchor:passButtonRow.bottomAnchor],
        [self.spinner.widthAnchor constraintEqualToConstant:16],
        [self.spinner.heightAnchor constraintEqualToConstant:16],
        [self.spinner.trailingAnchor constraintEqualToAnchor:passButtonRow.trailingAnchor constant:-6],
        [self.spinner.centerYAnchor constraintEqualToAnchor:passButtonRow.centerYAnchor],
    ]];
    [stack addArrangedSubview:passButtonRow];

    [stack addArrangedSubview:[self makeResultsTable]];
    self.results = @[];

    self.clearButton = [NSButton buttonWithTitle:@"Clear Trajectory" target:self action:@selector(clearPressed:)];
    self.clearButton.bezelStyle = NSBezelStyleRounded;
    self.clearButton.enabled = NO;
    [stack addArrangedSubview:self.clearButton];

    self.statusLabel = [self wrappingLabelWithString:@"Ready."
                                                font:[NSFont systemFontOfSize:11]
                                               color:[NSColor secondaryLabelColor]];
    [stack addArrangedSubview:self.statusLabel];
    [stack setCustomSpacing:6 afterView:self.statusLabel];

    // Bottom-most control: jump back to the live/near-real-time track.
    self.liveButton = [NSButton buttonWithTitle:@"Track Live Trajectory" target:self action:@selector(livePressed:)];
    self.liveButton.bezelStyle = NSBezelStyleRounded;
    [stack addArrangedSubview:self.liveButton];

    // NSStackView creates its cross-axis (.width) alignment constraints at
    // NSLayoutPriorityDefaultLow, so rows with an intrinsic width stay narrow and drift
    // to the trailing edge instead of filling the panel. Pin every row to the stack
    // width so the whole column lines up.
    for (NSView *row in stack.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    // Ensure the document view grows with its content.
    [documentView.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.contentView.heightAnchor].active = YES;

    self.placeSearch = [[PlaceSearchService alloc] init];
    self.placeSearch.delegate = self;
    [self setupSuggestionsPopover];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateRadiusLabel];
}

#pragma mark - UI factories

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSTextField *)wrappingLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField wrappingLabelWithString:string];
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSTextField *)sectionHeader:(NSString *)title {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    label.textColor = [NSColor tertiaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSStackView *)verticalStackWithViews:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    for (NSView *view in views) {
        [stack addArrangedSubview:view];
    }
    return stack;
}

- (NSDatePicker *)datePickerWithDate:(NSDate *)date {
    NSDatePicker *picker = [[NSDatePicker alloc] init];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    picker.datePickerMode = NSDatePickerModeSingle;
    picker.datePickerElements = NSDatePickerElementFlagYearMonthDay |
                                NSDatePickerElementFlagHourMinuteSecond;
    picker.dateValue = date;
    return picker;
}

- (NSStackView *)labeledRow:(NSString *)title control:(NSView *)control {
    NSTextField *label = [self labelWithString:title
                                          font:[NSFont systemFontOfSize:12]
                                         color:[NSColor labelColor]];
    [label.widthAnchor constraintEqualToConstant:38].active = YES;

    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 8;
    [row addArrangedSubview:label];
    [row addArrangedSubview:control];

    // Fixed-width label column, control fills the rest, so all rows line up.
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [control.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    ]];
    return row;
}

- (NSScrollView *)makeResultsTable {
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = YES;
    [scrollView.heightAnchor constraintEqualToConstant:150].active = YES;

    NSTableView *table = [[NSTableView alloc] init];
    table.headerView = nil;
    table.rowHeight = 22;
    table.allowsMultipleSelection = NO;
    table.allowsEmptySelection = YES;
    table.delegate = self;
    table.dataSource = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"result"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [table addTableColumn:column];
    scrollView.documentView = table;
    self.resultsTable = table;
    return scrollView;
}

#pragma mark - Popover suggestions

- (void)setupSuggestionsPopover {
    NSTableView *table = [[NSTableView alloc] init];
    table.headerView = nil;
    table.rowHeight = 26;
    table.allowsMultipleSelection = NO;
    table.allowsEmptySelection = YES;
    table.delegate = self;
    table.dataSource = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"suggestion"];
    column.width = 310;
    [table addTableColumn:column];
    self.suggestionsTable = table;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 320, 220)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = YES;
    scroll.documentView = table;

    NSViewController *content = [[NSViewController alloc] init];
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 220)];
    scroll.frame = contentView.bounds;
    [contentView addSubview:scroll];
    content.view = contentView;
    content.preferredContentSize = NSMakeSize(320, 220);

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = content;
    popover.contentSize = NSMakeSize(320, 220);
    popover.behavior = NSPopoverBehaviorTransient;
    popover.delegate = self;
    self.suggestionsPopover = popover;
}

- (void)showSuggestionsIfNeeded {
    if (self.placeSearch.results.count == 0) {
        [self.suggestionsPopover close];
        return;
    }
    if (self.suggestionsPopover.shown) {
        return;
    }
    [self.suggestionsPopover showRelativeToRect:self.searchField.bounds
                                         ofView:self.searchField
                                  preferredEdge:NSRectEdgeMaxY];
}

#pragma mark - PlaceSearchServiceDelegate

- (void)placeSearchServiceDidUpdateResults:(PlaceSearchService *)service {
    [self.suggestionsTable reloadData];
    [self showSuggestionsIfNeeded];
}

#pragma mark - Table view

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.suggestionsTable) {
        return (NSInteger)self.placeSearch.results.count;
    }
    return (NSInteger)self.results.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.font = [NSFont systemFontOfSize:12];
    [cell addSubview:label];
    cell.textField = label;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];

    if (tableView == self.suggestionsTable) {
        if (row < (NSInteger)self.placeSearch.results.count) {
            MKLocalSearchCompletion *completion = self.placeSearch.results[row];
            NSString *subtitle = completion.subtitle.length > 0
                ? [NSString stringWithFormat:@"  —  %@", completion.subtitle] : @"";
            label.stringValue = [completion.title stringByAppendingString:subtitle];
            label.toolTip = label.stringValue;
        }
    } else {
        if (row < (NSInteger)self.results.count) {
            TrajectorySearchResult *result = self.results[row];
            NSString *time = [TimeFormatter shortDateTimeStringFromTimestamp:result.timestamp];
            NSString *prefix = result.withinRadius ? @"Pass" : @"Closest";
            label.stringValue = [NSString stringWithFormat:@"%@  ·  %@  ·  %@",
                                 prefix, time, [TimeFormatter distanceStringFromKilometers:result.distanceKm]];
        }
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *table = notification.object;
    NSInteger row = table.selectedRow;
    if (row < 0) {
        return;
    }

    if (table == self.suggestionsTable) {
        if (row < (NSInteger)self.placeSearch.results.count) {
            MKLocalSearchCompletion *completion = self.placeSearch.results[row];
            [self resolveCompletion:completion];
        }
    } else if (table == self.resultsTable) {
        if (row < (NSInteger)self.results.count) {
            [self.delegate sidePanel:self didSelectSearchResult:self.results[row]];
        }
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) {
        [self.placeSearch updateQuery:self.searchField.stringValue];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control != self.searchField) {
        return NO;
    }
    if (commandSelector == @selector(insertNewline:)) {
        if (self.placeSearch.results.count > 0) {
            [self resolveCompletion:self.placeSearch.results.firstObject];
        } else {
            [self setStatusText:@"No matching place found." isError:YES];
        }
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self.suggestionsPopover close];
        return YES;
    }
    return NO;
}

- (void)resolveCompletion:(MKLocalSearchCompletion *)completion {
    [self.suggestionsPopover close];
    self.searchField.stringValue = completion.title;
    __weak typeof(self) weakSelf = self;
    [self.placeSearch resolveCompletion:completion completion:^(MKMapItem *item, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (!item) {
                [self setStatusText:error.localizedDescription ?: @"Could not resolve this location." isError:YES];
                return;
            }
            CLLocationCoordinate2D coordinate = item.placemark.coordinate;
            NSString *name = item.name.length > 0 ? item.name : completion.title;
            [self.delegate sidePanel:self didSelectCoordinate:coordinate name:name];
        });
    }];
}

#pragma mark - Actions

- (void)currentLocationPressed:(id)sender {
    [self.delegate sidePanelDidRequestCurrentLocation:self];
}

- (void)followCheckboxChanged:(id)sender {
    [self.delegate sidePanel:self didChangeFollowISS:self.followCheckbox.state == NSControlStateValueOn];
}

- (void)presetChanged:(id)sender {
    NSDate *now = [NSDate date];
    NSInteger index = self.presetPopup.indexOfSelectedItem;
    NSDate *start = nil;
    NSDate *end = nil;
    switch (index) {
        case 0:
            start = [now dateByAddingTimeInterval:-45 * 60];
            end = [now dateByAddingTimeInterval:45 * 60];
            break;
        case 1:
            start = [now dateByAddingTimeInterval:-90 * 60];
            end = now;
            break;
        case 2:
            start = now;
            end = [now dateByAddingTimeInterval:90 * 60];
            break;
        case 3:
            start = [now dateByAddingTimeInterval:-24 * 3600];
            end = now;
            break;
        case 4:
            start = now;
            end = [now dateByAddingTimeInterval:24 * 3600];
            break;
        default:
            return;
    }
    self.rangeStartPicker.dateValue = start;
    self.rangeEndPicker.dateValue = end;
}

- (void)rangeDateChanged:(id)sender {
    [self.presetPopup selectItemAtIndex:5];
}

- (void)radiusChanged:(id)sender {
    [self updateRadiusLabel];
}

- (double)radiusKm {
    return self.radiusSlider.doubleValue;
}

- (void)updateRadiusLabel {
    self.radiusValueLabel.stringValue = [TimeFormatter distanceStringFromKilometers:self.radiusSlider.doubleValue];
}

- (void)loadPressed:(id)sender {
    NSDate *start = self.rangeStartPicker.dateValue;
    NSDate *end = self.rangeEndPicker.dateValue;
    if ([end timeIntervalSinceDate:start] < 60) {
        [self setStatusText:@"The end time must be after the start time." isError:YES];
        return;
    }
    [self.delegate sidePanel:self didRequestTrajectoryFromDate:start toDate:end];
}

- (void)passSearchPressed:(id)sender {
    if (!self.hasReferenceCoordinate) {
        [self setStatusText:@"Choose a location first — search, use your location, or click the map." isError:YES];
        return;
    }
    [self.delegate sidePanel:self
        didRequestPassSearchAtDate:self.passDatePicker.dateValue
                          radiusKm:self.radiusSlider.doubleValue];
}

- (void)clearPressed:(id)sender {
    [self.delegate sidePanelDidRequestClear:self];
}

- (void)livePressed:(id)sender {
    [self.delegate sidePanelDidRequestLiveTracking:self];
}

#pragma mark - External updates

- (void)setReferenceLocationName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    self.hasReferenceCoordinate = YES;
    self.referenceLabel.stringValue = [NSString stringWithFormat:@"%@\n%.4f, %.4f",
                                       name.length > 0 ? name : @"Selected location",
                                       coordinate.latitude, coordinate.longitude];
}

- (void)setStatusText:(NSString *)text isError:(BOOL)isError {
    self.statusLabel.stringValue = text ?: @"";
    self.statusLabel.textColor = isError ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
}

- (void)setBusy:(BOOL)busy {
    self.spinner.hidden = !busy;
    if (busy) {
        [self.spinner startAnimation:nil];
    } else {
        [self.spinner stopAnimation:nil];
    }
    self.loadButton.enabled = !busy;
    self.passButton.enabled = !busy;
}

- (void)setClearEnabled:(BOOL)enabled {
    self.clearButton.enabled = enabled;
}

- (void)setLiveTrackingActive:(BOOL)active {
    self.liveButton.title = active ? @"Stop Live Tracking" : @"Track Live Trajectory";
}

- (void)setPassResults:(NSArray<TrajectorySearchResult *> *)results {
    self.results = results ?: @[];
    [self.resultsTable reloadData];
}

- (void)setTrajectoryRangeStartDate:(NSDate *)startDate endDate:(NSDate *)endDate {
    self.rangeStartPicker.dateValue = startDate;
    self.rangeEndPicker.dateValue = endDate;
}

- (void)setFollowISS:(BOOL)followISS {
    self.followCheckbox.state = followISS ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    if (notification.object == self.suggestionsPopover) {
        [self.suggestionsTable deselectAll:nil];
    }
}

@end
