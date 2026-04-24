#!/bin/bash
set -e

GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0,1 8890}"
PORT="${2:-8890}"
TENSOR_PARALLEL=$(echo "$GPU_IDS" | tr ',' '\n' | wc -l)

MODEL_DIR="llama-embed-nemotron-8b"
MODEL_ID="nvidia/llama-embed-nemotron-8b"

# Install huggingface-hub CLI if not available
if ! command -v hf &>/dev/null; then
    echo "hf not found, installing..."
    pip install -q huggingface-hub
fi

# Download model if folder doesn't exist or is empty
if [ ! -d "$MODEL_DIR" ] || [ -z "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
    echo "Downloading model $MODEL_ID..."
    hf download "$MODEL_ID" --local-dir "$MODEL_DIR"
else
    echo "Model folder '$MODEL_DIR' already exists, skipping download."
fi

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q '^llamaembed8b$'; then
    echo "Removing existing container 'llamaembed8b'..."
    docker rm -f llamaembed8b
fi

echo "Starting vLLM container 'llamaembed8b' (GPUs: $GPU_IDS, tensor-parallel-size: $TENSOR_PARALLEL, port: $PORT)..."
docker run -d \
    --name llamaembed8b \
    --gpus "\"device=$GPU_IDS\"" \
    -v "$(pwd)/$MODEL_DIR:/$MODEL_DIR" \
    -p "$PORT:8000" \
    --ipc=host \
    vllm/vllm-openai:latest \
    --model "/$MODEL_DIR" \
    --served-model-name "$MODEL_ID" \
    --runner pooling \
    --trust-remote-code \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --gpu-memory-utilization 0.7 \
    --max-model-len 32768

echo "Container started. Logs: docker logs -f llamaembed8b"
