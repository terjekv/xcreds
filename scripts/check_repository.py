#!/usr/bin/env python3
"""Validate configuration and release metadata without installing anything."""
import json
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).decode().split("\0")
    checked = 0
    for name in filter(None, names):
        path = ROOT / name
        if not path.is_file():
            continue
        if path.suffix in {".plist", ".mobileconfig", ".configprofile", ".entitlements"}:
            data = plistlib.loads(path.read_bytes())
            if path.suffix in {".mobileconfig", ".configprofile"}:
                for payload in data.get("PayloadContent", []):
                    assert payload.get("PayloadType") != "com.twocanoes.xcreds", f"Wrong preference domain: {name}"
        elif path.suffix == ".json":
            json.loads(path.read_text())
        elif path.suffix in {".xib", ".xcscheme"}:
            ET.parse(path)
        elif path.suffix == ".sh":
            subprocess.run(["bash", "-n", str(path)], check=True)
        else:
            continue
        checked += 1

    project = (ROOT / "XCreds.xcodeproj/project.pbxproj").read_text()
    versions = set(re.findall(r"MARKETING_VERSION = ([\d.]+);", project))
    builds = set(re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", project))
    assert len(versions) == 1, f"Inconsistent bundle versions: {versions}"
    assert len(builds) == 1, f"Inconsistent build numbers: {builds}"
    version, build = versions.pop(), builds.pop()
    manifest = plistlib.loads((ROOT / "Profile Manifest/no.uio.math.xcreds.plist").read_bytes())
    jamf = json.loads((ROOT / "Profile Manifest/jamf/no.uio.math.xcreds.json").read_text())
    expected = f"XCreds {version} ({build}) OAuth Settings"
    assert manifest["pfm_description"] == expected
    assert jamf["description"] == expected
    print(f"Validated {checked} configuration/script files; version {version} ({build})")


if __name__ == "__main__":
    main()
