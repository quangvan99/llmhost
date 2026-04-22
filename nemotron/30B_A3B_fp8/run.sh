#!/bin/bash
QUERY="${1:?Usage: $0 <query> [think]  e.g.: $0 \"Hello\" think}"
THINK=false
[ "$2" = "think" ] && THINK=true

curl -s http://localhost:8889/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$QUERY\"}],
    \"chat_template_kwargs\": {\"enable_thinking\": $THINK}
  }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
msg = data['choices'][0]['message']
if '$THINK' == 'true' and msg.get('reasoning_content'):
    print('<think>')
    print(msg['reasoning_content'])
    print('</think>')
print(msg['content'])
"
