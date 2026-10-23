# -*- coding: utf-8 -*-
from pathlib import Path
import json

root = Path(r"d:\Git\Roblox\S3")
jobs = [
    (
        "src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/CombatFx.luau",
        "game.ReplicatedStorage.ClientSideCode.SystemModule.SystemTbs.CombatFx",
        "CombatFx",
    ),
    (
        "src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/BoardView.luau",
        "game.ReplicatedStorage.ClientSideCode.SystemModule.SystemTbs.BoardView",
        "BoardView",
    ),
    (
        "src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/Input.luau",
        "game.ReplicatedStorage.ClientSideCode.SystemModule.SystemTbs.Input",
        "Input",
    ),
    (
        "src/ReplicatedStorage/ClientSideCode/SystemModule/SystemTbs/init.luau",
        "game.ReplicatedStorage.ClientSideCode.SystemModule.SystemTbs",
        "SystemTbsClient",
    ),
    (
        "src/ServerStorage/ServerSideCode/System/SystemTbs/Combat.luau",
        "game.ServerStorage.ServerSideCode.System.SystemTbs.Combat",
        "Combat",
    ),
    (
        "src/ServerStorage/ServerSideCode/System/SystemTbs/ActionHandler.luau",
        "game.ServerStorage.ServerSideCode.System.SystemTbs.ActionHandler",
        "ActionHandler",
    ),
    (
        "src/ServerStorage/ServerSideCode/System/SystemTbs/AI.luau",
        "game.ServerStorage.ServerSideCode.System.SystemTbs.AI",
        "AI",
    ),
    (
        "src/ServerStorage/ServerSideCode/System/SystemTbs/MatchStore.luau",
        "game.ServerStorage.ServerSideCode.System.SystemTbs.MatchStore",
        "MatchStore",
    ),
    (
        "src/ReplicatedFirst/AllSideCode/Interface/SystemTbs-Type.luau",
        'game.ReplicatedFirst.AllSideCode.Interface["SystemTbs-Type"]',
        "SystemTbsType",
    ),
]
out = root / "scripts" / "_tmp_json"
out.mkdir(exist_ok=True)
for rel, studio, name in jobs:
    text = (root / rel).read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    payload = (
        f"local inst = {studio}\n"
        f"if not inst then error('missing {name}') end\n"
        "local HttpService = game:GetService('HttpService')\n"
        f"inst.Source = HttpService:JSONDecode({json.dumps(json.dumps(text))})\n"
        "return { name = inst.Name, n = #inst.Source }\n"
    )
    path = out / f"{name}.luau"
    path.write_text(payload, encoding="utf-8")
    print(name, path.stat().st_size)
