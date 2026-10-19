#import "PlaybackBarController.h"
#import "TimeFormatter.h"
#import <QuartzCore/QuartzCore.h>

@interface PlaybackBarController ()

@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *replayButton;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSPopUpButton *speedPopup;
@property (nonatomic, strong) NSTextField *timeLabel;
@property (nonatomic, strong) NSTextField *statsLabel;

@property (nonatomic, strong, nullable) Trajectory *trajectory;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic) NSTimeInterval playheadTime;
@property (nonatomic) NSTimeInterval lastTickTime;
@property (nonatomic, readwrite, getter=isPlaying) BOOL playing;
@property (nonatomic) double speed;

@end

@implementation PlaybackBarController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    return self;
}

- (void)loadView {
    NSVisualEffectView *bar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 700, 82)];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.material = NSVisualEffectMaterialHUDWindow;
    bar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    bar.state = NSVisualEffectStateActive;
    bar.wantsLayer = YES;
    bar.layer.cornerRadius = 14;
    bar.layer.masksToBounds = YES;
    bar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.view = bar;

    self.speed = 1.0;

    NSStackView *root = [[NSStackView alloc] init];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeWidth;
    root.spacing = 6;

    NSStackView *controls = [[NSStackView alloc] init];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.alignment = NSLayoutAttributeCenterY;
    controls.spacing = 6;

    self.playButton = [self symbolButton:@"play.fill" tooltip:@"Play (Space)" action:@selector(playPressed:)];
    self.pauseButton = [self symbolButton:@"pause.fill" tooltip:@"Pause (Space)" action:@selector(pausePressed:)];
    self.stopButton = [self symbolButton:@"stop.fill" tooltip:@"Stop" action:@selector(stopPressed:)];
    self.replayButton = [self symbolButton:@"arrow.counterclockwise" tooltip:@"Replay (⌘R)" action:@selector(replayPressed:)];
    for (NSButton *button in @[self.playButton, self.pauseButton, self.stopButton, self.replayButton]) {
        [controls addArrangedSubview:button];
    }

    self.slider = [[NSSlider alloc] init];
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    self.slider.continuous = YES;
    self.slider.minValue = 0;
    self.slider.maxValue = 1;
    self.slider.doubleValue = 0;
    self.slider.target = self;
    self.slider.action = @selector(sliderChanged:);
    [self.slider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [controls addArrangedSubview:self.slider];

    self.speedPopup = [[NSPopUpButton alloc] init];
    self.speedPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.speedPopup addItemsWithTitles:@[@"1×", @"5×", @"20×", @"60×"]];
    self.speedPopup.target = self;
    self.speedPopup.action = @selector(speedChanged:);
    NSLayoutConstraint *popupWidth = [self.speedPopup.widthAnchor constraintEqualToConstant:76];
    popupWidth.priority = NSLayoutPriorityDefaultHigh;
    popupWidth.active = YES;
    [controls addArrangedSubview:self.speedPopup];
    [root addArrangedSubview:controls];

    NSStackView *labels = [[NSStackView alloc] init];
    labels.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    labels.alignment = NSLayoutAttributeCenterY;
    labels.spacing = 16;

    self.timeLabel = [NSTextField labelWithString:@"No trajectory loaded"];
    self.timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.timeLabel.textColor = [NSColor secondaryLabelColor];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.timeLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labels addArrangedSubview:self.timeLabel];

    self.statsLabel = [NSTextField labelWithString:@""];
    self.statsLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.statsLabel.textColor = [NSColor secondaryLabelColor];
    self.statsLabel.alignment = NSTextAlignmentRight;
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statsLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labels addArrangedSubview:self.statsLabel];
    [root addArrangedSubview:labels];

    // The stack's own cross-axis alignment runs at NSLayoutPriorityDefaultLow, so rows
    // with an intrinsic width would stay narrow; pin them to the bar's inner width.
    for (NSView *row in root.arrangedSubviews) {
        [row.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    }

    [bar addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [root.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-14],
        [root.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10],
        [root.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-10],
    ]];

    [self updateControls];
    [self updateLabels];
}

