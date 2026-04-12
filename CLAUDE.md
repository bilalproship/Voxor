# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voxor is an iOS native application (Swift/UIKit) that includes a custom keyboard extension. The project targets iOS 26.0 and uses Xcode with storyboard-based UI.

## Build & Run

Open in Xcode:
```bash
open Voxor.xcodeproj
```

Build from CLI:
```bash
# Debug build
xcodebuild -scheme Voxor -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Release build
xcodebuild -scheme Voxor -configuration Release
```

No dependency manager (CocoaPods/SPM/Carthage) — the project uses native iOS frameworks only.

## Architecture

Two targets share this repository:

### Voxor (Main App)
- **Entry point:** `AppDelegate` + `SceneDelegate` (iOS 13+ UIScene lifecycle)
- **UI:** Storyboard-based (`Main.storyboard`, `LaunchScreen.storyboard`)
- **Root controller:** `ViewController.swift` — currently a scaffold

### VoxorKeyboard (App Extension)
- **Type:** `com.apple.keyboard-service` extension, embedded in the main app
- **Entry point:** `KeyboardViewController` extending `UIInputViewController`
- **Features:** Next-keyboard button, dark mode support via `UIKeyboardAppearance`, text change callbacks (`textWillChange`/`textDidChange`)

### Key Settings
- Swift 5.0, C++20, `@MainActor` isolation enforced by default
- String Catalogs enabled for localization
- Bundle IDs: `com.edu.practice.Voxor` (app), `com.edu.practice.Voxor.VoxorKeyboard` (extension)
- Code signing: automatic
