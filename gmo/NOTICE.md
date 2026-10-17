# GMO Web port credits

Character fusion, the original compatibility table, balance presets, and the
hybrid portrait are adapted from Flabort's **Genetically Modified Overkill**:

https://github.com/Flabort/Genetically-Engineered-Overkill

Source revision: `3c85e5c2ce6f3e3004f8ef082fdb117661b6b9d6` (GMO 0.2.0).
Upstream credits KANA and Dami for code contributions, and EviePatamon for improved
art assets. The hybrid portrait and its Godot import are retained from that source.

The Web port adapts selection, resource hashing, saved runs, per-player data,
character-specific behavior and DLC compatibility to the existing Godot 3.7
export in this repository. Character abilities use this export's own character
and effect resources, retaining its current balance and DLC behavior.

The upstream entry point's Default preset overrides its placeholder resources:
XP -10%, prices +10%, enemies +15%, speed +3%. Original uses -25%, +40%, +50%,
+10%. Easy adds no penalties. Custom uses the same four modifiers.
