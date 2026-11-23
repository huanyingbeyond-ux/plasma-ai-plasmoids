#!/usr/bin/env python3
"""Extract DSH balance/usage curve from the local cost-meter ledger.

Also exports the *real* model catalog declared by the installed DSH bundle and
the model currently selected in the web profile's patch layer, so the Plasmoid
model dropdown matches the app instead of a hard-coded guess.

Output: ~/.local/state/dsh-widget/usage.json
"""
from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import datetime, timezone

LEDGER = os.path.expanduser("~/.dsh/storages/cost-meter/ledger.json")
OUT_DIR = os.path.expanduser("~/.local/state/dsh-widget")
OUT = os.path.join(OUT_DIR, "usage.json")
CATALOG_JS = os.path.expanduser(
    "~/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/"
    "@deepseek-ai/dsh-llm-deepseek/lib/index.js"
)
PATCH_YML = os.path.expanduser("~/.dsh/profiles/web/cordis.patch.yml")

FALLBACK_CATALOG = [
    {"id": "deepseek-flash", "name": "DeepSeek-V4.1-Flash", "description": ""},
    {"id": "deepseek-v4-pro", "name": "DeepSeek-V4-Pro", "description": ""},
]


def _num(value, default=0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def load_catalog() -> list[dict]:
    """Read DEFAULT_MODELS from the installed dsh-llm-deepseek bundle."""
    try:
        with open(CATALOG_JS, "r", encoding="utf-8") as fh:
            text = fh.read()
        block = text.split("const DEFAULT_MODELS = [", 1)[1].split("];", 1)[0]
    except (OSError, IndexError):
        return FALLBACK_CATALOG

    out: list[dict] = []
    for obj in re.findall(r"\{([\s\S]*?)\}", block):
        mid = re.search(r'id:\s*"([^"]+)"', obj)
        if not mid:
            continue
        name = re.search(r'name:\s*"([^"]+)"', obj)
        desc = re.search(r'description:\s*"([^"]+)"', obj)
        out.append({
            "id": mid.group(1),
            "name": name.group(1) if name else mid.group(1),
            "description": desc.group(1) if desc else "",
        })
    return out or FALLBACK_CATALOG


def current_model() -> str:
    """Read the model selected by dsh's web profile patch layer."""
    try:
        with open(PATCH_YML, "r", encoding="utf-8") as fh:
            text = fh.read()
        match = re.search(r"^\s*model:\s*([A-Za-z0-9_.-]+)\s*$", text, re.M)
        if match:
            return match.group(1)
    except OSError:
        pass
    return "deepseek-flash"


def build() -> dict:
    with open(LEDGER, "r", encoding="utf-8") as fh:
        ledger = json.load(fh)

    balance_ref = ledger.get("balanceRef") or {}
    currency = balance_ref.get("currency") or "CNY"
    current = _num(balance_ref.get("total"))

    rows = []
    for date, raw in (ledger.get("days") or {}).items():
        if not isinstance(raw, dict):
            continue
        cost = _num(raw.get("costCny"))
        if cost <= 0:
            cost = _num(raw.get("apiCostCny"))
        rows.append({
            "date": date,
            "cost": round(cost, 4),
            "calls": int(_num(raw.get("calls"))),
            "input": int(_num(raw.get("input"))),
            "output": int(_num(raw.get("output"))),
            "cacheRead": int(_num(raw.get("cacheRead"))),
        })
    rows.sort(key=lambda r: r["date"])

    start = current + sum(r["cost"] for r in rows)
    running = start
    for row in rows:
        running -= row["cost"]
        row["balance"] = round(running, 4)

    models: dict[str, float] = {}
    for date, raw in (ledger.get("days") or {}).items():
        if not isinstance(raw, dict):
            continue
        for name, info in (raw.get("byProviderModel") or {}).items():
            if isinstance(info, dict):
                val = _num(info.get("costCny")) or _num(info.get("apiCostCny"))
            else:
                val = _num(info)
            models[name] = round(models.get(name, 0.0) + val, 4)

    at = balance_ref.get("at")
    stamp = ""
    if isinstance(at, (int, float)) and at > 0:
        try:
            stamp = datetime.fromtimestamp(at / 1000, tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")
        except (ValueError, OSError, OverflowError):
            stamp = ""

    return {
        "balance": round(current, 4),
        "currency": currency,
        "balanceDate": balance_ref.get("date") or "",
        "balanceAt": stamp,
        "totalCost": round(sum(r["cost"] for r in rows), 4),
        "totalCalls": sum(r["calls"] for r in rows),
        "days": rows,
        "models": [{"name": k, "cost": v} for k, v in
                   sorted(models.items(), key=lambda kv: -kv[1])],
        "catalog": load_catalog(),
        "currentModel": current_model(),
        "updated": int(datetime.now().timestamp()),
    }


def main() -> None:
    data = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix="usage-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, OUT)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


if __name__ == "__main__":
    main()
