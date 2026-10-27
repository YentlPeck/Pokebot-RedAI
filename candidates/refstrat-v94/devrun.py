"""Development runner for the refstrat candidate: one fresh-boot run (candidate adapter with power cycle),
full state snapshot at every strategy event, optional stop after a given strategy or split.

Usage: devrun.py SEED [--stop-after STRATEGY] [--stop-split N] [--set NAME=LUAVALUE ...] [--tag T] [--quiet]
Prints the strategy timeline (elapsed = normal-speed seconds since the bot's start), party/moves/items at
changes, and a JSON summary line. Artifacts: --artifact-root/<tag>-<seed> (default: ~/pokebot-runs/refstrat-v94/)
"""
import argparse, json, re, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT)); sys.path.insert(0, str(HERE))
# v5: trash-direct-v100 (inherited hidden read of the Surge switch cans) is NOT loaded any more; Surge's cans use the
# reference-style save/reset manip (S.refSurgeCans) with the engine's visible can search as fallback.
STACK = ['candidates/refstrat-v94/lua/route.lua', 'candidates/refstrat-v94/lua/chain.lua', 'candidates/refstrat-v94/lua/strategies.lua', 'candidates/refstrat-v94/lua/loader.lua',
         'candidates/refstrat-v94/upgrades/brock-efficient-v66.lua', 'candidates/refstrat-v94/upgrades/menu-taps-v101.lua',
         'candidates/refstrat-v94/upgrades/menu-fix-v49.lua']
# base overlay of the inherited 'blue-v14' variant (v33: blue-v14.lua itself removed - fully overridden)
BASE = ['candidates/refstrat-v94/upgrades/agatha-v1.lua']
FPS = 4194304 / 70224
import os
MOVES = {}  # Diagnostic names omitted; report numeric game IDs.
ITEMS = {}


def state(m):
    party = []
    for i in range(m[0xD163]):
        p = 0xD16B + 44 * i
        party.append(dict(species=m[p], level=m[p + 33], hp=m[p + 1] * 256 + m[p + 2], max_hp=m[p + 34] * 256 + m[p + 35],
                          moves=[MOVES.get(x, x) for x in m[p + 8:p + 12]], pp=[x & 63 for x in m[p + 29:p + 33]],
                          dvs=[m[p + 27] >> 4, m[p + 27] & 15, m[p + 28] >> 4, m[p + 28] & 15],
                          stats=[m[p + 36 + 2 * k] * 256 + m[p + 37 + 2 * k] for k in range(4)],
                          exp=m[p + 14] * 65536 + m[p + 15] * 256 + m[p + 16], spd_statexp=m[p + 23] * 256 + m[p + 24]))
    inv = [(ITEMS.get(m[0xD31E + 2 * i], m[0xD31E + 2 * i]), m[0xD31F + 2 * i]) for i in range(m[0xD31D])]
    money = int(''.join(f'{b:02x}' for b in m[0xD347:0xD34A]))
    return dict(map=m[0xD35E], x=m[0xD362], y=m[0xD361], battle=m[0xD057], party=party, inventory=inv, money=money,
                igt=m[0xDA41] * 3600 + m[0xDA43] * 60 + m[0xDA44] + m[0xDA45] / 60)


