#!/bin/bash
set -e

GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0,1,2,3 8892}"
PORT="${2:-8892}"
TENSOR_PARALLEL=$(echo "$GPU_IDS" | tr ',' '\n' | wc -l)

MODEL_DIR="gemma-4-26B-A4B-it"
MODEL_ID="google/gemma-4-26B-A4B-it"

# Install huggingface-hub CLI if not available
if ! command -v hf &>/dev/null; then
    echo "hf not found, installing..."
    pip install -q huggingface-hub
fi

# Download model (hf download is idempotent: verifies hashes, skips files already complete,
# resumes any partial downloads). Always call it so partial downloads are auto-fixed.
echo "Ensuring model $MODEL_ID is fully downloaded..."
hf download "$MODEL_ID" --local-dir "$MODEL_DIR"

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q '^gemma4$'; then
    echo "Removing existing container 'gemma4'..."
    docker rm -f gemma4
fi

echo "Starting vLLM container 'gemma4' (GPUs: $GPU_IDS, tensor-parallel-size: $TENSOR_PARALLEL, port: $PORT)..."
docker run -d \
    --name gemma4 \
    --gpus "\"device=$GPU_IDS\"" \
    -v "$(pwd)/$MODEL_DIR:/$MODEL_DIR" \
    -p "$PORT:8000" \
    --ipc=host \
    vllm/vllm-openai:latest \
    --model "/$MODEL_DIR" \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --gpu-memory-utilization 0.9 \
    --max-model-len 4096 \
    --enable-auto-tool-choice \
    --tool-call-parser gemma4

echo "Container started. Logs: docker logs -f gemma4"
