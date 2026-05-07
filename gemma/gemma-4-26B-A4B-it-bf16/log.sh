#!/bin/bash
GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0,1,2,3 8892}"
PORT="${2:-8892}"
GPU_TAG=$(echo "$GPU_IDS" | tr -d ',')
CONTAINER_NAME="gemma4-gpu${GPU_TAG}-p${PORT}"

docker logs -f "${CONTAINER_NAME}"
