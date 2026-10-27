"""External ROM selection shared by initial boot and cartridge power cycles."""
import os
from pathlib import Path


def rom_path():
    value = os.environ.get('POKEBOT_ROM_PATH')
    if not value:
        raise ValueError('Supply your legal ROM with run.py --rom')
    path = Path(value).expanduser().resolve()
    if not path.is_file():
        raise ValueError('The supplied ROM is not a file')
    return path
