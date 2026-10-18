#!/usr/bin/env python3
"""Prüft ein lokales CloudKit-Profil und erzeugt die begrenzten Build-Einstellungen."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def validate(profile, platform, team, bundle, container, environment, identities):
    entitlements = profile.get("Entitlements", {})
    app_key = "com.apple.application-identifier" if platform == "macos" else "application-identifier"
    expected_platform = "OSX" if platform == "macos" else "iOS"
    if profile.get("TeamIdentifier") != [team] or expected_platform not in profile.get("Platform", []):
        raise ValueError("Team oder Plattform des Profils passt nicht.")
    if entitlements.get(app_key) != f"{team}.{bundle}":
        raise ValueError("Das Profil muss die explizite App-Kennung enthalten.")
    if entitlements.get("com.apple.developer.icloud-container-identifiers") != [container]:
        raise ValueError("Das Profil muss ausschließlich den gewählten Container erlauben.")
    services = entitlements.get("com.apple.developer.icloud-services", [])
    if services != "*" and (not isinstance(services, list) or "CloudKit" not in services):
        raise ValueError("Das Profil erlaubt CloudKit nicht.")
    environments = entitlements.get("com.apple.developer.icloud-container-environment", [])
    if isinstance(environments, str):
        environments = [environments]
    if environment not in environments:
        raise ValueError("Das Profil erlaubt die gewählte CloudKit-Umgebung nicht.")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime.datetime) or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Das Profil ist abgelaufen oder enthält kein gültiges Ablaufdatum.")
    allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    matching = sorted(allowed.intersection(identities))
    if len(matching) != 1:
        raise ValueError("Genau eine gültige lokale Signieridentität muss zum Profil passen.")
    return matching[0], {
        app_key: f"{team}.{bundle}",
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.icloud-container-identifiers": [container],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-environment": environment,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--platform", choices=["macos", "ios"], required=True)
    parser.add_argument("--team", default="9QSWKSR4NQ")
    parser.add_argument("--bundle", default="com.viben.SavageModPlayer")
    parser.add_argument("--container", default="iCloud.com.viben.SavageModPlayer")
    parser.add_argument("--environment", choices=["Development", "Production"], default="Development")
    parser.add_argument("--identity", default="")
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    for value in [args.team, args.bundle, args.container]:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
            raise ValueError("Ungültige Kennung.")
    raw = subprocess.check_output(["security", "cms", "-D", "-i", str(args.profile)], stderr=subprocess.PIPE)
    profile = plistlib.loads(raw)
    listing = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    identities = set()
    for line in listing.splitlines():
        match = re.search(r"\b[0-9A-F]{40}\b", line)
        if match and (not args.identity or args.identity == match[0] or f'"{args.identity}"' in line):
            identities.add(match[0])
    identity, entitlements = validate(profile, args.platform, args.team, args.bundle, args.container, args.environment, identities)
    root = args.output_directory.resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    entitlement_path = root / "CloudKit.entitlements"
    with entitlement_path.open("wb") as handle:
        plistlib.dump(entitlements, handle)
    entitlement_path.chmod(0o600)
    configuration_path = root / "CloudKit.xcconfig"
    values = {
        "SAVAGE_APP_SIGN_STYLE": "Manual",
        "SAVAGE_CLOUDKIT_PROFILE_SPECIFIER": profile["UUID"],
        "SAVAGE_CLOUDKIT_CONDITION": "SAVAGE_CLOUDKIT_ENABLED",
        "SAVAGE_CLOUDKIT_CONTAINER": args.container,
        "SAVAGE_CLOUDKIT_ENVIRONMENT": args.environment,
        "SAVAGE_CLOUDKIT_ENTITLEMENTS": str(entitlement_path),
        "SAVAGE_APP_CODE_SIGN_IDENTITY": identity,
    }
    if any(any(c in value for c in '\n\r"\\') or "//" in value for value in values.values()):
        raise ValueError("Build-Einstellungen enthalten nicht unterstützte Zeichen.")
    configuration_path.write_text("".join(f'{key} = {value}\n' for key, value in values.items()))
    configuration_path.chmod(0o600)
    print(json.dumps({"containerIdentifier": args.container, "environment": args.environment,
                      "identity": identity, "profileSpecifier": profile["UUID"],
                      "entitlementsPath": str(entitlement_path), "configurationPath": str(configuration_path)}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException):
        print("FEHLER: CloudKit-Profil oder Signierkonfiguration ungültig; Build abgebrochen.", file=sys.stderr)
        sys.exit(2)
