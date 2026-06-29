#!/usr/bin/env python3
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "platform/macos/Xnheime.xcodeproj"
APP_NAME = "Xnheime.app"
FLYPY_SENTINEL = ROOT / "data/flypy/flypy.dict.yaml"


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def capture(args):
    return subprocess.run(
        args,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout


def apple_development_identity():
    output = capture(["security", "find-identity", "-v", "-p", "codesigning"])
    match = re.search(r'"(Apple Development: .*\([A-Z0-9]+\))"', output)
    return match.group(1) if match else None


def team_id_from_identity(identity):
    if not identity:
        return None

    certificate = capture(["security", "find-certificate", "-c", identity, "-p"])
    if not certificate:
        return None

    subject = subprocess.run(
        ["openssl", "x509", "-noout", "-subject"],
        input=certificate,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout
    match = re.search(r"(?:^|[/, ])OU[ =]([^/,]+)", subject)
    return match.group(1) if match else None


def development_team():
    override = os.environ.get("XNHEIME_DEVELOPMENT_TEAM")
    if override:
        return override
    return team_id_from_identity(apple_development_identity())


def xcodebuild_args(derived_data, extra_args):
    args = [
        "xcodebuild",
        "-project",
        str(PROJECT.relative_to(ROOT)),
        "-scheme",
        "Xnheime",
        "-configuration",
        "Release",
        "-derivedDataPath",
        str(derived_data),
        "-destination",
        "platform=macOS,arch=arm64",
    ]

    team = development_team()
    if team:
        args.append(f"DEVELOPMENT_TEAM={team}")

    return args + extra_args + ["build"]


def ensure_repo_root():
    if not PROJECT.is_dir():
        print("error: run this from the xnheime repository root", file=sys.stderr)
        sys.exit(1)


def ensure_dictionary_data():
    if FLYPY_SENTINEL.is_file():
        return

    print(f"error: missing vendored dictionary data: {FLYPY_SENTINEL}", file=sys.stderr)
    print("run scripts/update_flypy.py to refresh the dictionary snapshot", file=sys.stderr)
    sys.exit(1)


def build(args):
    ensure_repo_root()
    ensure_dictionary_data()
    run(xcodebuild_args(Path("target/xcode-derived"), args.xcodebuild_args), cwd=ROOT)


def codesign_info(app):
    return subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(app)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    ).stdout


def install_system(args):
    ensure_repo_root()
    ensure_dictionary_data()
    destination = Path("/Library/Input Methods/Xnheime.app")
    legacy_destination = Path("/Library/Input Methods/\n  Xnheime.app")
    stale_app = ROOT / "target/xcode-derived/Build/Products/Release/Xnheime.app"
    stale_dsym = ROOT / "target/xcode-derived/Build/Products/Release/Xnheime.app.dSYM"

    with tempfile.TemporaryDirectory(prefix="xnheime-xcode-derived.") as build_dir:
        build_dir_path = Path(build_dir)
        app = build_dir_path / "Build/Products/Release" / APP_NAME
        run(xcodebuild_args(build_dir_path, args.xcodebuild_args), cwd=ROOT)

        if not app.is_dir():
            print(f"error: missing built app: {app}", file=sys.stderr)
            sys.exit(1)

        signature_info = codesign_info(app)
        if "Signature=adhoc" in signature_info:
            print("error: refusing to install ad-hoc signed input method", file=sys.stderr)
            print(
                "set XNHEIME_DEVELOPMENT_TEAM or configure an Apple Development certificate",
                file=sys.stderr,
            )
            sys.exit(1)

        run(["sudo", "rm", "-rf", str(destination), str(legacy_destination)])
        run(["sudo", "ditto", str(app), str(destination)])
        run(["sudo", "chown", "-R", "root:wheel", str(destination)])
        run(["sudo", "chmod", "-R", "go+rX", str(destination)])

    shutil.rmtree(stale_app, ignore_errors=True)
    shutil.rmtree(stale_dsym, ignore_errors=True)
    subprocess.run(["killall", "TextInputMenuAgent"], check=False, stderr=subprocess.DEVNULL)
    print(f"installed {destination}")


def main():
    parser = argparse.ArgumentParser(description="macOS build helpers for Xnheime")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("xcodebuild_args", nargs=argparse.REMAINDER)
    build_parser.set_defaults(func=build)

    install_parser = subparsers.add_parser("install-system")
    install_parser.add_argument("xcodebuild_args", nargs=argparse.REMAINDER)
    install_parser.set_defaults(func=install_system)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
