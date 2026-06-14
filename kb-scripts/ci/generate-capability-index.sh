#!/usr/bin/env bash
# 规则生成 capability 导航页（薄 Wiki，无 LLM 改写 spec）
set -euo pipefail
API_BASE="${API_BASE:-http://localhost:8090/api}"
PROJECT_ID="${PROJECT_ID:-1}"
OUT="${1:-./wiki-index.md}"

sections=$(curl -sf "$API_BASE/projects/$PROJECT_ID/sections?status=current")
python3 -c "
import json, sys
from collections import defaultdict
raw = json.load(sys.stdin)
data = raw.get('data', raw)
by_cap = defaultdict(list)
for s in data:
    if not s.get('searchable', True):
        continue
    cap = s.get('capabilityId') or 'general'
    by_cap[cap].append(s)
lines = ['# Capability Index (generated)', '']
for cap in sorted(by_cap):
    lines.append(f'## {cap}')
    lines.append('')
    for s in sorted(by_cap[cap], key=lambda x: x.get('logicalSectionId') or x.get('sectionId','')):
        lid = s.get('logicalSectionId') or s.get('sectionId','')
        hp = s.get('headingPath','')
        sp = s.get('sourcePath','')
        sk = s.get('sliceKind','')
        lines.append(f'- [{hp}]({sp}) — `{lid}` ({sk})')
    lines.append('')
open('$OUT','w').write('\n'.join(lines))
print('wrote', '$OUT')
"
