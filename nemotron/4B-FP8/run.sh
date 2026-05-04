#!/bin/bash
QUERY="${1:?Usage: $0 <query> [tool]  e.g.: $0 \"Weather in Hanoi?\" tool}"
MODE="${2:-}"

MODEL="/NVIDIA-Nemotron-3-Nano-4B-FP8"
PORT="${PORT:-8890}"

if [ "$MODE" = "tool" ]; then
    curl -s "http://localhost:$PORT/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$QUERY\"}],
        \"tools\": [{
          \"type\": \"function\",
          \"function\": {
            \"name\": \"get_weather\",
            \"description\": \"Get current weather for a city\",
            \"parameters\": {
              \"type\": \"object\",
              \"properties\": {
                \"city\": {\"type\": \"string\", \"description\": \"City name\"}
              },
              \"required\": [\"city\"]
            }
          }
        }],
        \"max_tokens\": 500
      }" | python3 -c "
import sys, json, re

data = json.load(sys.stdin)
msg = data['choices'][0]['message']
finish = data['choices'][0]['finish_reason']

# vLLM parsed tool_calls (if a future parser handles it)
if msg.get('tool_calls'):
    for tc in msg['tool_calls']:
        fn = tc['function']
        args = json.loads(fn['arguments'])
        print(f'[tool_call] {fn[\"name\"]}({args})')
    sys.exit(0)

# Nemotron XML format: <tool_call><function=name><parameter=p>v</parameter></function></tool_call>
content = msg.get('content', '')
xml_calls = re.findall(r'<tool_call>(.*?)</tool_call>', content, re.DOTALL)
if xml_calls:
    for call in xml_calls:
        fn_match = re.search(r'<function=(\w+)>', call)
        if not fn_match:
            continue
        fn_name = fn_match.group(1)
        params = {m.group(1): m.group(2).strip()
                  for m in re.finditer(r'<parameter=(\w+)>\s*(.*?)\s*</parameter>', call, re.DOTALL)}
        print(f'[tool_call] {fn_name}({params})')
    sys.exit(0)

# No tool call found — print raw content (excluding <think> block)
clean = re.sub(r'<think>.*?</think>', '', content, flags=re.DOTALL).strip()
print(clean or content)
"
else
    curl -s "http://localhost:$PORT/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$QUERY\"}],
        \"max_tokens\": 500
      }" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
content = data['choices'][0]['message']['content'] or ''
# Model may emit thinking text before </think> without opening tag
if '</think>' in content:
    content = content.split('</think>', 1)[-1].strip()
print(content)
"
fi
