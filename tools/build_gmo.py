#!/usr/bin/env python3
"""Compile the GMO scripts and package a Godot 3.7 overlay. Does not run the game."""

import argparse
import base64
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_REF = "df84cdf6b5084d91d5693fd5cf0159f62116a224"
UPSTREAM_REF = "3c85e5c2ce6f3e3004f8ef082fdb117661b6b9d6"
ICON_DIR = "mods-unpacked/flabort-GMO/content/characters/GMO_dummy/"


def aligned(value, alignment=16):
    return (value + alignment - 1) // alignment * alignment


def write_pack(files, output):
    entries = []
    for name, data in sorted(files.items()):
        path = ("res://" + name).encode("utf-8") + b"\0"
        path += b"\0" * (-len(path) % 4)
        entries.append((path, data))
    offset = aligned(88 + sum(4 + len(path) + 32 for path, _ in entries))
    index = bytearray(b"GDPC" + struct.pack("<4I", 1, 3, 7, 0) + bytes(64))
    index += struct.pack("<I", len(entries))
    payloads = []
    for path, data in entries:
        index += struct.pack("<I", len(path)) + path
        index += struct.pack("<QQ", offset, len(data)) + hashlib.md5(data).digest()
        payloads.append(data + bytes(-len(data) % 16))
        offset += aligned(len(data))
    index += bytes(-len(index) % 16)
    with output.open("wb") as pack:
        pack.write(index)
        for data in payloads:
            pack.write(data)


def describe(path):
    data = path.read_bytes()
    return {"name": path.name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gdre", required=True, type=Path, help="GDRE Tools v2.7.4 executable")
    args = parser.parse_args()
    gdre = args.gdre.resolve()
    files = {}
    with tempfile.TemporaryDirectory(prefix="potato-gmo-build-") as temporary:
        staging = Path(temporary)
        bytecode = staging / "bytecode"
        bytecode.mkdir()
        sources = []
        for source in sorted((ROOT / "gmo/src").rglob("*.gd")):
            target = staging / source.relative_to(ROOT / "gmo/src")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            sources.append(target)
        # This emits the same v13 token bytecode used by the existing export.
        # It compiles resources only; no scene, game, or test process is started.
        subprocess.run(
            [str(gdre), "--headless", "--bytecode=a7aad78", "--output=" + str(bytecode)]
            + ["--compile=" + str(source) for source in sources],
            check=True,
        )
        for source in sources:
            compiled = bytecode / source.with_suffix(".gdc").name
            relative = source.relative_to(staging).as_posix()
            files[relative[:-3] + ".gdc"] = compiled.read_bytes()
            if relative.startswith("gmo/"):
                files[relative + ".remap"] = (
                    '[remap]\n\npath="res://' + relative[:-3] + '.gdc"\n'
                ).encode("utf-8")
    for name in ("GMO_hybrid_reworked.png", "GMO_hybrid_reworked.png.import"):
        files[ICON_DIR + name] = (ROOT / "gmo/assets" / name).read_bytes()
    for asset in (ROOT / "gmo/assets").glob("*.stex"):
        files[".import/" + asset.name] = asset.read_bytes()
    output = ROOT / "GMO.pck"
    write_pack(files, output)
    base_chunks = sorted(ROOT.glob("Brotato.pck.part*")) + sorted(ROOT.glob("Brotato.wasm.part*"))
    manifest = {
        "format": "godot3-pck-overlay-v1",
        "version": "gmo-web-1",
        "engine": "3.7.0",
        "base_repository": "bitball41/potato-modded",
        "base_ref": BASE_REF,
        "upstream_repository": "Flabort/Genetically-Engineered-Overkill",
        "upstream_ref": UPSTREAM_REF,
        "patch": describe(output),
        "base_files": [describe(chunk) for chunk in base_chunks],
        "engine_script_integrity": "sha384-" + base64.b64encode(hashlib.sha384((ROOT / "Brotato.js").read_bytes()).digest()).decode(),
        "resources": sorted(files),
    }
    (ROOT / "gmo/build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Packaged", output.name, manifest["patch"]["size"], "bytes")


if __name__ == "__main__":
    main()
