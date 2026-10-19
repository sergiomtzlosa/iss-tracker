# ISS Tracker

A native macOS application that tracks the International Space Station (NORAD 25544) in real-time on a MapKit map, animates its ground track, and searches for passes over any location at a given date and time.

## Features

- **Live Tracking**: Real-time ISS position with automatic updates every 15 seconds
- **Trajectory Animation**: Visualize the ISS ground track over customizable time windows (90 minutes, 24 hours, or custom ranges)
- **Playback Controls**: Play, pause, stop, and replay animations with adjustable speed (1x, 5x, 20x, 60x)
- **Location Search**: Search for any location, use your current position, or click the map to set a reference point
- **Pass Prediction**: Find when the ISS will pass over a specific location within a given radius
- **Dateline-Safe Rendering**: Properly handles trajectory visualization across the +/- 180 degree meridian

## Tech Stack

- **Language**: Objective-C with ARC
- **Frameworks**: AppKit, MapKit, CoreLocation
- **Project Management**: XcodeGen
- **UI**: Programmatic Auto Layout (no storyboards)
- **Minimum Target**: macOS 12.0

## Requirements

- macOS 12.0 or later
- Xcode (for building and running)
- XcodeGen (install via Homebrew if not present)

## Building

1. Generate the Xcode project:
```sh
xcodegen generate
```

2. Build from command line:
```sh
xcodebuild -project ISSTracker.xcodeproj -scheme ISSTracker -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

3. Run the application:
```sh
open build/Build/Products/Debug/ISSTracker.app
```

Alternatively, open `ISSTracker.xcodeproj` in Xcode and build/run from there.

### Installing XcodeGen

If you don't have XcodeGen installed:
```sh
brew install xcodegen
```

## Data Source

The application uses the [Where the ISS at?](https://wheretheiss.at/) public API:

- Current position: `GET https://api.wheretheiss.at/v1/satellites/25544`
- Historical/future positions: `GET https://api.wheretheiss.at/v1/satellites/25544/positions`

Position data includes latitude, longitude, altitude, velocity, visibility, and timestamp.

## Usage

### Live Tracking

1. Launch the application
2. The map automatically centers on the ISS current position
3. Click "Track Live Trajectory" to load a +/- 45 minute window around the current time
4. The view updates every 15 seconds with the latest position

### Trajectory Animation

1. Select a time window preset (past/next 90 min, +/- 45 min, past/next 24 h) or choose a custom range
2. Use the playback controls:
   - Play/Pause: Start or pause the animation
   - Stop: Reset to the beginning
   - Replay: Restart from the beginning
   - Scrubber: Jump to any point in the trajectory
   - Speed: Adjust playback speed (1x, 5x, 20x, 60x)

### Finding Passes Over a Location

1. Set a reference location using one of these methods:
   - Search for a location by name
   - Click "Use My Location"
   - Click anywhere on the map
2. Choose a date and time for the search
3. Set the search radius
4. Click "Search Passes"
5. View results in the list (time and distance from reference point)
6. Click any result to jump to that point in the trajectory

## Automated Testing

The application includes environment variable hooks for scripted verification:

### Self-Test Mode

```sh
ISSTRACKER_SELFTEST=1 ./build/Build/Products/Debug/ISSTracker.app/Contents/MacOS/ISSTracker
```

This mode:
- Loads the initial trajectory
- Plays the animation
- Sets a reference location (London)
- Runs a pass search
- Clears the trajectory and starts live tracking
- Quits automatically
- Success indicated by "SELFTEST complete" in logs

### Debug Layout Mode

```sh
ISSTRACKER_DEBUG_LAYOUT=1 ./build/Build/Products/Debug/ISSTracker.app/Contents/MacOS/ISSTracker
```

Logs window, split view, map, sidebar, and playback bar frames for numerical verification of Auto Layout.

## Architecture

### Components

- **AppDelegate**: Application lifecycle and main menu
- **MainWindowController**: Window management, split layout coordination, pass search logic, reference location handling
- **MapViewController**: MapKit view management, annotations, overlays, and map interactions
- **SidePanelViewController**: Location search interface, trajectory range selection, pass search controls, and results display
- **PlaybackBarController**: Transport controls, scrubber, speed selector, and animation timer

### Services

- **ISSDataProvider**: API client with request batching and throttling
- **PlaceSearchService**: Location search and autocomplete wrapper
- **LocationService**: Current location access wrapper

### Models

- **ISSPosition**: Single sampled position with coordinates and metadata
- **Trajectory**: Collection of positions with interpolation and dateline handling
- **TrajectorySearchResult**: Pass prediction and closest approach data

## Project Structure

```
ISS Tracker/
├── Sources/
│   ├── AppDelegate.{h,m}
│   ├── MainWindowController.{h,m}
│   ├── MapViewController.{h,m}
│   ├── SidePanelViewController.{h,m}
│   ├── PlaybackBarController.{h,m}
│   ├── Services/
│   │   ├── ISSDataProvider.{h,m}
│   │   ├── PlaceSearchService.{h,m}
│   │   └── LocationService.{h,m}
│   ├── Models/
│   │   ├── ISSPosition.{h,m}
│   │   ├── Trajectory.{h,m}
│   │   └── TrajectorySearchResult.{h,m}
│   └── Helpers/
│       └── TimeFormatter.{h,m}
├── Resources/
│   └── Info.plist
├── ISSTracker.xcodeproj/
├── project.yml
└── README.md
```

## Development Guidelines

- Use ARC for memory management
- Build UI programmatically with Auto Layout
- Perform all UI updates on the main thread
- Parse network responses off the main thread
- Declare public APIs in headers, keep implementation details in class extensions
- No third-party dependencies
- HTTPS only for network requests

## License

This project is open source. Feel free to use, modify, and distribute as needed.

## Acknowledgments

- ISS position data provided by [Where the ISS at?](https://wheretheiss.at/)
- Built with Apple's MapKit and CoreLocation frameworks
