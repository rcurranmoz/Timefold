# Latent

A privacy-first iOS app that shows you photos from this day in past years.

<div align="center">
  <img src="https://img.shields.io/badge/iOS-26.2+-blue.svg" />
  <img src="https://img.shields.io/badge/Swift-5-orange.svg" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
</div>

## 📱 About

Latent is like Timehop, but actually private. No ads, no account required, and nothing leaves your iPhone.

Every day, Latent shows you photos taken on this date in previous years from your Apple Photos library. It's a simple, beautiful way to revisit your memories without sacrificing your privacy.

**[Download on the App Store](https://apps.apple.com/app/id6758055406)**

## ✨ Features

- 📅 **On this day** — photos from today's date in every past year, one chapter per year
- ✨ **Best of** — near-identical shots collapse into one card, chosen on-device with Vision
- 🎞️ **Live Photos** — press and hold to play
- ❤️ **Favorites** — heart a photo in Latent and it's favorited in Photos, and leads its year
- 🃏 **Daily reveal** — five polaroids from five years, with a special reveal on big anniversaries
- 🧩 **Widgets** — small, medium, large and Lock Screen; turns over at midnight on its own
- 🔔 **Reminders** — only on days worth it, with the photo they're about
- 🐣 **Companions** — Foldy, Luna and Mochi, with hats earned by visiting and seasonal hats
- 🔒 **100% private** — no accounts, no analytics, nothing leaves the device

## 🎯 Privacy First

- **No server** - Everything runs locally on your iPhone
- **No tracking** - Zero analytics or telemetry
- **No ads** - Free, no business model that relies on your data
- **No account** - Just install and use
- **Open source** - You can verify everything yourself

## 🚀 Getting Started

### Requirements

- iOS 26.2+
- Xcode 26+

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

Latent is built with:
- **SwiftUI** - Modern declarative UI
- **PhotoKit** - Apple Photos integration
- **Combine** - Reactive state management

### Key Components

- `ContentView.swift` — the main screen, grid, photo pager, reveal, settings and companions
- `Chapters.swift` — splits a day into year chapters
- `MomentCuration.swift` — groups near-duplicates and picks the best frame (Vision, on-device)
- `LivePhoto.swift` — Live Photo playback in the pager
- `WidgetForecast.swift` — precomputes the next few days for the widget
- `DeepLink.swift` — `latent://day/yyyy-MM-dd?year=N`, used by the widget and notifications
- `TimefoldWidget/` — the widget extension

## 🤝 Contributing

Contributions are welcome! This is a simple app with a focused mission: show your memories privately.

If you have ideas for features that maintain this privacy-first approach, please open an issue or PR.

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

Built with the idea that your memories are yours, and they should stay that way.

## 📬 Contact

- **App Store**: [Latent](https://apps.apple.com/app/id6758055406)
- **Issues**: [GitHub Issues](https://github.com/rcurranmoz/Timefold/issues)

---

<div align="center">
  <p>Made with ❤️ for people who value their privacy</p>
  <p>No venture capital • No exit strategy • Just a good app</p>
</div>
