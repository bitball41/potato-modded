#!/usr/bin/env python3
"""Emit the standalone GMO HTML launcher, pinned to a published patch commit."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mod-ref", required=True, help="Commit containing GMO.pck")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.mod_ref):
        parser.error("--mod-ref must be a full immutable commit SHA")
    manifest = json.loads((ROOT / "gmo/build.json").read_text())
    release = {key: manifest[key] for key in ("version", "base_repository", "base_ref", "base_files", "patch", "engine_script_integrity")}
    release["mod_ref"] = args.mod_ref
    template = (ROOT / "tools/launcher.html.in").read_text()
    launcher = template.replace("__GMO_RELEASE_CONFIG__", json.dumps(release, separators=(",", ":")))
    for name in ("Brotato-GMO.html", "Brotato.html", "Brotato-GMO-v4.html"):
        (ROOT / name).write_text(launcher)
        print("Created", name)
    (ROOT / "gmo/release.json").write_text(json.dumps(release, indent=2) + "\n")


if __name__ == "__main__":
    main()
