#!/usr/bin/env python3
"""Entry point: python -m compress <filepath>"""

import sys
from pathlib import Path
from .compress import compress_file

if len(sys.argv) != 2:
    print("Usage: python -m compress <filepath>")
    sys.exit(1)

target = Path(sys.argv[1]).resolve()
success = compress_file(target)
sys.exit(0 if success else 1)
