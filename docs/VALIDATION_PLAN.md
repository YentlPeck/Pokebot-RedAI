# Export validation plan (2026-10-27)

Before running: scan public filenames and text for excluded data, personal paths, emails and common credential formats; compile Python and parse Lua without creating bytecode. Compare every copied gameplay Lua hash with the source.

Run exactly one PB-seed replay from this folder, with the source project's external ROM and final ordered flags. Clear REFSTRAT_PACE, HUNT_CONFIG, REFSTRAT_TURN_HOOK and REFSTRAT_SRAM_DUMP. Start only after the source count_slots.ps1 reports at most 11 occupied emulator slots. Empty cartridge RAM must be io.BytesIO(bytes(0x8000)) on initial boot; keep normal save RAM in memory for power cycles. Write run artifacts outside this repository.

Pass: success, 21 splits, bot completion 6386.672744750977 seconds, in-game 6255.416666666667 seconds, and actions SHA-256 8b3ffca98347dee95e93dce4d1e2a825239773c6844e07fb2808431ac26c2cdd. Stop and document any mismatch; no hunt or extra games. Re-scan the finished public folder. Never modify or delete source files, never push, and never configure a remote.
