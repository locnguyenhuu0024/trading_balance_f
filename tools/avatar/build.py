"""Bundle the local avatar page using its pinned npm dependencies."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile

THREE = "0.187.0"
THREE_VRM = "3.5.5"
ESBUILD = "0.25.10"

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "tools/avatar/src/entry.js"
OUTPUT = ROOT / "assets/avatar/avatar.bundle.js"


def bundle(deps):
    modules = deps.resolve() / "node_modules"
    env = {**os.environ, "NODE_PATH": str(modules)}
    subprocess.run(
        [
            "node", str(modules / "esbuild/bin/esbuild"), str(ENTRY),
            "--bundle", "--format=iife", "--minify", "--target=es2019",
            "--legal-comments=eof", "--resolve-extensions=.js,.mjs,.json",
            f"--outfile={OUTPUT}",
        ],
        cwd=ROOT,
        env=env,
        check=True,
    )
    print(f"{OUTPUT.relative_to(ROOT)}: {OUTPUT.stat().st_size} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deps", type=Path, help="directory containing staged node_modules")
    args = parser.parse_args()
    if args.deps:
        bundle(args.deps)
        return

    with tempfile.TemporaryDirectory(prefix="avatar-build-") as directory:
        subprocess.run(
            [
                "npm", "install", "--prefix", directory, "--no-save",
                "--ignore-scripts", "--no-audit", "--no-fund",
                f"three@{THREE}", f"@pixiv/three-vrm@{THREE_VRM}", f"esbuild@{ESBUILD}",
            ],
            cwd=directory,
            check=True,
        )
        bundle(Path(directory))


if __name__ == "__main__":
    main()
