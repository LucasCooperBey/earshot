#!/usr/bin/env python3
"""Print the last substantial assistant TEXT response from the current Claude Code session.

Resolves the transcript by $CLAUDE_CODE_SESSION_ID via glob over ~/.claude/projects/*/
(machine-agnostic — no hardcoded project slug); falls back to the most recently modified
*.jsonl. Returns the last assistant text BEFORE the last real user message, so the turn
that invoked earshot is excluded. Skips tool-call-only messages.
Exit 0 with text on stdout; nonzero (empty) if nothing usable is found.
"""
import os
import sys
import json
import glob

PROJ = os.path.expanduser("~/.claude/projects")


def transcript_path():
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if sid:
        hits = glob.glob(os.path.join(PROJ, "*", f"{sid}.jsonl"))
        if hits:
            return hits[0]
    files = sorted(glob.glob(os.path.join(PROJ, "*", "*.jsonl")), key=os.path.getmtime, reverse=True)
    return files[0] if files else None


def text_of(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return ""


def is_real_response(o):
    if o.get("type") != "assistant":
        return ""
    msg = o.get("message") or {}
    if msg.get("role") != "assistant":
        return ""
    t = text_of(msg).strip()
    if not t or len(t) < 40:
        return ""
    return t


def main():
    path = transcript_path()
    if not path or not os.path.exists(path):
        return 1
    entries = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    last_user = -1
    for i, o in enumerate(entries):
        if o.get("type") == "user" and text_of(o.get("message") or {}).strip():
            last_user = i
    start = last_user - 1 if last_user >= 0 else len(entries) - 1
    for i in range(start, -1, -1):
        t = is_real_response(entries[i])
        if t:
            sys.stdout.write(t)
            return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
