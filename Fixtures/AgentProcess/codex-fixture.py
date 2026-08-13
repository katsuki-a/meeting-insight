#!/usr/bin/python3

import json
import os
import signal
import sys
import time


mode = os.environ.get("MEETING_INSIGHT_FIXTURE_MODE", "success")
pid_path = os.environ.get("MEETING_INSIGHT_FIXTURE_PID_PATH")
if pid_path:
    with open(pid_path, "w", encoding="utf-8") as handle:
        handle.write(str(os.getpid()))

prompt = sys.stdin.read()

if mode == "success":
    expected_prompt = os.environ.get("MEETING_INSIGHT_FIXTURE_EXPECTED_PROMPT")
    if expected_prompt and prompt != expected_prompt:
        sys.exit(65)
    with open("Sources/DemoApp/FeatureAccessPolicy.swift", "r", encoding="utf-8") as handle:
        if "FeatureAccessPolicy" not in handle.read():
            sys.exit(66)
    card = os.environ["MEETING_INSIGHT_FIXTURE_CARD"]
    events = [
        {"type": "thread.started", "thread_id": "fixture-thread"},
        {"type": "turn.started"},
        {"type": "future.event", "payload": {"forward_compatible": True}},
        {
            "type": "item.completed",
            "item": {"id": "item_1", "type": "agent_message", "text": card},
        },
        {
            "type": "turn.completed",
            "usage": {
                "input_tokens": 1200,
                "cached_input_tokens": 200,
                "output_tokens": 300,
                "reasoning_output_tokens": 100,
            },
        },
    ]
    for event in events:
        print(json.dumps(event), flush=True)
elif mode == "malformed":
    print('{"type":"item.completed","item":', flush=True)
elif mode == "policy":
    print(json.dumps({
        "type": "item.started",
        "item": {"id": "item_web", "type": "web_search"},
    }), flush=True)
    time.sleep(60)
elif mode == "output-limit":
    print("x" * 10_000, flush=True)
elif mode == "crash":
    print("synthetic failure", file=sys.stderr, flush=True)
    sys.exit(7)
elif mode == "hang":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)
