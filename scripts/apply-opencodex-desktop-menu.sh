#!/usr/bin/env bash
set -euo pipefail

codex_home="\${CODEX_HOME:-$HOME/.codex}"
opencodex_home="\${OPENCODEX_HOME:-$HOME/.opencodex}"
router_url="\${OPENCODEX_ROUTER_URL:-http://127.0.0.1:10100/v1}"
catalog_path="$codex_home/opencodex-catalog.json"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$codex_home/backups/opencodex-desktop-menu-$timestamp"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

backup_file() {
  local path="$1"
  local name="$2"
  if [ -f "$path" ]; then
    cp "$path" "$backup_dir/$name"
  fi
}

need ocx
need jq
need python3
need curl
need security

mkdir -p "$backup_dir"
backup_file "$codex_home/config.toml" codex-config.toml
backup_file "$opencodex_home/config.json" opencodex-config.json
backup_file "$catalog_path" opencodex-catalog.json
backup_file "$codex_home/opencodex.config.toml" opencodex.config.toml

echo "backup: $backup_dir"

if [ ! -f "$codex_home/config.toml" ]; then
  echo "missing $codex_home/config.toml" >&2
  exit 1
fi

if [ ! -f "$opencodex_home/config.json" ]; then
  echo "missing $opencodex_home/config.json" >&2
  exit 1
fi

kimi_key="$(security find-generic-password \
  -s 'OpenCodex Provider Credential' \
  -a 'provider:kimi' \
  -w 2>/dev/null || true)"

if [ -z "$kimi_key" ]; then
  echo "missing Kimi key in Keychain: service='OpenCodex Provider Credential', account='provider:kimi'" >&2
  echo "configure the key first, then rerun this script." >&2
  exit 1
fi

ocx restart
ocx ready --json --wait --timeout 25

ocx provider add moonshot-cn \
  --adapter openai-chat \
  --base-url https://api.moonshot.cn/v1 \
  --api-key "$kimi_key" \
  --default-model kimi-k3 \
  --force

tmp_config="$(mktemp)"
jq '
  .providers.moonshot.disabled = true
  | .providers["moonshot-cn"].disabled = false
  | .providers["qwen-cloud"].disabled = false
  | .providers.zai.disabled = false
  | .disabledModels = ((.disabledModels // [])
      | map(select(. != "moonshot-cn/kimi-k3"))
      | map(select(. != "moonshot-cn/kimi-k2.7-code"))
    )
' "$opencodex_home/config.json" > "$tmp_config"
mv "$tmp_config" "$opencodex_home/config.json"

python3 - "$codex_home/config.toml" "$router_url" "$catalog_path" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
router_url = sys.argv[2]
catalog_path = sys.argv[3]
text = path.read_text()

def upsert_top_level(src, key, value):
    line = f'{key} = "{value}"'
    pattern = re.compile(rf'^{re.escape(key)}\s*=.*$', re.M)
    if pattern.search(src):
        return pattern.sub(line, src, count=1)
    if not src.endswith('\n'):
        src += '\n'
    return src + line + '\n'

text = re.sub(r'^model_provider\s*=.*\n?', '', text, flags=re.M)
text = re.sub(r'(?ms)^\[model_providers\.[^\n]+\]\n.*?(?=^\[|\Z)', '', text)
text = upsert_top_level(text, 'openai_base_url', router_url)
text = upsert_top_level(text, 'model_catalog_json', catalog_path)
text = upsert_top_level(text, 'model', 'moonshot-cn/kimi-k2.7-code')
path.write_text(text)
PY

ocx sync

python3 - "$catalog_path" <<'PY'
import json
import os
import sys
import tempfile

catalog_path = sys.argv[1]
allow_order = [
    'gpt-5.6-terra',
    'gpt-5.5',
    'deepseek/deepseek-v4-flash',
    'deepseek/deepseek-v4-pro',
    'qwen-cloud/qwen3.8-max',
    'qwen-cloud/qwen3-coder-plus',
    'moonshot-cn/kimi-k3',
    'moonshot-cn/kimi-k2.7-code',
    'zai/glm-5.2',
    'zai/glm-5.3',
    'qwen-cloud/MiniMax-MiniMax-M3',
]

with open(catalog_path) as f:
    catalog = json.load(f)

by_slug = {m.get('slug'): m for m in catalog.get('models', [])}
catalog['models'] = [by_slug[s] for s in allow_order if s in by_slug]

fd, tmp = tempfile.mkstemp(prefix='opencodex-catalog.', suffix='.json', dir=os.path.dirname(catalog_path))
with os.fdopen(fd, 'w') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write('\n')
os.replace(tmp, catalog_path)

print('kept models:', len(catalog['models']))
for model in catalog['models']:
    print(model.get('slug'))
PY

ocx sync-cache

test_model() {
  local label="$1"
  local model="$2"
  local phrase="$3"
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":"只输出 "+sys.argv[2]}],"max_tokens":768,"stream":False}, ensure_ascii=False))' "$model" "$phrase")"

  curl -sS -m 120 http://127.0.0.1:10100/v1/chat/completions \
    -H 'Authorization: Bearer dummy' \
    -H 'Content-Type: application/json' \
    -d "$payload" |
  python3 -c 'import json,sys
d=json.load(sys.stdin)
if "error" in d:
    print(sys.argv[1], "ERROR", d["error"].get("message"))
    raise SystemExit(1)
content = d.get("choices", [{}])[0].get("message", {}).get("content")
print(sys.argv[1], d.get("model"), repr(content))
if sys.argv[2] not in (content or ""):
    raise SystemExit(1)' "$label" "$phrase"
}

test_model kimi27 moonshot-cn/kimi-k2.7-code KIMI_OK
test_model kimi3 moonshot-cn/kimi-k3 KIMI3_OK
test_model glm52 zai/glm-5.2 GLM52_OK
test_model glm53 zai/glm-5.3 GLM53_OK
test_model qwen qwen-cloud/qwen3.8-max QWEN_OK
test_model ds deepseek/deepseek-v4-flash DS_OK

echo
echo "Desktop cache refreshed. To force the visible menu to reload, run:"
echo "  ocx sync-cache --restart-codex"
echo "This restarts Codex app-server and may disconnect the current task."
echo
echo "verify sessions remain:"
find "$codex_home/sessions" -name '*.jsonl' 2>/dev/null | wc -l

