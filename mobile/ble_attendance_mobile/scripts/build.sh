#!/usr/bin/env bash
set -e

API_URL="${API_BASE_URL:-https://ble-attendance-api.onrender.com}"
echo "Building with API_BASE_URL=$API_URL"

# Check Flutter
if ! command -v flutter &>/dev/null; then
  echo "Flutter not found. Installing via snap..."
  sudo snap install flutter --classic
fi

# Check Java 17
if ! java -version 2>&1 | grep -q "17\|21"; then
  echo "Java 17+ not found. Installing..."
  sudo apt-get install -y openjdk-17-jdk
fi

# Check Android SDK
if [ -z "$ANDROID_HOME" ] || ! command -v sdkmanager &>/dev/null; then
  echo "ANDROID_HOME not set or sdkmanager not found."
  echo "Download cmdline-tools from: https://developer.android.com/studio#command-tools"
  echo "Then: export ANDROID_HOME=~/Android/Sdk && export PATH=\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin"
  exit 1
fi

cd "$(dirname "$0")/.."

flutter pub get

flutter build apk --release \
  --dart-define=API_BASE_URL="$API_URL" \
  --split-per-abi \
  --target-platform android-arm,android-arm64

echo ""
echo "APKs built:"
find build/app/outputs/flutter-apk -name '*.apk' | while read f; do
  echo "  $f ($(du -h "$f" | cut -f1))"
done
