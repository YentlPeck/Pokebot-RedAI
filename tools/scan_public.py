"""Read-only filename, size, ROM-signature and common sensitive-text scan."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLOCKED_SUFFIXES = {'.gb', '.gbc', '.gba', '.sav', '.ram', '.state', '.sram', '.bin', '.zip', '.7z', '.pyc', '.log', '.jsonl', '.pem', '.key'}
BLOCKED_DIRS = {'.venv', 'venv', '__pycache__', 'pokebot-scratch', 'runs', 'artifacts'}
PATTERNS = {
    'email': r'[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}',
    'personal_windows_path': r'(?i)[A-Z]:[\\/]+Users[\\/]+[^\s\"\']+',
    'personal_unix_path': r'/(?:home|Users)/[A-Za-z0-9_.-]+/',
    'private_key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'github_token': r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})',
    'openai_token': r'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}',
    'aws_access_key': r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'assigned_credential': r'(?i)(?:api[_-]?key|access[_-]?token|secret|password)\s*[:=]\s*[\"\'][A-Za-z0-9_+/=-]{16,}[\"\']',
}


def scan():
    findings, files = [], []
    for path in sorted(ROOT.rglob('*')):
        rel = path.relative_to(ROOT)
        if '.git' in rel.parts:
            continue
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            findings.append({'file': rel.as_posix(), 'kind': 'link'})
            continue
        if path.is_dir():
            if path.name in BLOCKED_DIRS:
                findings.append({'file': rel.as_posix(), 'kind': 'excluded_directory'})
            continue
        if not path.is_file():
            continue
        files.append(path)
        name = path.name.lower()
        if (set(path.suffixes) & BLOCKED_SUFFIXES or name == '.env' or name.startswith('.env.')
                or re.search(r'(transcript|agent[-_]session|id_rsa|id_ed25519)', name)):
            findings.append({'file': rel.as_posix(), 'kind': 'excluded_filename'})
        raw = path.read_bytes()
        if len(raw) > 5_000_000:
            findings.append({'file': rel.as_posix(), 'kind': 'over_5MB'})
        # Game Boy Nintendo-logo prefix at its cartridge-header offset.
        if raw[0x104:0x10C].hex() == 'ceed6666cc0d000b':
            findings.append({'file': rel.as_posix(), 'kind': 'ROM_signature'})
        try:
            content = raw.decode('utf-8')
        except UnicodeDecodeError:
            findings.append({'file': rel.as_posix(), 'kind': 'unexpected_binary'})
            continue
        for kind, pattern in PATTERNS.items():
            for match in re.finditer(pattern, content):
                # Report locations only, never print a possible credential.
                findings.append({'file': rel.as_posix(), 'kind': kind, 'line': content.count('\n', 0, match.start()) + 1})
    return dict(files=len(files), bytes=sum(p.stat().st_size for p in files),
                largest_file_bytes=max((p.stat().st_size for p in files), default=0),
                findings=findings, passed=not findings)


if __name__ == '__main__':
    result = scan()
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
