# Private engine copy for refstrat-v5

`candidates/refstrat-v5/engine/` is a copy of `reference/PokeBotBad` (PokeBot v2.4.8, MIT; LICENSE retained), made
2026-10-11 13:05 and byte-identical at creation (all *.lua SHA256 matched). The candidate's adapter sets
`pokebot_pyboy.SOURCE` / `pokebot_pyboy_fast.SOURCE` to this directory, so the shared engine is never modified.
Check the difference with: `diff -r reference/PokeBotBad candidates/refstrat-v5/engine`.

## #1 PP reads (independent review item 1; offline check experiments/refstrat-v5-2026-10-11/tools/pp_check.py)
- `action/battle.lua` `movePP` (= `Battle.pp`, also used by `Battle.automate` to drop a forced move with 0 PP): usable
  PP = byte % 64 (the top two bits count PP Ups); in battle the battle copy (0xD02D..) is used, outside battle the
  lead's party data (0xD188..) because the battle copy is stale after TMs/level-up learning.
- `ai/combat.lua` `getMoves`: `moveTable.pp = byte % 64` (move choice ignored nothing before: an exhausted Horn Drill
  with one PP Up read 64 and could be chosen).
- `storage/pokemon.lua` `Pokemon.pp(index, move)`: slot looked up in that party member's own move list (was the battle
  copy, nil -> crash for a move not in it), PP-Up bits masked.
- Inherited engine on the same 9 cases: 0/9 (64 / 70 / 67 / 12 / crash); v5: 9/9.
The v4 overlay copies of `Battle.pp` / `Pokemon.pp` were removed from `lua/strategies.lua` (single implementation).

## #2 (v6) Reflect / Light Screen in the damage model (ai/combat.lua)
`calcDamage` ignored the defender's Reflect / Light Screen (pokered engine/battle/core.asm doubles the defending stat).
v5's Champion loss on seed 1740000019 (diagnostic mt1, experiments/refstrat-v6-2026-10-11/FINDINGS.md): after Alakazam's
Reflect the model still predicted Earthquake as a guaranteed KO, the PP-conserving tie-break chose it over Horn Drill,
and the real Earthquake did 79 of 143. activePokemon now reads wPlayerBattleStatus3 (0xD064) / wEnemyBattleStatus3
(0xD069) bits 2 (Reflect) and 1 (Light Screen) — battle state the engine already reads, shown on screen by the move
text — and doubles the defending stat. Offline check: tools/bm_check2.py.

## refstrat-v7: read-only export Combat.calcRange
`Combat.calcRange(move, attacker, defender)` returns the same (min, max) damage `calcDamage` computes for the move
choice (incl. fix #2's Reflect/Light Screen). Used only by the candidate's SCREEN evidence log; no decision changes.

- refstrat-v13: main.lua no longer reads the play-time bytes for the stream-clock display (Bridge.time); the candidate's
  lua/strategies.lua redirects Utils.igt / frames / elapsedTime / timeSince to the approved LCD-on tracker.

- refstrat-v18 (cycle 1): action/battle.lua recover() - before the League the smallest item that survives the threatened
  hit is used and a League reserve (2 Super Potions, the Full Restore) is kept unless no smaller item survives (logged
  "League reserve breached"); one "refstrat RECOVER-OPP" line per threatened battle turn (opportunity, decision, item).
- refstrat-v18 (cycle 2, edits J/L/L2/L3 - supersedes the cycle-1 item rule above): action/battle.lua recover() uses the
  INHERITED item choice again (Super Potion first when > 22 HP missing; the cycle-1 smallest-item rule healed +20
  Potions at 27-56/120 HP vs Silph Giovanni and the next critical hit killed, c2c 3/6). Logging only: one "refstrat
  RECOVER-OPP" line per threatened battle turn while the game waits for our action (battle menu 94/106/233, no battle
  text; REFSTRAT_ACTION_PENDING), also when in-battle healing is disabled (Control.canRecover false); a decision that
  changes within the turn is logged again; turn key = map:opponent:opponent HP:our HP:ppSUM:itemsTOTAL
  (REFSTRAT_TURN_KEY). recover() and the paralysis cure set REFSTRAT_ITEM_SOURCE around their Inventory.use (ITEMUSE
  source=recover|paralysis). Paralysis cure: before the League only a Parlyz Heal (the Full Restore is kept for after
  Lance; logged "refstrat PARALYSIS-OPP"); in the League the inherited choice.
