#!/bin/bash
python3 - "$@" <<'EOF'
import asyncio
import time
import httpx
import argparse
from dataclasses import dataclass

BASE_URL = "http://localhost:8890"
MODEL = "nvidia/llama-embed-nemotron-8b"
PROMPT = "Instruct: Given a question, retrieve passages that answer the question\nQuery: What is the theory of relativity?"
NUM_USERS = 20
REQUESTS_PER_USER = 5

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
    latencies: list = None
    requests: int = 0
    errors: int = 0
    dim: int = 0
    done: bool = False

    def __post_init__(self):
        if self.latencies is None:
            self.latencies = []


async def embed_user(client: httpx.AsyncClient, user_id: int, prompt: str, n_req: int, stats: Stats):
    color = COLORS[user_id % len(COLORS)]
    prefix = f"{color}{BOLD}[U{user_id:02d}]{RESET}{color} "

    for i in range(n_req):
        t0 = time.perf_counter()
        try:
            r = await client.post(
                f"{BASE_URL}/v1/embeddings",
                json={
                    "model": MODEL,
                    "input": [prompt],
                    "encoding_format": "float",
                },
                timeout=120,
            )
            r.raise_for_status()
            data = r.json()
            lat = time.perf_counter() - t0
            stats.latencies.append(lat)
            stats.requests += 1
            stats.dim = len(data["data"][0]["embedding"])
            async with print_lock:
                print(f"{prefix}req={i+1}/{n_req} lat={lat*1000:.0f}ms dim={stats.dim}{RESET}")
        except Exception as e:
            stats.errors += 1
            async with print_lock:
                print(f"{color}{BOLD}[U{user_id:02d}] ERROR: {e}{RESET}")

    stats.done = True
    async with print_lock:
        if stats.latencies:
            avg = sum(stats.latencies) / len(stats.latencies)
            print(
                f"{color}{BOLD}[U{user_id:02d} DONE]{RESET}"
                f"{color} req={stats.requests} err={stats.errors} "
                f"avg_lat={avg*1000:.0f}ms{RESET}"
            )


async def run(base_url: str, num_users: int, n_req: int, prompt: str):
    global BASE_URL
    BASE_URL = base_url

    print(f"\n{BOLD}{'='*70}{RESET}")
    print(f"{BOLD}  Embedding stress test — {num_users} concurrent users x {n_req} reqs{RESET}")
    print(f"  Prompt: \"{prompt[:60]}{'...' if len(prompt) > 60 else ''}\"")
    print(f"{BOLD}{'='*70}{RESET}\n")

    stats_list = [Stats(user_id=i + 1) for i in range(num_users)]

    async with httpx.AsyncClient() as client:
        t_wall = time.perf_counter()
        await asyncio.gather(*[
            embed_user(client, i + 1, prompt, n_req, stats_list[i])
            for i in range(num_users)
        ])
        wall_time = time.perf_counter() - t_wall

    all_lats = [lat for s in stats_list for lat in s.latencies]
    total_req = sum(s.requests for s in stats_list)
    total_err = sum(s.errors for s in stats_list)

    print(f"\n{BOLD}{'='*70}{RESET}")
    print(f"{BOLD}  SUMMARY{RESET}")
    print(f"{'='*70}")
    print(f"  Users        : {num_users}  (total req={total_req}, err={total_err})")
    print(f"  Wall time    : {wall_time:.2f}s")
    print(f"  Throughput   : {total_req/wall_time:.2f} req/s")
    if all_lats:
        all_lats.sort()
        mean = sum(all_lats) / len(all_lats)
        p50 = all_lats[len(all_lats) // 2]
        p95 = all_lats[int(len(all_lats) * 0.95)]
        p99 = all_lats[int(len(all_lats) * 0.99)]
        print(f"  Latency mean : {mean*1000:.0f}ms")
        print(f"  Latency p50  : {p50*1000:.0f}ms")
        print(f"  Latency p95  : {p95*1000:.0f}ms")
        print(f"  Latency p99  : {p99*1000:.0f}ms")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=BASE_URL)
    parser.add_argument("--users", type=int, default=NUM_USERS)
    parser.add_argument("--requests", type=int, default=REQUESTS_PER_USER)
    parser.add_argument("--prompt", default=PROMPT)
    args = parser.parse_args()

    asyncio.run(run(args.base_url, args.users, args.requests, args.prompt))
EOF
