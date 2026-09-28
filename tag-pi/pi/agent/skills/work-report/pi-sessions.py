#!/usr/bin/env python3
"""Extract pi session summaries for work reports.

Usage:
    pi-sessions.py --since 2026-06-08 --until 2026-06-15
"""

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

SESSIONS_DIR = Path.home() / ".pi/agent/sessions"
CLICKHOUSE_MARKER = "Space-Felixoid-github-ClickHouse"
GITHUB_MARKER = "/github/"
MAX_MSG_LEN = 400
DEFAULT_MODEL = "claude-sonnet-4-6"

# Short acknowledgment messages that carry no information for a report
ACK_MESSAGES = frozenset({
    "ok", "okay", "yes", "no", "y", "n", "go", "go for it", "sure",
    "sounds good", "lgtm", "done", "continue", "proceed", "next",
    "thanks", "thank you", "perfect", "nice", "good", "great",
    "go for the next point", "the next round?",
})


def parse_date(s: str) -> datetime:
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(f"Cannot parse date: {s!r}")



def repo_label(cwd: str | None, dir_name: str) -> str:
    """Derive a short 'Org/repo' label, preferring cwd."""
    if cwd:
        idx = cwd.find(GITHUB_MARKER)
        if idx >= 0:
            return cwd[idx + len(GITHUB_MARKER):]
    # Fallback: pull org/repo out of the session dir name
    idx = dir_name.find("-github-")
    if idx >= 0:
        # e.g. --home-...-github-ClickHouse-ClickHouse--
        tail = dir_name[idx + len("-github-"):].strip("-")
        # The org is the first segment (split on first remaining --)
        # Dir names use -- for / separators in path components, but org/repo
        # names may themselves contain dashes, so use the known ClickHouse
        # prefix as anchor when possible.
        return tail.replace("--", "/", 1)
    return dir_name


def is_noise(text: str) -> bool:
    """Return True for messages that add no value to a work report."""
    low = text.strip().lower().rstrip(".!?")
    if low in ACK_MESSAGES:
        return True
    # Skill invocation blobs embedded as user messages
    if low.startswith("<skill "):
        return True
    # Very short (≤ 4 chars) — likely a stray keystroke or single word
    if len(low) <= 4:
        return True
    return False


def dedup_consecutive(messages: list[str]) -> list[str]:
    """Drop consecutive near-duplicate messages (same after lowercasing)."""
    out: list[str] = []
    prev = None
    for msg in messages:
        key = msg.lower().strip()
        if key != prev:
            out.append(msg)
        prev = key
    return out


def extract_session(
    path: Path, since: datetime, until: datetime
) -> tuple[str | None, datetime | None, list[str]]:
    """Return (cwd, first_in_range_ts, [user_messages_in_range]) from a session JSONL."""
    cwd = None
    first_ts: datetime | None = None
    messages: list[str] = []
    since_ms = since.timestamp() * 1000
    until_ms = until.timestamp() * 1000
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                if obj.get("type") == "session":
                    cwd = obj.get("cwd")

                if (
                    obj.get("type") == "message"
                    and obj.get("message", {}).get("role") == "user"
                ):
                    msg_ts_ms = obj["message"].get("timestamp", 0)
                    if not (since_ms <= msg_ts_ms <= until_ms):
                        continue
                    msg_dt = datetime.fromtimestamp(
                        msg_ts_ms / 1000, tz=timezone.utc
                    )
                    if first_ts is None:
                        first_ts = msg_dt
                    for block in obj["message"].get("content", []):
                        if isinstance(block, dict) and block.get("type") == "text":
                            text = block["text"].strip().replace("\n", " ")
                            if text and not is_noise(text):
                                if len(text) > MAX_MSG_LEN:
                                    text = text[:MAX_MSG_LEN] + "…"
                                messages.append(text)
                            break  # one text block per message is enough
    except OSError:
        pass
    return cwd, first_ts, messages


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Summarise pi sessions for ClickHouse work"
    )
    parser.add_argument("--since", required=True, help="Start date (YYYY-MM-DD or ISO)")
    parser.add_argument("--until", required=True, help="End date (YYYY-MM-DD or ISO)")
    args = parser.parse_args()

    since = parse_date(args.since)
    # Make --until inclusive: push to end of that day if no time given
    until = parse_date(args.until)
    if until.hour == 0 and until.minute == 0 and until.second == 0:
        until = until.replace(hour=23, minute=59, second=59)

    # Collect sessions grouped by repo label
    repos: dict[str, list[tuple[datetime, list[str]]]] = defaultdict(list)

    for session_dir in sorted(SESSIONS_DIR.iterdir()):
        if not session_dir.is_dir():
            continue
        if CLICKHOUSE_MARKER not in session_dir.name:
            continue

        for jsonl in sorted(session_dir.glob("*.jsonl")):
            # Skip files last modified before the window — they can't have in-range messages
            if jsonl.stat().st_mtime < since.timestamp():
                continue

            cwd, first_ts, messages = extract_session(jsonl, since, until)
            if not messages or first_ts is None:
                continue
            messages = dedup_consecutive(messages)

            label = repo_label(cwd, session_dir.name)
            repos[label].append((first_ts, messages))

    if not repos:
        print("_No pi sessions found in the requested period._")
        return

    print("## Pi Sessions\n")
    for label in sorted(repos):
        print(f"### {label}\n")
        for ts, messages in sorted(repos[label]):
            print(f"**{ts.strftime('%Y-%m-%d %H:%M UTC')}**\n")
            for msg in messages:
                print(f"- {msg}")
            print()


if __name__ == "__main__":
    main()
