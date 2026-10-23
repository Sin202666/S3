# -*- coding: utf-8 -*-
import json
import sys
from pathlib import Path

root = Path(r"d:\Git\Roblox\S3")
rel = sys.argv[1]
studio_path = sys.argv[2]
out_path = Path(sys.argv[3])
text = (root / rel).read_text(encoding="utf-8")
if not text.endswith("\n"):
    text += "\n"
payload = (
    f"local inst = {studio_path}\n"
    "if not inst then error('missing') end\n"
    f"local HttpService = game:GetService('HttpService')\n"
    f"inst.Source = HttpService:JSONDecode({json.dumps(json.dumps(text))})\n"
    "return { name = inst.Name, n = #inst.Source, cn = string.find(inst.Source, 'HumanRootPart', 1, true) ~= nil }\n"
)
out_path.write_text(payload, encoding="utf-8")
print(out_path, out_path.stat().st_size)
