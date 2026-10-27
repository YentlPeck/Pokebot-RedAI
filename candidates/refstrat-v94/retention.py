"""Post-game evidence policy. No emulator imports or gameplay callbacks."""
import hashlib
import json
import math
import os
import re
import time
from pathlib import Path

MARKER = 'RETENTION.json'
PROTECTED = re.compile(r'^(?:ver|off|footage|replay|record|pb|named|input|testinput)', re.I)
NORMAL = {'reset', 'pace_reset', 'early_reset', 'dev_stop', 'death', 'timeout', 'incomplete'}

def atomic(path, value):
    path = Path(path)
    tmp = path.with_name(path.name + '.tmp')
    with tmp.open('w', encoding='utf-8') as f:
        json.dump(value, f, separators=(',', ':')); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

def read(folder):
    return json.loads((Path(folder) / MARKER).read_text(encoding='utf-8'))

def safe_tree(folder):
    """Metadata only. Refuse links/junctions, even when nested."""
    total = 0
    for entry in os.scandir(folder):
        if entry.is_symlink() or (hasattr(os.path, 'isjunction') and os.path.isjunction(entry.path)):
            raise ValueError('linked artifact: ' + entry.path)
        if entry.is_dir(follow_symlinks=False): total += safe_tree(entry.path)
        elif entry.is_file(follow_symlinks=False): total += entry.stat(follow_symlinks=False).st_size
        else: raise ValueError('unsupported artifact: ' + entry.path)
    return total

def create(folder, seed, tag, owner=None, named=False):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=False)
    atomic(folder / MARKER, dict(schema=1, state='TEMP', seed=seed, tag=tag,
           created=time.time(), completed=False, owner=str(Path(owner).resolve()) if owner else None,
           reason='new run'))
    (folder / 'LOCK').write_text(str(os.getpid()), encoding='ascii')
    # Discover managed runs without opening 200,000+ old unmarked folders.
    index=folder.parent/'.retention-index'; index.mkdir(exist_ok=True)
    (index/folder.name).touch(exist_ok=False)
    if named or PROTECTED.match(tag): promote(folder,'protected tag/named input')

def promote(folder, reason='named input'):
    """Only new managed folders. Never invent a marker for old evidence."""
    folder = Path(folder)
    lock=folder/'SCREEN_LOCK'
    handle=lock.open('x')
    try:
        with handle:
            m = read(folder)
            if m.get('pruned'): raise ValueError('raw files already pruned; register named inputs BEFORE running them')
            m.update(state='KEEP', reason=reason); atomic(folder / MARKER, m)
    finally: lock.unlink()

def adapter_folder(folder, seed, record=False):
    """Also cover direct adapter/footage callers which do not use devrun."""
    folder=Path(folder)
    if not (folder/MARKER).exists():
        create(folder,seed,folder.name.rsplit('-',1)[0],named=record)
        return True
    # devrun created this staging folder before constructing the emulator.
    if (folder/'LOCK').read_text(encoding='ascii') != str(os.getpid()):
        raise FileExistsError('folder is not this process\'s new staging folder')
    if read(folder).get('completed'): raise FileExistsError('completed evidence must not be overwritten')
    return False

def adapter_finish(folder, result):
    """Default-off direct callers keep all raw files and cannot be cleaned
    without a linked external summary. This does not alter their result object.
    """
    summary=dict(seed=result['seed'],outcome=result['outcome'],
                 completion_elapsed=result.get('completion_elapsed_seconds'),
                 split_elapsed=[s['elapsed_seconds'] for s in result['splits']])
    return finish(folder,summary)

def load_pace(path):
    pace = json.loads(Path(path).read_text())
    if not isinstance(pace, list) or len(pace) != 21 or not all(
        type(x) in (int, float) and math.isfinite(x) and x > 0 for x in pace
    ) or any(a >= b for a, b in zip(pace, pace[1:])):
        raise ValueError('keep pace must contain 21 increasing PB split seconds')
    return pace

def reason_to_keep(summary, marker, late, pace):
    if marker['state'] == 'KEEP': return marker['reason']
    if summary.get('outcome') == 'success' or summary.get('completion_elapsed') is not None: return 'success/PB candidate'
    if summary.get('outcome') not in NORMAL: return 'technical error or unknown outcome'
    if summary.get('outcome') in {'timeout', 'incomplete'}: return 'possible technical failure'
    splits = summary.get('split_elapsed', [])
    if len(splits) >= late: return 'late split'
    if splits and pace is None: return 'PB pace unknown; preserve split evidence'
    if splits and splits[-1] <= pace[len(splits)-1]: return 'ahead of PB at last split'
    return None

def append_summary(path, summary, folder):
    """An append-only per-process ledger avoids interleaved worker writes."""
    path = Path(path).resolve()
    if Path(folder).resolve() in path.parents: raise ValueError('summary must live outside game folder')
    path.parent.mkdir(parents=True, exist_ok=True)
    row = dict(summary, artifact_folder=str(Path(folder).resolve()))
    raw = (json.dumps(row, separators=(',', ':')) + '\n').encode()
    lock=path.with_name(path.name+'.append-lock')
    with lock.open('x'):
        with path.open('ab') as f:
            offset = f.tell(); f.write(raw); f.flush(); os.fsync(f.fileno())
    lock.unlink()
    return dict(path=str(path), offset=offset, length=len(raw), sha256=hashlib.sha256(raw).hexdigest())

def summary_exists(folder, marker):
    try:
        ref = marker['summary']
        if not 0 < ref['length'] <= 1048576: return False
        with Path(ref['path']).open('rb') as f:
            f.seek(ref['offset']); raw = f.read(ref['length'])
        row = json.loads(raw)
        return (hashlib.sha256(raw).hexdigest() == ref['sha256'] and
                row['seed'] == marker['seed'] and
                Path(row['artifact_folder']).resolve() == Path(folder).resolve())
    except (OSError, ValueError, KeyError, TypeError): return False

def finish(folder, summary, *, enabled=False, ledger=None, late=9, pace=None):
    folder = Path(folder)
    # Serialize read/decide/write with promotion. Failed pruning stays locked.
    with (folder / 'SCREEN_LOCK').open('x'):
        m = read(folder)
        if enabled and (not ledger or not pace): raise ValueError('summary ledger and PB pace required')
        if ledger:
            m['summary'] = append_summary(ledger, summary, folder)
        why = reason_to_keep(summary, m, late, pace)
        m.update(completed=True, finished=time.time(), state='KEEP' if why else 'TEMP',
                 reason=why or ('early dead; move to delete folder after two idle hours' if enabled else 'retention off'),
                 raw_bytes=safe_tree(folder), pruned=False, last_write=time.time(),
                 move_ready=bool(enabled and not why))
        atomic(folder / MARKER, m)
        if enabled and not summary_exists(folder,m): raise RuntimeError('summary is not durable; keeping raw data')
        # Standing rule, 25 Oct: never delete raw data. TEMP stages intact until
        # clean_scratch --move can rename it after two idle hours. the owner empties
        # Downloads/pokebot-delete. No raw unlink/rmtree/copy-delete path exists.
        m['bytes'] = safe_tree(folder)
        atomic(folder / MARKER, m)
    (folder / 'SCREEN_LOCK').unlink()
    (folder / 'LOCK').unlink()
    return m

def failed(folder, error):
    folder = Path(folder)
    if (folder / MARKER).exists():
        m = read(folder); m.update(state='KEEP', reason='exception: ' + str(error)[:180])
        atomic(folder / MARKER, m)
    # Keep LOCK on a failed/partial attempt. A human reviews the crash.
