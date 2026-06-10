# iOS Setup Guide

Everything you need to build and distribute the BLE Attendance app for iOS.
All steps that require Xcode must be done on your macOS machine.

---

## Prerequisites

- macOS with Xcode 15+ installed (get it from the Mac App Store)
- Flutter SDK installed on macOS (`flutter --version` to verify)
- An Apple Developer account — free works for sideloading, paid ($99/yr) is required for TestFlight
- CocoaPods installed

Install CocoaPods if you don't have it:
```bash
sudo gem install cocoapods
```

Or via Homebrew:
```bash
brew install cocoapods
```

---

## Step 1 — Get the code on macOS

Either clone the repo directly on macOS or copy the project over. Make sure you're on the `ios-support` branch:

```bash
git clone <your-repo-url>
cd BLE_Attendance
git checkout ios-support
```

---

## Step 2 — Install Flutter dependencies

```bash
cd mobile/ble_attendance_mobile
flutter pub get
```

---

## Step 3 — Install iOS CocoaPods dependencies

```bash
cd ios
pod install
cd ..
```

This generates `Pods/` and the `Runner.xcworkspace`. Always open the `.xcworkspace` file in Xcode, never the `.xcodeproj`.

---

## Step 4 — Open in Xcode

```bash
open ios/Runner.xcworkspace
```

---

## Step 5 — Register the entitlements file

The `Runner.entitlements` file is already in the repo but Xcode needs to be told about it:

1. In Xcode, select the **Runner** project in the left sidebar
2. Select the **Runner** target
3. Go to **Signing & Capabilities** tab
4. Look for the **Code Signing Entitlements** field
5. Type `Runner/Runner.entitlements` (or click the folder icon and navigate to it)

If you don't see the field directly, click **+ Capability** and add **Background Modes**. Then check:
- ✅ Uses Bluetooth LE accessories

Adding it via Capabilities also auto-populates the entitlements — if both are ticked, you're good.

---

## Step 6 — Set your signing team

Still in **Signing & Capabilities**:

1. Under **Signing**, set **Team** to your Apple Developer account
2. Change the **Bundle Identifier** to something unique like `com.yourname.bleattendance`
   - Must be unique across all Apple devices — `com.example.*` is reserved and will be rejected
3. Let Xcode manage signing automatically (leave "Automatically manage signing" checked)

---

## Step 7 — Verify the deployment target

The minimum iOS version is already set to 13.0 in the project. Verify:

1. Select the **Runner** target → **General** tab
2. Under **Minimum Deployments**, confirm iOS is set to **13.0** or higher

Also check the Podfile at `ios/Podfile`:
```ruby
platform :ios, '13.0'
```

If you change this, run `pod install` again.

---

## Step 8 — Build for testing

### Debug build (fastest, for direct device install via Xcode)

Connect your iPhone via USB, select it as the target in Xcode, then press **Run (▶)**.

Or from terminal:
```bash
flutter run --release
```
Flutter will detect the connected device.

### Release build (for TestFlight / Ad-hoc)

```bash
flutter build ios --release
```

Then in Xcode: **Product → Archive**, and follow the distribution flow.

---

## Getting it onto your friend's iPhone

### Option A — TestFlight (recommended, fully remote)

Requires a paid Apple Developer account ($99/yr).

1. Create an **App ID** at [developer.apple.com](https://developer.apple.com) matching your bundle identifier
2. In Xcode: **Product → Archive**
3. Click **Distribute App → App Store Connect → Upload**
4. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
5. Find your build under **TestFlight**
6. Add your friend as an **External Tester** with their Apple ID email
7. They get an email invite, install the **TestFlight** app from the App Store, and install your build from there
8. No physical presence needed — fully remote

TestFlight builds are valid for 90 days before needing a re-upload.

### Option B — Ad-hoc distribution (no physical presence, but more setup)

Requires a paid Apple Developer account.

1. Get your friend's device **UDID**:
   - Connect to a Mac with Finder, click the device, click the hardware info line until UDID shows, right-click → Copy
   - Or use [udid.io](https://udid.io) — they visit the site on their iPhone and it shows their UDID
2. Add the UDID to your **provisioning profile** at developer.apple.com → Devices → Register
3. Create an **Ad Hoc** provisioning profile that includes their device
4. In Xcode: **Product → Archive → Distribute App → Ad Hoc**
5. This produces a `.ipa` file
6. Share the `.ipa` via a download link (Diawi, TestFlight, or a self-hosted link)
7. Your friend installs it; on first launch they go to **Settings → General → VPN & Device Management** and trust your developer certificate

Ad-hoc certificates expire after 1 year. Device limit is 100 per year.

### Option C — Free account sideload (needs presence or screen share, 7-day expiry)

With a free Apple account you can still install directly to one device via Xcode.

1. Connect their iPhone to your Mac via USB
2. Trust the computer on the iPhone
3. In Xcode, select their device and press **Run**
4. They go to **Settings → General → VPN & Device Management** and trust your certificate
5. The app works for 7 days, then the certificate expires and needs to be re-signed

This is fine for a quick in-person test session but not sustainable.

---

## BLE-specific iOS notes

### Background behaviour

The `Info.plist` and entitlements are already configured with:
- `UIBackgroundModes: bluetooth-central` — allows BLE scanning when backgrounded
- `UIBackgroundModes: bluetooth-peripheral` — allows BLE advertising when backgrounded

iOS will show a blue status bar when an app is using Bluetooth in the background. This is normal.

### First launch permissions

On first launch, iOS will show two permission prompts:
1. Bluetooth access — the user must tap **Allow**
2. Face ID access — the user must tap **Allow** (for the biometric finalization step)

Both must be granted for the app to function fully. If the user denies and wants to re-enable, they go to **Settings → BLE Attendance**.

### Advertising payload

Unlike Android where manufacturer data is used, on iOS the BLE payload is carried in **service data** (`CBAdvertisementDataServiceDataKey`). This is handled transparently in the app — Android devices scanning for the teacher/student will correctly receive it because `flutter_reactive_ble` exposes service data in `DiscoveredDevice.serviceData`.

Teacher and student devices are cross-compatible: an Android teacher can see an iOS student and vice versa.

### Known iOS BLE limitation

iOS limits advertising when the app is in the background to **service UUIDs only** — the service data payload may be dropped in the background peripheral role on some iOS versions. The central (scanning) role works fine in the background.

In practice for this app: the teacher's phone should stay foregrounded during a session (they're looking at the dashboard anyway). Students scanning for the teacher beacon work fine in the background.

---

## Troubleshooting

**`pod install` fails with "CDN: trunk" error**
```bash
pod repo update
pod install
```

**Xcode shows "No account found" for signing**
Go to **Xcode → Settings → Accounts** and add your Apple ID.

**App installs but crashes immediately on device**
Run from Xcode with the device connected to see the crash log in the debug console.

**BLE not working — "Bluetooth not ready" in app**
Make sure the iPhone has Bluetooth on and the app has been granted Bluetooth permission in Settings.

**`flutter build ios` fails with provisioning errors**
Make sure the bundle ID in Xcode matches the App ID registered at developer.apple.com, and that your device's UDID is included in the provisioning profile.

**Entitlements not taking effect**
After editing `Runner.entitlements`, do a clean build: **Product → Clean Build Folder** (Shift+Cmd+K), then rebuild.
