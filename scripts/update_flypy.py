#!/usr/bin/env python3
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "data/flypy"
SOURCE_REPOSITORY = "https://github.com/cubercsl/rime-flypy.git"
SOURCE_REF = "v20251211"

DICTIONARY_FILES = [
    "flypy.dict.yaml",
    "flypy/flypy.user.top.dict.yaml",
    "flypy/flypy.fast.symbols.dict.yaml",
    "flypy/flypy.primary.dict.yaml",
    "flypy/flypy.secondary.dict.yaml",
    "flypy/flypy.three.dict.yaml",
    "flypy/flypy.web.dict.yaml",
    "flypy/flypy.emoji.dict.yaml",
    "flypy/flypy.symbols.dict.yaml",
    "flypy/flypy.wechat.dict.yaml",
    "flypy/flypy.primary.short.word.dict.yaml",
    "flypy/flypy.whimsicality.dict.yaml",
    "flypy/flypy.user.dict.yaml",
]


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def capture(args, **kwargs):
    return subprocess.run(
        args,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
        **kwargs,
    ).stdout.strip()


def main():
    with tempfile.TemporaryDirectory(prefix="xnheime-flypy.") as temp_dir:
        checkout = Path(temp_dir) / "rime-flypy"
        run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                SOURCE_REF,
                SOURCE_REPOSITORY,
                str(checkout),
            ]
        )
        source_commit = capture(["git", "-C", str(checkout), "rev-parse", "HEAD"])

        shutil.rmtree(DESTINATION, ignore_errors=True)
        for relative_path in DICTIONARY_FILES:
            source = checkout / relative_path
            destination = DESTINATION / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        (DESTINATION / "SOURCE").write_text(
            "\n".join(
                [
                    f"repository: {SOURCE_REPOSITORY}",
                    f"ref: {SOURCE_REF}",
                    f"commit: {source_commit}",
                    "files: flypy.dict.yaml and enabled import tables",
                    "",
                ]
            ),
            encoding="utf-8",
        )

    print(f"updated {DESTINATION} from {SOURCE_REPOSITORY} {SOURCE_REF}")


if __name__ == "__main__":
    main()