def main(argv=None, *, _worker=False):
    ap = argparse.ArgumentParser()
    ap.add_argument('seed', type=int)
    ap.add_argument('--stop-after')
    ap.add_argument('--stop-split', type=int)
    ap.add_argument('--set', action='append', default=[])
    ap.add_argument('--tag', default='dev')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--max-frames', type=int, default=480000)
    ap.add_argument('--extra-patch', action='append', default=[], help='diagnostic overlay (not part of the candidate)')
    ap.add_argument('--stop-map', type=int, help='stop (dev_stop) the moment this map is entered (v6 runner: 120 = Champion room)')
    ap.add_argument('--trace', help='FROM:TO:EVERY frames for experiments/refstrat-v3-2026-10-11/tools/walker_trace.lua')
    ap.add_argument('--temp-runs', action='store_true', help='post-game raw retention; default off')
    ap.add_argument('--summary-jsonl', help='durable per-process raw summary ledger')
    ap.add_argument('--keep-pace', help='21 actual PB split seconds, separate from reset pace')
    ap.add_argument('--keep-split', type=int, default=9)
    ap.add_argument('--keep-input', action='store_true', help='named test/replay input; preserve all raw data')
    ap.add_argument('--artifact-root', type=Path, help='new game folders here (tests only)')
    a = ap.parse_args(argv)
    from retention import create, finish, failed, load_pace
    keep_pace = load_pace(a.keep_pace) if a.keep_pace else None
    if a.temp_runs and (not a.summary_jsonl or keep_pace is None):
        ap.error('--temp-runs requires --summary-jsonl and --keep-pace')
    if not 1 <= a.keep_split <= 21: ap.error('--keep-split must be 1..21')
    pace_limits = json.loads(Path(os.environ['REFSTRAT_PACE']).read_text()) if os.environ.get('REFSTRAT_PACE') else None
    import warnings; warnings.filterwarnings('ignore')
    from refstrat_adapter import Attempt
    from pokebot_pyboy import AttemptDone
    folder = Path.home() / 'pokebot-runs' / 'refstrat-v94' / f'{a.tag}-{a.seed}'
    if a.artifact_root:
        folder = a.artifact_root.resolve() / f'{a.tag}-{a.seed}'
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', a.tag): ap.error('safe tag required')
    if a.summary_jsonl and folder.resolve() in Path(a.summary_jsonl).resolve().parents:
        ap.error('summary ledger must live outside the game folder')
    create(folder, a.seed, a.tag, owner=Path(a.summary_jsonl).resolve().parent if a.summary_jsonl else None, named=a.keep_input)
    events = []

    class Dev(Attempt):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.lua.globals().port_next_split_pace = self.next_split_pace

        def next_split_pace(self):
            # Read-only. Same next index and exact JSON float as the existing split check.
            # frames/started survive the adapter's normal cartridge-save power cycles.
            index = len(self.splits)
            elapsed = None if self.started is None else (self.frames - self.started) / FPS
            limit = pace_limits[index] if pace_limits and index < len(pace_limits) and self.outcome != 'success' else None
            return elapsed, limit, index + 1

        def on_strategy(self, name):
            if getattr(self, 'strategy', None) != name:
                prev = getattr(self, 'strategy', None)
                events.append(dict(strategy=name, frame=self.frames,
                                   elapsed=None if self.started is None else (self.frames - self.started) / FPS, **state(self.gb.memory)))
                if a.stop_after and prev == a.stop_after:
                    self.outcome, self.reason = 'dev_stop', f'after {prev}'
                    super().on_strategy(name)
                    raise AttemptDone(self.reason)
            super().on_strategy(name)

        def advance(self):
            try:
                r = super().advance()
            except AttemptDone:
                # review1 #2: an attempt that ends on the frame it enters the stop map still counts as having entered
                if a.stop_map is not None and self.gb.memory[0xD35E] == a.stop_map:
                    self.stop_map = a.stop_map
                raise
            if a.stop_map is not None and self.gb.memory[0xD35E] == a.stop_map and self.outcome != 'success':
                self.outcome, self.reason = 'dev_stop', f'entered map {a.stop_map}'
                self.stop_map = a.stop_map
                raise AttemptDone(self.reason)
            return r

        def split(self, finished=None):
            super().split(finished)
            if a.stop_split and len(self.splits) >= a.stop_split and self.outcome != 'success':
                self.outcome, self.reason = 'dev_stop', f'split {len(self.splits)}'
                raise AttemptDone(self.reason)
            pace = pace_limits[len(self.splits) - 1] if pace_limits and len(self.splits) <= len(pace_limits) else None   # v39 reset when off pace
            el = self.splits[-1].get('elapsed_seconds') if self.splits else None
            if pace is not None and el is not None and el > pace and self.outcome != 'success':
                self.outcome, self.reason = 'pace_reset', f'split {len(self.splits)} at {el:.1f} s > pace {pace:.1f} s'
                raise AttemptDone(self.reason)

    run = Dev.__new__(Dev)
    try:
        Dev.__init__(run, a.seed, a.max_frames, folder, goal='full', variant='blue-v14')
        if _worker:
            from worker_support import audit_fresh
            audit_fresh(run)
        run.patch_files = [ROOT / p for p in BASE] + [ROOT / p for p in STACK] + [ROOT / p for p in a.extra_patch]
        if a.trace:
            f, t, e = (int(x) for x in a.trace.split(':'))
            run.patch_files.append(ROOT / 'experiments/refstrat-v3-2026-10-11/tools/walker_trace.lua')
            run.lua.execute(f'REFTRACE_FROM, REFTRACE_TO, REFTRACE_EVERY = {f}, {t}, {e}')
        for kv in a.set:
            k, v = kv.split('=', 1)
            run.lua.execute(f'{k} = {v}')
        r = run.run()
        (folder / 'events.json').write_text(json.dumps(events))
        if not a.quiet:
            last = None
            for e in events:
                lead = e['party'][0] if e['party'] else None
                key = (tuple(lead['moves']) if lead else None, e['map'])
                el = f"{e['elapsed']:7.1f}" if e['elapsed'] is not None else '      -'
                print(f"{el}s igt {e['igt']:7.1f} {e['strategy']:22s} map {e['map']:3d} ({e['x']},{e['y']})"
                      + (f" L{lead['level']} {lead['hp']}/{lead['max_hp']} {lead['moves']}" if lead and key != last else ''))
                last = key
            end = state(run.gb.memory) if False else (events[-1] if events else {})
            print('party:', [(p['species'], p['level'], p['moves'], p['dvs']) for p in (end.get('party') or [])])
            print('items:', end.get('inventory'), 'money', end.get('money'))
        summary = dict(seed=a.seed, outcome=r['outcome'], reason=r['reason'], igt=r['game_seconds'],
                              elapsed=r['elapsed_seconds'], splits=len(r['splits']),
                              completion_elapsed=r.get('completion_elapsed_seconds'), completion_igt=r.get('completion_game_seconds'),
                              split_elapsed=[round(x['elapsed_seconds'], 2) for x in r['splits']], power_cycles=len(run.power_cycles),
                              last_strategy=r['strategy'], stop_map=getattr(run, 'stop_map', None),
                              final_map=run.gb.memory[0xD35E])
        finish(folder, summary, enabled=a.temp_runs, ledger=a.summary_jsonl,
               late=a.keep_split, pace=keep_pace)
        print(json.dumps(summary))
        return summary
    except BaseException as ex:
        failed(folder, ex)
        raise
    finally:
        if _worker:
            from worker_support import release_attempt
            release_attempt(run)


if __name__ == '__main__':
    if sys.argv[1:] == ['--worker']:
        from worker_support import serve
        serve(main)
    else:
        main()
