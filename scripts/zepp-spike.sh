#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
cd "$repo_root"

binary_path="$repo_root/.build/release/ZeppSpike"
app_path="$repo_root/.build/ZeppSpike.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
plist_path="$contents_path/Info.plist"

if [[ ! -f "$repo_root/.env" ]]; then
  echo "No .env found. Put your 16-byte auth key in .env as: KEY=<32 hex chars>"
  exit 1
fi

echo "Building ZeppSpike..."
swift build --package-path "$repo_root" -c release --product ZeppSpike

echo "Assembling signed app (for Bluetooth permission)..."
mkdir -p "$macos_path"
cp "$binary_path" "$macos_path/ZeppSpike"

cat > "$plist_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ZeppSpike</string>
  <key>CFBundleIdentifier</key><string>com.helio.ZeppSpike</string>
  <key>CFBundleName</key><string>ZeppSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>ZeppSpike runs the ZeppOS auth handshake with the Helio Strap over Bluetooth.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_path"

# Export KEY from .env into the environment (keeps the secret out of argv / ps).
set -a
source "$repo_root/.env"
set +a

# Metric to fetch: restinghr (default) | spo2 | stress | respiratory
metric="${1:-restinghr}"
echo "Running ZeppSpike (metric: $metric). Wear the strap and make sure the Zepp app is closed. Ctrl-C to stop."
KEY="$KEY" METRIC="$metric" "$macos_path/ZeppSpike"
