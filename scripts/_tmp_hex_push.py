# -*- coding: utf-8 -*-
"""Print hex chunks of a luau file for Studio execute_luau."""
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if not text.endswith("\n"):
    text += "\n"
hx = text.encode("utf-8").hex()
chunk = 4000
parts = [hx[i : i + chunk] for i in range(0, len(hx), chunk)]
out_dir = Path(r"d:\Git\Roblox\S3\scripts\_tmp_hex")
out_dir.mkdir(exist_ok=True)
for i, part in enumerate(parts):
    (out_dir / f"{sys.argv[2]}_{i:02d}.txt").write_text(part, encoding="ascii")
print(sys.argv[2], len(parts), len(hx))
