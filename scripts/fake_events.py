#!/usr/bin/env python3
"""Fake agent event generator: streams a realistic AgentEvent lifecycle into
the ContextDock Unix socket for demos and manual testing.

Usage: python3 scripts/fake_events.py [socket_path]
"""
import json
import os
import socket
import sys
import time
import uuid
from datetime import datetime, timezone

SOCK = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/Library/Application Support/ContextDock/events.sock")

SESSION = f"sess-demo-{uuid.uuid4().hex[:8]}"

LIFECYCLE = [
    ("sessionStarted", "Demo agent session started"),
    ("userPromptReceived", "Task received: Continue IRIS V2 F09 PRD"),
    ("thinkingStarted", "Reviewing context package"),
    ("toolStarted", "Reading F09 Access Governance notes"),
    ("toolFinished", "Notes reviewed"),
    ("checklistUpdated", "Drafted section 3 of the F09 PRD"),
    ("fileChanged", "F09-PRD.md updated"),
    ("checklistUpdated", "Recorded decisions back to the project note"),
    ("completed", "All steps completed"),
    ("sessionEnded", "Session ended"),
]


def event(etype: str, summary: str) -> dict:
    return {
        "schemaVersion": 1,
        "eventID": {"raw": f"evt-{uuid.uuid4().hex[:12]}"},
        "adapter": "fake",
        "sessionID": {"raw": SESSION},
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "status": "ok",
        "summary": summary,
        "type": etype,
    }


def main() -> None:
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    for etype, summary in LIFECYCLE:
        s.sendall((json.dumps(event(etype, summary)) + "\n").encode())
        print(f"sent {etype}: {summary}")
        time.sleep(0.4)
    s.close()


if __name__ == "__main__":
    main()
