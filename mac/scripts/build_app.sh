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
# being installed system-wide: the licence covers this app, not the Mac. The
# files aren't in the repo - a licensed font isn't ours to hand out - so a
# fresh clone builds without them and falls back to the system serif.
if [ -d Resources/Fonts ]; then
	cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
else
	mkdir -p "$APP/Contents/Resources/Fonts"
	echo "no Resources/Fonts — headlines will fall back to the system serif"
fi

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

# Signed with the self-signed "Client Studio" certificate when it's in the
# keychain, ad hoc otherwise.
#
# This is what stops macOS forgetting the calendar permission on every build.
# An ad-hoc signature's designated requirement is a cdhash, which changes
# every time the binary does, so each build looks like a different app and
# TCC starts again from nothing. A certificate makes the requirement
# "this bundle id, signed by this certificate", which survives a rebuild.
#
# No --entitlements: the time-sensitive entitlement needs a provisioning
# profile from a paid developer account, and a self-signed bundle carrying it
# is refused at launch (RBSRequestErrorDomain 5). Focus break-through is done
# by allowing Intermission in the Focus's own app list instead.
IDENTITY=${INTERMISSION_SIGNING_IDENTITY:-Client Studio}
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
	codesign --force --sign "$IDENTITY" --identifier com.carlwilliamson.intermission "$APP"
	echo "signed with $IDENTITY"
else
	codesign --force --sign - --identifier com.carlwilliamson.intermission "$APP"
	echo "signed ad hoc — macOS will forget its permissions on the next build"
fi
echo "built $APP"
