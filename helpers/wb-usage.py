#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Export WorkBuddy credits/context usage and the real model list for Plasmoid.

All data is read-only and local:
  - model list / credit multipliers: latest WorkBuddy local product config
  - current model: latest session row in workbuddy.db
  - context usage: latest session_usage row in workbuddy.db
  - accumulated credits spent: session_usage.credit_json

Output: ~/.local/state/dsh-widget/wb-usage.json
"""
from __future__ import annotations

import glob
import json
import os
import sqlite3
import tempfile
from datetime import datetime

HOME = os.path.expanduser("~")
DB_PATH = os.path.join(HOME, ".workbuddy", "workbuddy.db")
LOCAL_STORAGE = os.path.join(HOME, ".workbuddy", "local_storage", "*.info")
CACHE_CONFIG = os.path.join(HOME, ".workbuddy", "cache", "acc-product-config-v3.json")
OUT_DIR = os.path.join(HOME, ".local", "state", "dsh-widget")
OUT = os.path.join(OUT_DIR, "wb-usage.json")


def load_product_config() -> dict:
    """Prefer the newest local_storage product cache; fall back to static cache."""
    best_ts = -1
    best: dict = {}
    for path in glob.glob(LOCAL_STORAGE):
        try:
            raw = open(path, encoding="utf-8", errors="replace").read()
            data = json.loads(raw)
            if isinstance(data, list) and data and isinstance(data[0], dict):
                entry = data[0]
                payload = entry.get("data")
                if isinstance(payload, dict) and "models" in payload:
                    ts = int(entry.get("ts") or 0)
                    if ts > best_ts:
                        best_ts, best = ts, payload
        except (OSError, ValueError, TypeError):
            continue
    if best:
        return best
    try:
        with open(CACHE_CONFIG, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def real_models(config: dict) -> list[dict]:
    out: list[dict] = []
    for m in config.get("models") or []:
        if not isinstance(m, dict) or not m.get("id"):
            continue
        out.append({
            "id": m["id"],
            "name": m.get("name") or m["id"],
            "credits": m.get("credits") or "",
        })
    return out


def db_snapshot() -> dict:
    result = {
        "currentModel": "",
        "sessionUsed": 0,
        "sessionSize": 300000,
        "creditSpent": 0.0,
        "creditEntries": 0,
        "sessionTitle": "",
    }
    if not os.path.exists(DB_PATH):
        return result
    try:
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        row = con.execute(
            "SELECT model, title FROM sessions "
            "WHERE model IS NOT NULL AND model != '' ORDER BY updated_at DESC LIMIT 1"
        ).fetchone()
        if row:
            result["currentModel"] = row["model"] or ""
            result["sessionTitle"] = row["title"] or ""

        row = con.execute(
            "SELECT used, size, updated_at FROM session_usage "
            "ORDER BY updated_at DESC LIMIT 1"
        ).fetchone()
        if row:
            result["sessionUsed"] = int(row["used"] or 0)
            result["sessionSize"] = int(row["size"] or 300000)

        total = 0.0
        count = 0
        for (raw,) in con.execute("SELECT credit_json FROM session_usage"):
            if not raw:
                continue
            try:
                values = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if not isinstance(values, dict):
                continue
            for value in values.values():
                try:
                    total += float(value)
                    count += 1
                except (TypeError, ValueError):
                    continue
        result["creditSpent"] = round(total, 2)
        result["creditEntries"] = count
        con.close()
    except sqlite3.Error:
        pass
    return result


def build() -> dict:
    config = load_product_config()
    models = real_models(config)
    snap = db_snapshot()

    current = snap["currentModel"]
    if not current:
        for m in models:
            if m.get("id") == "hy4flash-free":
                current = m["id"]
                break
    if current and not any(m["id"] == current for m in models):
        models.insert(0, {"id": current, "name": current, "credits": ""})

    credits = ""
    for m in models:
        if m["id"] == current:
            credits = m.get("credits") or ""
            break

    used = snap["sessionUsed"]
    size = snap["sessionSize"] or 300000
    percent = round(used * 100.0 / size, 1) if size else 0.0

    return {
        "currentModel": current,
        "currentModelName": next((m["name"] for m in models if m["id"] == current), current),
        "modelCredits": credits,
        "creditSpent": snap["creditSpent"],
        "creditEntries": snap["creditEntries"],
        "sessionUsed": used,
        "sessionSize": size,
        "usagePercent": percent,
        "sessionTitle": snap["sessionTitle"],
        "models": models,
        "updated": int(datetime.now().timestamp()),
    }


def main() -> None:
    data = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix="wb-usage-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, OUT)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


if __name__ == "__main__":
    main()
