#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WorkBuddy 会话摘要导出器 —— 给 KDE 原生 Plasmoid 用。

只读扫描 ~/.workbuddy/projects/*/*.jsonl，取最近一次会话的：
  - 标题 (ai-title)
  - 问答轮次 (message role=user/assistant)
  - 思考过程 (reasoning.rawContent[].text)
导出成 JSON 到 ~/.local/state/dsh-widget/wb-summary.json，
由 Plasmoid 用 XMLHttpRequest 读 file:// 展示（不阻塞、低 CPU）。

设计：流式逐行读 + 只保留尾部若干轮，避免把 18MB 的 jsonl 全量载入内存。
"""
import json
import os
import glob
import sys

PROJECTS = os.path.expanduser("~/.workbuddy/projects")
OUT = os.path.expanduser("~/.local/state/dsh-widget/wb-summary.json")
MAX_TURNS = 12          # 最多保留最近 12 条问答
MAX_TEXT = 1400         # 单段文本上限，防止摘要文件过大

SYS_MARK = "<system-reminder"   # 用户消息里混进的系统提醒，正文要剥掉
WRAP_TAGS = ("user_query", "cb_summary")   # 包裹正文的标签，取其内部文本


def clean_text(s: str) -> str:
    """去掉 user content 里注入的 system-reminder / 包裹标签，只留真实输入。"""
    if not s:
        return ""
    if SYS_MARK in s:
        parts = [p.strip() for p in s.split(SYS_MARK)]
        kept = []
        for p in parts:
            if "</system-reminder>" in p:
                p = p.split("</system-reminder>", 1)[-1].strip()
            if p and not p.startswith("data-role="):
                kept.append(p)
        s = "\n".join(kept) if kept else ""
    # 取 <user_query>...</user_query> 里的正文；cb_summary 整段丢弃
    for tag in WRAP_TAGS:
        marker = f"<{tag}>"
        if marker in s:
            if tag == "cb_summary":
                # 会话摘要整段没意义，若有 user_query 用它，否则取尖括号外的尾段
                if "<user_query>" in s:
                    s = s.split("<user_query>", 1)[1]
                else:
                    s = s.split(f"</{tag}>", 1)[-1]
            s = s.split(marker, 1)[-1]
    for tag in WRAP_TAGS:
        s = s.replace(f"</{tag}>", "")
    s = s.strip()
    # 去掉残留的尖括号包裹（如 <omitted />）
    return s[:MAX_TEXT]


def text_from_content(content, keys=("text",)):
    parts = []
    if not isinstance(content, list):
        return ""
    for c in content:
        if not isinstance(c, dict):
            continue
        for k in keys:
            v = c.get(k)
            if isinstance(v, str) and v.strip():
                parts.append(v.strip())
    return "\n".join(parts)


def all_session_files(limit=10):
    files = glob.glob(os.path.join(PROJECTS, "*", "*.jsonl"))
    files.sort(key=os.path.getmtime, reverse=True)
    return files[:limit]


def parse_session(path):
    """解析单个会话文件 -> {id,title,mtime,turns}, 失败返回 None。"""
    turns, title = [], ""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if not line.strip():
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                t = o.get("type")
                if t == "ai-title" and o.get("aiTitle"):
                    title = o["aiTitle"]
                elif t == "message":
                    role = o.get("role")
                    txt = text_from_content(o.get("content"))
                    if role == "user":
                        txt = clean_text(txt)
                    if txt:
                        turns.append({"role": role, "text": txt[:MAX_TEXT]})
                elif t == "reasoning":
                    rtxt = text_from_content(o.get("rawContent"), keys=("text",))
                    if rtxt:
                        turns.append({"role": "reasoning", "text": rtxt[:MAX_TEXT]})
    except Exception as e:
        print(f"[wb-summary] 读取失败 {path}: {e}", file=sys.stderr)
        return None

    rounds = []
    cur = None
    for item in turns:
        if item["role"] == "user":
            if cur:
                rounds.append(cur)
            cur = {"prompt": item["text"], "response": "", "reasoning": ""}
        elif cur:
            if item["role"] == "assistant":
                cur["response"] = (cur["response"] + "\n" + item["text"]).strip()[:MAX_TEXT]
            elif item["role"] == "reasoning":
                cur["reasoning"] = (cur["reasoning"] + "\n" + item["text"]).strip()[:MAX_TEXT]
    if cur:
        rounds.append(cur)
    rounds = [r for r in rounds if r["prompt"]][-MAX_TURNS:]
    if not rounds:
        return None
    proj = os.path.basename(os.path.dirname(path))
    return {
        "id": os.path.splitext(os.path.basename(path))[0],
        "title": title or proj or "未命名会话",
        "mtime": int(os.path.getmtime(path)),
        "turns": rounds,
    }


def main():
    paths = all_session_files()
    sessions = []
    for p in paths:
        s = parse_session(p)
        if s:
            sessions.append(s)

    result = {
        "title": "WorkBuddy",
        "prompt": "",
        "response": "",
        "reasoning": "",
        "turns": [],
        "mtime": 0,
        "session": "",
        "sessions": sessions,
        "empty": len(sessions) == 0,
    }
    if sessions:
        latest = sessions[0]
        result["title"] = latest["title"]
        result["mtime"] = latest["mtime"]
        result["session"] = latest["id"]
        result["turns"] = latest["turns"]
        last = latest["turns"][-1]
        result["prompt"] = last["prompt"]
        result["response"] = last["response"]
        result["reasoning"] = last["reasoning"]
    write(result)
    print(f"[wb-summary] 已导出 {len(sessions)} 个会话, 最新={result['title']}")


def write(data):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
