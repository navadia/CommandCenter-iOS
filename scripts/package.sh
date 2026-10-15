#!/bin/bash
# Fake-sign the app and widget with their entitlements (ldid), then zip into
# an .ipa. SideStore replaces this signature with your Apple ID's, but it
# reads the entitlements (App Groups) from here, so they must be embedded.
set -euo pipefail

APP=build/Build/Products/Release-iphoneos/CommandCenter.app
WIDGET="$APP/PlugIns/CommandCenterWidget.appex"

test -d "$WIDGET" || { echo "Widget extension missing from the app bundle"; exit 1; }

ldid -SWidget/CommandCenterWidget.entitlements "$WIDGET/CommandCenterWidget"
ldid -SApp/CommandCenter.entitlements "$APP/CommandCenter"

echo "Embedded entitlements:"
ldid -e "$APP/CommandCenter"
ldid -e "$WIDGET/CommandCenterWidget"

rm -rf Payload CommandCenter.ipa
mkdir Payload
cp -R "$APP" Payload/
zip -qry CommandCenter.ipa Payload
ls -lh CommandCenter.ipa