- (NSButton *)symbolButton:(NSString *)symbol tooltip:(NSString *)tooltip action:(SEL)action {
    NSButton *button = [[NSButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
    button.toolTip = tooltip;
    button.title = @"";
    button.target = self;
    button.action = action;
    button.contentTintColor = [NSColor whiteColor];
    NSLayoutConstraint *width = [button.widthAnchor constraintEqualToConstant:32];
    NSLayoutConstraint *height = [button.heightAnchor constraintEqualToConstant:26];
    width.priority = NSLayoutPriorityDefaultHigh;
    height.priority = NSLayoutPriorityDefaultHigh;
    width.active = YES;
    height.active = YES;
    return button;
}

- (void)dealloc {
    [_timer invalidate];
}

#pragma mark - Public API

- (BOOL)hasTrajectory {
    return self.trajectory.count > 1;
}

- (void)loadTrajectory:(Trajectory *)trajectory {
    [self pause];
    self.trajectory = trajectory;
    self.playheadTime = trajectory.startTime;
    [self updateControls];
    [self updateLabels];
    [self updateSlider];
    [self notifyDelegate];
}

/// Drops the loaded trajectory and returns the bar to its idle "no trajectory" state.
- (void)unloadTrajectory {
    self.playing = NO;
    [self.timer invalidate];
    self.timer = nil;
    self.trajectory = nil;
    self.playheadTime = 0;
    [self updateControls];
    [self updateLabels];
    [self updateSlider];
    [self notifyDelegate];
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!self.trajectory) {
        return;
    }
    self.playheadTime = MAX(self.trajectory.startTime, MIN(self.trajectory.endTime, time));
    if (self.playing) {
        self.lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    }
    [self updateLabels];
    [self updateSlider];
    [self notifyDelegate];
}

- (void)play {
    if (!self.hasTrajectory) {
        return;
    }
    if (self.playheadTime >= self.trajectory.endTime - 0.001) {
        self.playheadTime = self.trajectory.startTime;
    }
    self.playing = YES;
    self.lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    [self startTimer];
    [self updateControls];
    [self updateLabels];
    [self notifyDelegate];
}

- (void)pause {
    if (!self.playing) {
        return;
    }
    self.playing = NO;
    [self.timer invalidate];
    self.timer = nil;
    [self updateControls];
    [self notifyDelegate];
}

- (void)stop {
    self.playing = NO;
    [self.timer invalidate];
    self.timer = nil;
    if (self.trajectory) {
        self.playheadTime = self.trajectory.startTime;
    }
    [self updateControls];
    [self updateLabels];
    [self updateSlider];
    [self notifyDelegate];
}

- (void)replay {
    if (!self.hasTrajectory) {
        return;
    }
    self.playheadTime = self.trajectory.startTime;
    [self play];
}

- (void)togglePlayPause {
    if (self.playing) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Actions

- (void)playPressed:(id)sender {
    [self play];
}

- (void)pausePressed:(id)sender {
    [self pause];
}

- (void)stopPressed:(id)sender {
    [self stop];
}

- (void)replayPressed:(id)sender {
    [self replay];
}

- (void)sliderChanged:(NSSlider *)slider {
    if (!self.trajectory) {
        return;
    }
    self.playheadTime = self.trajectory.startTime +
        slider.doubleValue * (self.trajectory.endTime - self.trajectory.startTime);
    if (self.playing) {
        self.lastTickTime = [NSDate timeIntervalSinceReferenceDate];
    }
    [self updateLabels];
    [self notifyDelegate];
}

- (void)speedChanged:(NSPopUpButton *)popup {
    NSArray<NSNumber *> *speeds = @[@1, @5, @20, @60];
    NSInteger index = popup.indexOfSelectedItem;
    if (index >= 0 && index < (NSInteger)speeds.count) {
        self.speed = speeds[index].doubleValue;
    }
}

#pragma mark - Clock

- (void)startTimer {
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf tick];
    }];
    timer.tolerance = 1.0 / 60.0;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.timer = timer;
}

- (void)tick {
    if (!self.playing || !self.trajectory) {
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval delta = MAX(0, now - self.lastTickTime);
    self.lastTickTime = now;
    self.playheadTime += delta * self.speed;

    if (self.playheadTime >= self.trajectory.endTime) {
        self.playheadTime = self.trajectory.endTime;
        self.playing = NO;
        [self.timer invalidate];
        self.timer = nil;
    }
    [self updateLabels];
    [self updateSlider];
    [self updateControls];
    [self notifyDelegate];
}

- (void)notifyDelegate {
    [self.delegate playbackBar:self didUpdatePlayheadTime:self.playheadTime];
}

#pragma mark - UI updates

- (void)updateControls {
    self.playButton.enabled = self.hasTrajectory && !self.playing;
    self.pauseButton.enabled = self.hasTrajectory && self.playing;
    self.stopButton.enabled = self.hasTrajectory;
    self.replayButton.enabled = self.hasTrajectory;
    self.slider.enabled = self.hasTrajectory;
    self.speedPopup.enabled = self.hasTrajectory;
}

- (void)updateSlider {
    if (!self.trajectory || self.trajectory.duration <= 0) {
        self.slider.doubleValue = 0;
        return;
    }
    double fraction = (self.playheadTime - self.trajectory.startTime) / self.trajectory.duration;
    self.slider.doubleValue = MAX(0, MIN(1, fraction));
}

- (void)updateLabels {
    if (!self.trajectory) {
        self.timeLabel.stringValue = @"No trajectory loaded";
        self.statsLabel.stringValue = @"";
        return;
    }
    NSString *local = [TimeFormatter localDateTimeStringFromTimestamp:self.playheadTime];
    NSString *utc = [TimeFormatter utcTimeStringFromTimestamp:self.playheadTime];
    self.timeLabel.stringValue = [NSString stringWithFormat:@"%@   ·   %@", local, utc];

    ISSPosition *position = [self.trajectory interpolatedPositionAtTime:self.playheadTime];
    if (position) {
        self.statsLabel.stringValue = [NSString stringWithFormat:@"Alt %@ km   ·   %@ km/h   ·   %@",
                                       [TimeFormatter numberStringFromValue:position.altitude fractionDigits:0],
                                       [TimeFormatter numberStringFromValue:position.velocity fractionDigits:0],
                                       [position visibilityDisplayName]];
    }
}

@end
