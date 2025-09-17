# iOS Build & Deployment

This repository uses GitHub Actions to automatically build iOS, Android, and Web versions of the Flutter app.

## 🚀 Build Status

Every push to `main` branch automatically triggers builds for all platforms.

## 📱 Download Builds

After each successful build, you can download the artifacts:

### iOS (.ipa file)
1. Go to [Actions tab](../../actions)
2. Click on the latest successful workflow run
3. Download `ios-build-XXX` artifact
4. Extract the ZIP to get `EvenDemoApp.ipa`

### Android (.apk file)
1. Go to [Actions tab](../../actions)
2. Click on the latest successful workflow run  
3. Download `android-apk-XXX` artifact
4. Extract the ZIP to get `app-release.apk`

### Web Build
1. Go to [Actions tab](../../actions)
2. Click on the latest successful workflow run
3. Download `web-build-XXX` artifact
4. Extract and serve the web files

## 📲 Install on iPhone

### Method 1: TestFlight (Recommended)
1. Get Apple Developer account ($99/year)
2. Upload IPA to App Store Connect
3. Distribute via TestFlight
4. Send invite links to testers

### Method 2: Direct Install
1. Use tools like **3uTools**, **AltStore**, or **Sideloadly**
2. Install the IPA file directly to iPhone
3. Trust the developer certificate in Settings

### Method 3: Xcode (if you have Mac)
1. Download the `ios-build-folder-XXX` artifact
2. Open in Xcode
3. Connect iPhone and run

## 🔄 Manual Build Trigger

You can manually trigger a build:
1. Go to [Actions tab](../../actions)
2. Click "iOS Build and Deploy" workflow
3. Click "Run workflow" button
4. Select branch and click "Run workflow"

## 🛠️ Local Development

For local development on Windows:
```bash
# Web development
flutter run -d web-server

# Android development  
flutter run -d android

# Note: iOS development requires macOS
```

## 📋 Build Configuration

The workflow builds:
- **iOS**: Release mode, no code signing (ready for manual signing)
- **Android**: Release APK (ready to install)
- **Web**: Production build (ready to deploy)

Artifacts are kept for 30 days and can be downloaded anytime.