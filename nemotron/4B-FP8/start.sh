#!/bin/bash
set -e

GPU_IDS="${1:?Usage: $0 <gpu_ids> [port]  e.g.: $0 0 8890}"
PORT="${2:-8890}"
TENSOR_PARALLEL=$(echo "$GPU_IDS" | tr ',' '\n' | wc -l)

MODEL_DIR="NVIDIA-Nemotron-3-Nano-4B-FP8"
MODEL_ID="nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8"

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
if docker ps -a --format '{{.Names}}' | grep -q '^nemotron4b$'; then
    echo "Removing existing container 'nemotron4b'..."
    docker rm -f nemotron4b
fi

echo "Starting vLLM container 'nemotron4b' (GPUs: $GPU_IDS, tensor-parallel-size: $TENSOR_PARALLEL, port: $PORT)..."
docker run -d \
    --name nemotron4b \
    --gpus "\"device=$GPU_IDS\"" \
    -v "$(pwd)/$MODEL_DIR:/$MODEL_DIR" \
    -p "$PORT:8000" \
    --ipc=host \
    vllm/vllm-openai:latest \
    --model "/$MODEL_DIR" \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --trust-remote-code \
    --gpu-memory-utilization 0.85 \
    --max-model-len 16384 \
    --reasoning-parser-plugin "/$MODEL_DIR/nano_v3_reasoning_parser.py" \
    --reasoning-parser nano_v3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --override-generation-config '{"enable_thinking": false}'

echo "Container started. Logs: docker logs -f nemotron4b"
