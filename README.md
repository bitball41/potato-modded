# Brotato + GMO Web

Native character fusion for the existing Godot WebAssembly export, adapted from
[Flabort's GMO](https://github.com/Flabort/Genetically-Engineered-Overkill).
Works with the vanilla and active Abyssal Terrors character resources in this build.

Download **[Brotato-GMO.html](Brotato-GMO.html)** and open it in your browser.
It is a standalone launcher: the game files load through jsDelivr, so an internet
connection is required. `Brotato.html` is the same launcher for existing links.

On character selection, enable **GMO**, select a balance preset, then select two
different unlocked characters. Hovering the second character previews the fusion;
incompatible characters show an explanation. **Reset fusion** clears the choices.
Keyboard/controller navigation, random selection, and local co-op use the game's
existing selection system. Each co-op player can choose their own fusion. Back or
Cancel clears the current fusion step before leaving character selection.

| Balance | XP gain | Item prices | Enemy count | Enemy speed |
| --- | ---: | ---: | ---: | ---: |
| Default | -10% | +10% | +15% | +3% |
| Original | -25% | +40% | +50% | +10% |
| Easy | 0% | 0% | 0% | 0% |
| Custom | Configurable | Configurable | Configurable | Configurable |

Both characters keep their native effects, starting grants, appearances, wanted
shop tags, and item restrictions. Starting choices are merged and filtered by the
combined restrictions. The original GMO incompatibility rules apply in both
directions; resource-based checks also handle newer and DLC characters, conflicting
limits, forbidden weapon types, starting weapons, and weapon slots.

Creature, Builder, Dwarf, Fisherman, Jack, Gangster, Ogre, King, Curious, and
Renegade identity-dependent behavior recognizes either half of a fusion.

Existing save files, profile names, engine persistence, and `/userfs` stay intact.
Fusion IDs encode both characters and exact balance values so saved runs and
restarts reconstruct the same build. Fusion records use separate native score
entries; they do not replace either character's individual win records or count as
extra vanilla characters toward Nightmare unlocks. To retain access to existing
saves, use the same browser profile and origin; browsers isolate different origins.

The original PCK/WASM chunks and engine files are unchanged. The original character
selection script also stays intact: a separate child controller attaches GMO after
the native screen initializes. Hover previews do not apply/remove fusion effects
or replace the grid's character resources. The custom dialog uses Godot 3 APIs.

The launcher merges a small `GMO.pck` resource patch into the pack index before
startup. The actual Web engine parses the changed GDScript source, avoiding an
assumed external bytecode revision. The launcher does no per-frame gameplay work. Downloads are
bounded to three concurrent files and cached separately from game saves. Asset
sizes and, where Web Crypto is available, SHA-256 hashes are checked before use.

## Source and packaging

- `gmo/src/`: edited native scripts at their original resource paths, plus fusion
  services and controls.
- `gmo/upstream-incompatibilities.json`: normalized upstream pair rules.
- `gmo/build.json`: base revision, upstream revision, resource list and asset hashes.
- `GMO.pck`: native script/scene resource patch, ready for the launcher.
- `tools/launcher.html.in`: launcher source template.
- [Credits and upstream details](gmo/NOTICE.md).

Package the patch with Python (no editor or external script compiler required):

```bash
python tools/build_gmo.py
```

Commit the source and `GMO.pck`, then pin the launcher to that commit:

```bash
python tools/make_launcher.py --mod-ref COMMIT_CONTAINING_GMO_PCK
```

The generator updates both HTML launchers. Commit them after generation.
The base assets remain pinned to the pre-mod export; changing the engine or base
game requires adapting the native scripts and updating the base ref together.

No automated or manual tests were run for this change, as requested. Packaging
writes the resource archive without starting the game or opening an editor.
