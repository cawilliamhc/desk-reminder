#!/bin/sh
# Assemble Intermission.app from the SwiftPM build.
#
# A real bundle, not a bare binary: UNUserNotificationCenter needs a bundle
# identifier and a signature, which is what lets notifications carry buttons
# and say "Intermission" rather than "Script Editor".
set -e
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
APP="$PWD/build/Intermission.app"
BIN=$(swift build -c "$CONFIG" --show-bin-path)

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Intermission" "$APP/Contents/MacOS/Intermission"
# GT Ultra rides inside the bundle (ATSApplicationFontsPath) rather than
# being installed system-wide: the licence covers this app, not the Mac.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Intermission</string>
	<key>CFBundleDisplayName</key>
	<string>Intermission</string>
	<key>CFBundleIdentifier</key>
	<string>com.carlwilliamson.intermission</string>
	<key>CFBundleExecutable</key>
	<string>Intermission</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Intermission reads your calendar so it can plan breaks into the gaps between sessions. It never creates or changes an event.</string>
	<!-- GT Ultra, bundled rather than installed. -->
	<key>ATSApplicationFontsPath</key>
	<string>Fonts</string>
	<!-- Menu-bar app: no Dock icon. The window opens from the menu. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Carl Williamson</string>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

# No --entitlements: the time-sensitive entitlement needs a provisioning
# profile from a paid developer account, and an ad-hoc signature carrying it
# is refused at launch (RBSRequestErrorDomain 5). Focus break-through is done
# by allowing Intermission in the Focus's own app list instead.
codesign --force --sign - --identifier com.carlwilliamson.intermission "$APP"
echo "built $APP"
