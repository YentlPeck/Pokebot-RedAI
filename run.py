"""Run one final-v94 game, optionally checking the recorded PB inputs."""
import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--rom', required=True, type=Path)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--seed', type=int)
    mode.add_argument('--replay-pb', action='store_true')
    ap.add_argument('--output-dir', type=Path, default=Path.home() / 'pokebot-runs' / 'refstrat-v94')
    args = ap.parse_args()
    rom = args.rom.expanduser().resolve()
    output = args.output_dir.expanduser().resolve()
    if not rom.is_file():
        ap.error('ROM must be an existing file')
    if rom.is_relative_to(ROOT) or output.is_relative_to(ROOT):
        ap.error('Keep ROM and run output outside this repository')
    if hashlib.sha1(rom.read_bytes()).hexdigest() != 'ea9bcae617fdf159b045185467ae58b2e4a48b9a':
        ap.error('Expected the unmodified Pokemon Red USA/Europe ROM described in README.md')
    if Path(str(rom) + '.ram').exists():
        ap.error('A cartridge RAM sidecar exists next to the ROM; refusing a fresh boot')
    record = json.loads((ROOT / 'docs/pb.json').read_text(encoding='utf-8'))
    flags = record['sets']
    if not flags:
        ap.error('PB flags must not be empty')
    for key in ('REFSTRAT_PACE', 'HUNT_CONFIG', 'REFSTRAT_TURN_HOOK', 'REFSTRAT_SRAM_DUMP'):
        os.environ.pop(key, None)
    os.environ['POKEBOT_ROM_PATH'] = str(rom)
    # Avoid generating untracked bytecode in a publication copy.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(ROOT / 'candidates/refstrat-v94'))
    import devrun
    seed = record['seed'] if args.replay_pb else args.seed
    tag = ('replay-pb' if args.replay_pb else 'game') + '-' + str(time.time_ns())
    argv = [str(seed), '--tag', tag, '--quiet', '--keep-input', '--artifact-root', str(output)]
    argv += [part for setting in flags for part in ('--set', setting)]
    summary = devrun.main(argv)
    folder = output / f'{tag}-{seed}'
    digest = hashlib.sha256((folder / 'actions.jsonl').read_bytes()).hexdigest()
    verification = dict(seed=seed, outcome=summary['outcome'], actions_sha256=digest,
                        split_elapsed=summary['split_elapsed'], completion_elapsed=summary['completion_elapsed'],
                        completion_igt=summary['completion_igt'], pb_replay=args.replay_pb)
    if args.replay_pb:
        verification['passed'] = (summary['outcome'] == 'success' and summary['splits'] == 21
                                  and digest == record['actions']
                                  and summary['completion_elapsed'] == record['real']
                                  and summary['completion_igt'] == record['igt'])
    (folder / 'verification.json').write_text(json.dumps(verification, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'output_folder': str(folder), **verification}), flush=True)
    if args.replay_pb and not verification['passed']:
        raise SystemExit(1)
    if summary['outcome'] in ('error', 'technical_error'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
