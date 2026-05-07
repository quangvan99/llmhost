#!/bin/bash
GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0 8890}"
PORT="${2:-8890}"
GPU_TAG=$(echo "$GPU_IDS" | tr -d ',')
CONTAINER_NAME="nemotron4b-gpu${GPU_TAG}-p${PORT}"

docker logs -f "${CONTAINER_NAME}"
