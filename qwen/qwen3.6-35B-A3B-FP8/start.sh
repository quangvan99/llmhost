#!/bin/bash
set -e

GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0,1,2,3 8889}"
PORT="${2:-8889}"
TENSOR_PARALLEL=$(echo "$GPU_IDS" | tr ',' '\n' | wc -l)
GPU_TAG=$(echo "$GPU_IDS" | tr -d ',')
CONTAINER_NAME="qwen35b-gpu${GPU_TAG}-p${PORT}"

MODEL_DIR="Qwen3.6-35B-A3B-FP8"
HF_REPO="Qwen/Qwen3.6-35B-A3B-FP8"

# Download weights if not present
if [ ! -f "./$MODEL_DIR/config.json" ]; then
    echo "Weights not found. Downloading $HF_REPO ..."
    hf download "$HF_REPO" --local-dir "./$MODEL_DIR"
fi

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing existing container '${CONTAINER_NAME}'..."
    docker rm -f "${CONTAINER_NAME}"
fi

echo "Starting vLLM container '${CONTAINER_NAME}' (GPUs: $GPU_IDS, tensor-parallel-size: $TENSOR_PARALLEL, port: $PORT)..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    --gpus "\"device=$GPU_IDS\"" \
    -v "$(pwd)/$MODEL_DIR:/$MODEL_DIR" \
    -p "$PORT:8000" \
    --ipc=host \
    vllm/vllm-openai:latest \
    --model "/$MODEL_DIR" \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --trust-remote-code \
    --gpu-memory-utilization 0.85 \
    --max-model-len 16384   \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3 \
    --default-chat-template-kwargs '{"enable_thinking": false}'
echo "Container started. Logs: docker logs -f ${CONTAINER_NAME}"
