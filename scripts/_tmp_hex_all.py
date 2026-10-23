# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(r"d:\Git\Roblox\S3")
jobs = [
    ("src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/CombatFx.luau", "combatfx"),
    ("src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/BoardView.luau", "boardview"),
    ("src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/Input.luau", "input"),
    ("src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/init.luau", "tbsclient"),
    ("src/ServerStorage/ServerSideCode/System/SystemTbs/Combat.luau", "combat"),
    ("src/ServerStorage/ServerSideCode/System/SystemTbs/ActionHandler.luau", "actionhandler"),
    ("src/ServerStorage/ServerSideCode/System/SystemTbs/AI.luau", "ai"),
    ("src/ServerStorage/ServerSideCode/System/SystemTbs/MatchStore.luau", "matchstore"),
    ("src/ReplicatedFirst/AllSideCode/Interface/SystemTbs-Type.luau", "tbstype"),
]
out_dir = root / "scripts" / "_tmp_hex"
out_dir.mkdir(exist_ok=True)
chunk = 6000
for rel, key in jobs:
    text = (root / rel).read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    hx = text.encode("utf-8").hex()
    parts = [hx[i : i + chunk] for i in range(0, len(hx), chunk)]
    for i, part in enumerate(parts):
        (out_dir / f"{key}_{i:02d}.txt").write_text(part, encoding="ascii")
    print(key, len(parts), len(hx))
