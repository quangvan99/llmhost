#!/bin/bash
set -e

GPU_IDS="${1:-2}"
PORT="${2:-8892}"
TENSOR_PARALLEL=$(echo "$GPU_IDS" | tr ',' '\n' | wc -l)
GPU_TAG=$(echo "$GPU_IDS" | tr -d ',')
CONTAINER_NAME="gemma4-fp8-gpu${GPU_TAG}-p${PORT}"

MODEL_DIR="gemma-4-26B-A4B-it-FP8-Dynamic"
HF_REPO="RedHatAI/gemma-4-26B-A4B-it-FP8-Dynamic"

if ! command -v hf &>/dev/null; then
    echo "hf not found, installing..."
    pip install -q huggingface-hub
fi

if [ ! -f "./$MODEL_DIR/config.json" ]; then
    echo "Weights not found. Downloading $HF_REPO ..."
    hf download "$HF_REPO" --local-dir "./$MODEL_DIR"
fi

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
    --served-model-name "/$MODEL_DIR" \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --gpu-memory-utilization 0.9 \
    --max-model-len 4096 \
    --enable-prefix-caching \
    --enable-chunked-prefill \
    --enable-auto-tool-choice \
    --tool-call-parser gemma4

echo "Container started. Logs: docker logs -f ${CONTAINER_NAME}"
