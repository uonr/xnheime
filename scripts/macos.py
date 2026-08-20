#!/usr/bin/env python3
import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "platform/macos/Xnheime.xcodeproj"
APP_NAME = "Xnheime.app"
FLYPY_SENTINEL = ROOT / "data/flypy/flypy.table.bin"
RUST_CORE_BUILD_SCRIPT = ROOT / "scripts/build_rust_core.sh"


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


def xcodebuild_command():
    override = os.environ.get("XNHEIME_XCODEBUILD")
    if override:
        candidate = Path(override).expanduser()
        if candidate.is_file():
            return candidate
        print(f"error: XNHEIME_XCODEBUILD does not exist: {candidate}", file=sys.stderr)
        sys.exit(1)

    candidates = [
        Path("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"),
        Path("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild"),
    ]
    candidates.extend(
        Path(path)
        for path in sorted(
            glob.glob("/Applications/Xcode*.app/Contents/Developer/usr/bin/xcodebuild")
        )
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate

    print("error: a full Xcode installation was not found in /Applications", file=sys.stderr)
    sys.exit(1)


def xcode_environment(xcodebuild):
    environment = os.environ.copy()
    environment.pop("SDKROOT", None)
    environment["DEVELOPER_DIR"] = str(xcodebuild.parents[2])
    return environment


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
    xcodebuild = xcodebuild_command()
    args = [
        str(xcodebuild),
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
        "LD=$(TOOLCHAIN_DIR)/usr/bin/clang",
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
    print("copy the original Rime Flypy tables into data/flypy", file=sys.stderr)
    sys.exit(1)


def build_rust_core(configuration, xcodebuild):
    environment = xcode_environment(xcodebuild)
    run(
        ["/bin/sh", str(RUST_CORE_BUILD_SCRIPT), configuration],
        cwd=ROOT,
        env=environment,
    )


def build(args):
    ensure_repo_root()
    ensure_dictionary_data()
    command = xcodebuild_args(Path("target/xcode-derived"), args.xcodebuild_args)
    xcodebuild = Path(command[0])
    build_rust_core("Release", xcodebuild)
    run(command, cwd=ROOT, env=xcode_environment(xcodebuild))


def verify_signature(app):
    result = subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.returncode == 0, result.stdout


def ensure_valid_signature(app, build_dir):
    valid, verification_output = verify_signature(app)
    if valid:
        return

    identity = apple_development_identity()
    if not identity:
        print(verification_output, file=sys.stderr)
        print("error: built input method does not have a valid signature", file=sys.stderr)
        print("configure an Apple Development certificate and try again", file=sys.stderr)
        sys.exit(1)

    entitlements = (
        build_dir
        / "Build/Intermediates.noindex/Xnheime.build/Release/Xnheime.build/Xnheime.app.xcent"
    )
    sign_args = ["codesign", "--force", "--sign", identity]
    if entitlements.is_file():
        sign_args += ["--entitlements", str(entitlements)]
    sign_args += ["--timestamp=none", "--generate-entitlement-der", str(app)]
    run(sign_args)

    valid, verification_output = verify_signature(app)
    if not valid:
        print(verification_output, file=sys.stderr)
        print("error: input method signature remains invalid after re-signing", file=sys.stderr)
        sys.exit(1)


def install_system(args):
    ensure_repo_root()
    ensure_dictionary_data()
    destination = Path("/Library/Input Methods/Xnheime.app")
    staging = Path("/Library/Input Methods/.Xnheime.app.installing")
    backup = Path("/Library/Input Methods/.Xnheime.app.backup")
    legacy_destination = Path("/Library/Input Methods/\n  Xnheime.app")

    with tempfile.TemporaryDirectory(prefix="xnheime-xcode-derived.") as build_dir:
        build_dir_path = Path(build_dir)
        app = build_dir_path / "Build/Products/Release" / APP_NAME
        command = xcodebuild_args(build_dir_path, args.xcodebuild_args)
        xcodebuild = Path(command[0])
        build_rust_core("Release", xcodebuild)
        run(command, cwd=ROOT, env=xcode_environment(xcodebuild))

        if not app.is_dir():
            print(f"error: missing built app: {app}", file=sys.stderr)
            sys.exit(1)

        ensure_valid_signature(app, build_dir_path)

        run(["sudo", "rm", "-rf", str(staging), str(backup)])
        run(["sudo", "ditto", str(app), str(staging)])
        run(["sudo", "chown", "-R", "root:wheel", str(staging)])
        run(["sudo", "chmod", "-R", "go+rX", str(staging)])

        valid, verification_output = verify_signature(staging)
        if not valid:
            print(verification_output, file=sys.stderr)
            run(["sudo", "rm", "-rf", str(staging)])
            print("error: staged input method failed signature verification", file=sys.stderr)
            sys.exit(1)

        had_previous_install = destination.exists()
        if had_previous_install:
            run(["sudo", "mv", str(destination), str(backup)])
        try:
            run(["sudo", "mv", str(staging), str(destination)])
        except subprocess.CalledProcessError:
            if had_previous_install and backup.exists():
                run(["sudo", "mv", str(backup), str(destination)])
            raise

        run(["sudo", "rm", "-rf", str(backup), str(legacy_destination)])

    subprocess.run(["killall", "Xnheime"], check=False, stderr=subprocess.DEVNULL)
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
