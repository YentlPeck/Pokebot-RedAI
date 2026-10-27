# Export changes

Gameplay Lua, including engine fixes and the optional walker trace, is byte-identical to the private v94 source. docs/SOURCE_SHA256.json records copied source-file hashes before adaptation.

Only three copied Python files changed:

- devrun.py: replace the pret move/item diagnostic names with numeric IDs; change the default artifact directory to ~/pokebot-runs/refstrat-v94. No decision callback or flag changes.
- refstrat_adapter.py: select the external ROM through runtime_config.py on initial boot checks and power cycles; check its adjacent RAM sidecar.
- pokebot_pyboy.py: external ROM and in-memory initial cartridge RAM, relative engine/license references, portable optional video fonts and ffmpeg lookup, and removal of its obsolete CLI for omitted historical variants. Its frame/input/split lifecycle is retained.

control.py contains only the source PNG writer; the unrelated save-state setup CLI is omitted. run.py provides the public single-game/PB commands, exact ordered flags, external-output validation, environment clearing, and PB hash/time verification. runtime_config.py resolves the ROM path. Worker/retention support remains; obsolete budget.py and v19run.py are not dependencies and are omitted.

No source git history, upstream binaries, wiki run records, historical build markers, old experiment scripts, disassembly, ROM, saves, raw logs, model transcripts, or environment folders are included. The optional trace is the one small file retained under experiments/.

- `candidates/refstrat-v94/retention.py`: one comment line reworded for the public copy (no code change).
