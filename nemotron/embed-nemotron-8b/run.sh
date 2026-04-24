#!/bin/bash
QUERY="${1:?Usage: $0 <text> [instruct]  e.g.: $0 \"summit define\" \"Given a question, retrieve passages that answer the question\"}"
INSTRUCT="${2:-}"

if [ -n "$INSTRUCT" ]; then
    INPUT="Instruct: ${INSTRUCT}\nQuery: ${QUERY}"
else
    INPUT="$QUERY"
fi

curl -s http://localhost:8890/v1/embeddings \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"nvidia/llama-embed-nemotron-8b\",
    \"input\": [\"${INPUT}\"],
    \"encoding_format\": \"float\"
  }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print('ERROR:', data['error'])
    sys.exit(1)
emb = data['data'][0]['embedding']
print(f'dim={len(emb)}')
print(f'first 8 values: {emb[:8]}')
print(f'last 4 values: {emb[-4:]}')
if 'usage' in data:
    print(f\"tokens: {data['usage'].get('prompt_tokens', '?')}\")
"
