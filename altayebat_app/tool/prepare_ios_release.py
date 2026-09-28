#!/usr/bin/env python3
"""Configure a freshly generated Flutter iOS Runner for Altayebat."""

import argparse
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.altayebat.app"


def configure_project(team_id: str | None, profile_name: str | None) -> None:
    project = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    source = project.read_text()
    source, runner_count = re.subn(
        r"PRODUCT_BUNDLE_IDENTIFIER = (?![^;]*RunnerTests)[^;]+;",
        f"CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        source,
    )
    if runner_count < 2:
        raise RuntimeError("Could not locate Runner bundle identifiers")
    source = re.sub(
        r"PRODUCT_BUNDLE_IDENTIFIER = [^;]*RunnerTests;",
        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.RunnerTests;",
        source,
    )
    source = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", source)
    # The storefront has been designed and tested for phones; iPad needs its
    # own layout pass and App Store screenshots before enabling that family.
    source = re.sub(r"TARGETED_DEVICE_FAMILY = [^;]+;", "TARGETED_DEVICE_FAMILY = 1;", source)
    if team_id and profile_name:
        # Only Runner configurations receive distribution signing. RunnerTests
        # retain generated settings; no test target is archived for release.
        source = source.replace(
            f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
            f"DEVELOPMENT_TEAM = {team_id};\n"
            f"\t\t\t\tCODE_SIGN_STYLE = Manual;\n"
            f"\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = \"{profile_name}\";\n"
            f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
        )
    project.write_text(source)


def configure_info() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    with path.open("rb") as file:
        info = plistlib.load(file)
    info["CFBundleDisplayName"] = "أسواق الطيبات"
    info["NSCameraUsageDescription"] = "نستخدم الكاميرا لمسح باركود المنتجات عند اختيارك هذه الميزة."
    info["NSLocationWhenInUseUsageDescription"] = "نستخدم موقعك لتحديد عنوان التوصيل، ولتحديث موقع المندوب أثناء فتح التطبيق."
    info["UIBackgroundModes"] = ["remote-notification"]
    info["CFBundleURLTypes"] = [
        {"CFBundleURLName": BUNDLE_ID, "CFBundleURLSchemes": ["altayebat"]}
    ]
    with path.open("wb") as file:
        plistlib.dump(info, file)

    # The distribution profile must have Push Notifications enabled. The
    # entitlement's environment is supplied by the signed profile.
    entitlements = ROOT / "ios/Runner/Runner.entitlements"
    with entitlements.open("wb") as file:
        plistlib.dump({"aps-environment": "production"}, file)


def install_icons() -> None:
    source = ROOT.parent / "store_assets/app_icon_1024.png"
    if not source.is_file():
        raise FileNotFoundError(source)
    icon_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((icon_dir / "Contents.json").read_text())
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        width = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].removesuffix("x"))
        pixels = round(width * scale)
        destination = icon_dir / filename
        if pixels == 1024:
            shutil.copyfile(source, destination)
        else:
            subprocess.run(
                ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
                 str(source), "--out", str(destination)],
                check=True,
                stdout=subprocess.DEVNULL,
            )


def export_options(team_id: str, profile_name: str) -> None:
    path = ROOT / "ios/ExportOptions.plist"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as file:
        plistlib.dump(
            {
                "method": "app-store-connect",
                "destination": "export",
                "signingStyle": "manual",
                "signingCertificate": "Apple Distribution",
                "teamID": team_id,
                "provisioningProfiles": {BUNDLE_ID: profile_name},
                "manageAppVersionAndBuildNumber": False,
            },
            file,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team-id")
    parser.add_argument("--profile-name")
    args = parser.parse_args()
    if bool(args.team_id) != bool(args.profile_name):
        parser.error("Team ID and provisioning profile name must be supplied together")
    if args.team_id and not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        parser.error("Invalid Apple Team ID")
    if args.profile_name and not re.fullmatch(r"[\w .()-]+", args.profile_name):
        parser.error("Invalid provisioning profile name")
    configure_project(args.team_id, args.profile_name)
    configure_info()
    install_icons()
    if args.team_id:
        export_options(args.team_id, args.profile_name)


if __name__ == "__main__":
    main()
