# -*- coding: utf-8 -*-
"""Print a Luau snippet that sets a ModuleScript Source from a local file."""
from __future__ import annotations

import sys
from pathlib import Path

root = Path(r"d:\Git\Roblox\S3")
rel = sys.argv[1]
studio_path = sys.argv[2]
out_path = Path(sys.argv[3])
text = (root / rel).read_text(encoding="utf-8")
if not text.endswith("\n"):
    text += "\n"
delim = "TBS_SRC"
while f"]{delim}]" in text:
    delim += "X"
payload = (
    f"local inst = {studio_path}\n"
    'if not inst then error("missing") end\n'
    f"inst.Source = [{delim}[{text}]{delim}]\n"
    'return { name = inst.Name, lines = select(2, string.gsub(inst.Source, "\\n", "\\n")) }\n'
)
out_path.write_text(payload, encoding="utf-8")
print(out_path, out_path.stat().st_size)
