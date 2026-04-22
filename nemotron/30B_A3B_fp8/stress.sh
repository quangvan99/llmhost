#!/bin/bash
python3 - "$@" <<'EOF'
import asyncio
import time
import httpx
import json
import argparse
from dataclasses import dataclass

BASE_URL = "http://localhost:8889"
MODEL = "/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8"
PROMPT = "Explain the theory of relativity in detail."
NUM_USERS = 20

COLORS = [
    "\033[91m", "\033[92m", "\033[93m", "\033[94m", "\033[95m",
    "\033[96m", "\033[97m", "\033[33m", "\033[35m", "\033[36m",
    "\033[31m", "\033[32m", "\033[34m", "\033[90m", "\033[37m",
    "\033[38;5;208m", "\033[38;5;129m", "\033[38;5;46m", "\033[38;5;201m", "\033[38;5;51m",
]
RESET = "\033[0m"
BOLD = "\033[1m"

print_lock = asyncio.Lock()


@dataclass
class Stats:
    user_id: int
    ttfb: float = 0.0
    total_time: float = 0.0
    tokens: int = 0
    done: bool = False
    error: str = ""


async def stream_user(client: httpx.AsyncClient, user_id: int, prompt: str, stats: Stats):
    color = COLORS[user_id % len(COLORS)]
    prefix = f"{color}{BOLD}[U{user_id:02d}]{RESET}{color} "
    t_start = time.perf_counter()
    first_token = None

    try:
        async with client.stream(
            "POST",
            f"{BASE_URL}/v1/chat/completions",
            json={
                "model": MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "stream": True,
                "max_tokens": 300,
                "chat_template_kwargs": {"enable_thinking": False},
            },
            timeout=120,
        ) as r:
            async for line in r.aiter_lines():
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                chunk = json.loads(data)
                content = chunk["choices"][0]["delta"].get("content", "")
                if content:
                    if first_token is None:
                        first_token = time.perf_counter()
                        stats.ttfb = first_token - t_start
                    stats.tokens += 1
                    async with print_lock:
                        print(f"{prefix}{content}{RESET}", end="", flush=True)

    except Exception as e:
        stats.error = str(e)
        async with print_lock:
            print(f"{color}{BOLD}[U{user_id:02d}] ERROR: {e}{RESET}")

    stats.total_time = time.perf_counter() - t_start
    stats.done = True
    async with print_lock:
        tps = stats.tokens / stats.total_time if stats.total_time > 0 else 0
        print(
            f"\n{color}{BOLD}[U{user_id:02d} DONE]{RESET}"
            f"{color} ttfb={stats.ttfb:.2f}s  total={stats.total_time:.2f}s  "
            f"tokens={stats.tokens}  tok/s={tps:.1f}{RESET}"
        )


async def run(base_url: str, num_users: int, prompt: str):
    global BASE_URL
    BASE_URL = base_url

    print(f"\n{BOLD}{'='*70}{RESET}")
    print(f"{BOLD}  Streaming stress test — {num_users} concurrent users{RESET}")
    print(f"  Prompt: \"{prompt[:60]}{'...' if len(prompt) > 60 else ''}\"")
    print(f"{BOLD}{'='*70}{RESET}\n")

    stats_list = [Stats(user_id=i + 1) for i in range(num_users)]

    async with httpx.AsyncClient() as client:
        t_wall = time.perf_counter()
        await asyncio.gather(*[
            stream_user(client, i + 1, prompt, stats_list[i])
            for i in range(num_users)
        ])
        wall_time = time.perf_counter() - t_wall

    ok = [s for s in stats_list if s.done and not s.error]
    fail = [s for s in stats_list if s.error]
    total_tokens = sum(s.tokens for s in ok)

    print(f"\n{BOLD}{'='*70}{RESET}")
    print(f"{BOLD}  SUMMARY{RESET}")
    print(f"{'='*70}")
    print(f"  Users        : {num_users}  (ok={len(ok)}, fail={len(fail)})")
    print(f"  Wall time    : {wall_time:.2f}s")
    print(f"  Total tokens : {total_tokens}")
    print(f"  System tok/s : {total_tokens/wall_time:.1f}")
    if ok:
        ttfbs = sorted(s.ttfb for s in ok)
        print(f"  TTFB mean    : {sum(ttfbs)/len(ttfbs):.2f}s")
        print(f"  TTFB p95     : {ttfbs[int(len(ttfbs)*0.95)]:.2f}s")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=BASE_URL)
    parser.add_argument("--users", type=int, default=NUM_USERS)
    parser.add_argument("--prompt", default=PROMPT)
    args = parser.parse_args()

    asyncio.run(run(args.base_url, args.users, args.prompt))
EOF
