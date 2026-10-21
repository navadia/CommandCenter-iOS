"""Writes the SideStore / AltStore source for the latest build (apps.json).

Env: BUILD (CURRENT_PROJECT_VERSION), SIZE (ipa bytes), NOTES (commit subject).
The app's version is 1.0.<BUILD> (set at build time), so SideStore sees each
build as newer than the one installed and offers Update.
"""
import datetime as dt
import json
import os

REPO = "https://github.com/navadia/CommandCenter-iOS"
RAW = "https://raw.githubusercontent.com/navadia/CommandCenter-iOS/main"
build = os.environ["BUILD"]

print(json.dumps({
    "name": "Command Center",
    "identifier": "com.navadia.commandcenter.source",
    "sourceURL": f"{REPO}/releases/download/latest/apps.json",
    "iconURL": f"{RAW}/App/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png",
    "tintColor": "FF7A1A",
    "apps": [{
        "name": "Command Center",
        "bundleIdentifier": "com.navadia.commandcenter",
        "developerName": "Parth Navadia",
        "subtitle": "Every inbox. One list each morning.",
        "localizedDescription": "Your mail sorted by business, what needs you today first, voice and screenshot capture.",
        "iconURL": f"{RAW}/App/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png",
        "tintColor": "FF7A1A",
        "category": "productivity",
        "appPermissions": {"entitlements": ["com.apple.security.application-groups"], "privacy": {}},
        "versions": [{
            "version": f"1.0.{build}",
            "buildVersion": build,
            "date": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": f"Build {build}: {os.environ.get('NOTES', '')}",
            "downloadURL": f"{REPO}/releases/download/latest/CommandCenter.ipa",
            "size": int(os.environ["SIZE"]),
            "minOSVersion": "26.0",
        }],
    }],
    "news": [],
}, indent=2))
