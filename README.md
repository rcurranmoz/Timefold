# Timefold

A privacy-first iOS app that shows you photos from this day in past years.

<div align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-blue.svg" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
</div>

## About

Timefold is like Timehop, but actually private. No ads, no account required, and nothing leaves your iPhone.

Every day, Timefold shows you photos taken on this date in previous years from your Apple Photos library. It's a simple, beautiful way to revisit your memories without sacrificing your privacy.

**[Download on the App Store](https://apps.apple.com/us/app/timefold-on-this-day/id6758055406)**

## Features

- **Daily Reveal** - A cinematic opening experience on first launch each day: your memories materialize as scattered polaroids against a rotating retro backdrop, different every day for two weeks
- **Daily Memories** - Automatically shows photos from today's date in past years
- **100% Private** - No accounts, no analytics, no data collection
- **Offline First** - Works entirely on your device using Apple Photos
- **Two View Modes** - Switch between grid and fullscreen viewing
- **Instagram Story Ready** - Share memories with beautiful gradient backgrounds
- **Dark Mode** - Full support with custom dark mode icon
- **Fast & Lightweight** - Native SwiftUI, no dependencies

## 🎯 Privacy First

- **No server** - Everything runs locally on your iPhone
- **No tracking** - Zero analytics or telemetry
- **No ads** - Free, no business model that relies on your data
- **No account** - Just install and use
- **Open source** - You can verify everything yourself

## 🚀 Getting Started

### Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

### Building

1. Clone the repository:
```bash
git clone https://github.com/rcurranmoz/Timefold.git
cd Timefold
```

2. Open in Xcode:
```bash
open Timefold.xcodeproj
```

3. Build and run (⌘R)

No dependencies, no setup required!

## 🏗️ Architecture

Timefold is built with:
- **SwiftUI** - Modern declarative UI
- **PhotoKit** - Apple Photos integration
- **Combine** - Reactive state management

### Key Components

- `ContentView.swift` - Main app interface with view mode toggling
- `MemoriesViewModel` - Photo fetching and filtering logic
- `MemoryPagerView` - Fullscreen photo viewing with sharing
- `MemoriesGridView` - Grid layout with delete functionality
- `DailyRevealView` - Ceremonial first-open animation with retro Miami aesthetic
- `TimefoldWidget` - Home and lock screen widgets

## 📸 Screenshots

*Add your App Store screenshots here*

## 🤝 Contributing

Contributions are welcome! This is a simple app with a focused mission: show your memories privately.

If you have ideas for features that maintain this privacy-first approach, please open an issue or PR.

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

Built with the idea that your memories are yours, and they should stay that way.

## 📬 Contact

- **App Store**: [Timefold](https://apps.apple.com/us/app/timefold-on-this-day/id6758055406)
- **Issues**: [GitHub Issues](https://github.com/rcurranmoz/Timefold/issues)

---

<div align="center">
  <p>Made with ❤️ for people who value their privacy</p>
  <p>No venture capital • No exit strategy • Just a good app</p>
</div>
