# WAUX - Audio Collection Manager

A native macOS application for managing and playing audio collections, built with SwiftUI and AVFoundation.

## 🎵 Features

- **Native macOS audio player** with full playback controls
- **Audio collection management** with metadata extraction
- **Playlist support** for organizing your music
- **Modern SwiftUI interface** with native macOS design
- **Audio metadata extraction** from ID3 tags and file properties
- **File organization** with tags, ratings, and notes

## 🏗️ Project Structure

```
WAUX/
├── WAUX.xcodeproj/          # Xcode project files
├── WAUX/                    # Main app source code
│   ├── WAUXApp.swift        # App entry point
│   ├── ContentView.swift    # Main interface
│   ├── Views/               # SwiftUI views
│   │   └── AudioPlayerView.swift
│   ├── Models/              # Data models
│   │   ├── AudioTrack.swift
│   │   └── Playlist.swift
│   ├── Services/            # Business logic
│   │   └── AudioService.swift
│   ├── Utils/               # Utility functions
│   └── Assets.xcassets/     # App assets
├── WAUXTests/               # Unit tests
├── WAUXUITests/             # UI tests
└── README.md               # This file
```

## 🚀 Getting Started

### Requirements
- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Building and Running
1. Open `WAUX.xcodeproj` in Xcode
2. Select the WAUX target
3. Choose your development team for code signing
4. Build and run (⌘+R)

## 🎯 Current Status

✅ **Task 1.1: Create Xcode Project Structure** - COMPLETED
- [x] Create new macOS app project in Xcode
- [x] Set up project with SwiftUI and AppKit
- [x] Configure app bundle identifier and signing
- [x] Set up folder structure for organized code
- [x] Configure build settings for macOS deployment target

✅ **Core Features Implemented**
- [x] Basic audio player with play/pause controls
- [x] Audio metadata extraction from files
- [x] AudioTrack and Playlist data models
- [x] Modern SwiftUI interface with sidebar
- [x] Progress tracking and time display

## 🔧 Architecture

### Models
- **AudioTrack**: Represents individual audio files with metadata
- **Playlist**: Collections of audio tracks with management functions

### Services
- **AudioService**: Handles audio playback, metadata extraction, and file management

### Views
- **ContentView**: Main application interface with sidebar and content area
- **AudioPlayerView**: Dedicated audio player controls and progress display

## 🎵 Audio Support

The app supports common audio formats through AVFoundation:
- MP3, AAC, WAV, FLAC, and other formats supported by macOS
- Automatic metadata extraction from ID3 tags
- File properties (duration, file size, bitrate, etc.)

## 🔮 Next Steps

### Planned Features
- [ ] File import dialog and drag-and-drop support
- [ ] Track list view with sorting and filtering
- [ ] Playlist creation and management
- [ ] Audio visualization and waveform display
- [ ] Library management and organization
- [ ] Search and filtering capabilities
- [ ] Export and sharing features

### Technical Improvements
- [ ] Core Data integration for persistent storage
- [ ] Background audio playback
- [ ] Audio effects and equalizer
- [ ] Multi-track selection and batch operations
- [ ] Cloud sync and backup

## 🛠️ Development

### Adding New Features
1. Create models in the `Models/` directory
2. Add business logic in the `Services/` directory
3. Create UI components in the `Views/` directory
4. Update the main ContentView to integrate new features

### Testing
- Unit tests are in `WAUXTests/`
- UI tests are in `WAUXUITests/`
- Run tests with ⌘+U

## 📝 License

This project is part of the Flutter to Native macOS conversion plan.

## 🤝 Contributing

This is a learning project for converting Flutter apps to native macOS applications. The focus is on understanding SwiftUI, AVFoundation, and native macOS development patterns.
