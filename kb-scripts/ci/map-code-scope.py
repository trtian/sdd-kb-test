#!/usr/bin/env python3
"""Map git changed files + optional GitNexus symbol list → capability scope hints for KB CI."""
import fnmatch
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


def load_map(path: str) -> dict:
    if yaml is None:
        return {}
    p = Path(path)
    if not p.is_file():
        return {}
    with p.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def match_capability(changed: str, cap_id: str, cfg: dict) -> bool:
    patterns = (cfg or {}).get("path_patterns") or []
    for pat in patterns:
        if fnmatch.fnmatch(changed.replace("\\", "/"), pat):
            return True
    return False


def match_sdd(changed: str, cap_id: str, cfg: dict) -> bool:
    patterns = (cfg or {}).get("sdd_paths") or []
    for pat in patterns:
        if fnmatch.fnmatch(changed.replace("\\", "/"), pat):
            return True
    return False


def main() -> None:
    map_file = os.environ.get("CODE_CAPABILITY_MAP", "")
    if not map_file:
        root = Path(__file__).resolve().parent.parent
        map_file = str(root / "samples" / "code-capability-map.yml")

    changed_file = os.environ.get("CHANGED_FILES_LIST", "")
    symbols_file = os.environ.get("GITNEXUS_SYMBOLS_FILE", "")
    git_base = os.environ.get("GIT_BASE", "")
    git_head = os.environ.get("GIT_HEAD", "HEAD")

    changed = []
    if changed_file and Path(changed_file).is_file():
        changed = [
            line.strip()
            for line in Path(changed_file).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    symbols = []
    if symbols_file and Path(symbols_file).is_file():
        try:
            symbols = json.loads(Path(symbols_file).read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            symbols = []

    cap_map = load_map(map_file)
    code_caps = set()
    sdd_caps = set()
    for f in changed:
        for cap_id, cfg in cap_map.items():
            if match_capability(f, cap_id, cfg):
                code_caps.add(cap_id)
            if match_sdd(f, cap_id, cfg):
                sdd_caps.add(cap_id)

    out = {
        "gitBase": git_base,
        "gitHead": git_head,
        "changedFiles": changed,
        "matchedCapabilitiesFromCode": sorted(code_caps),
        "matchedCapabilitiesFromSdd": sorted(sdd_caps),
        "matchedCapabilities": sorted(code_caps | sdd_caps),
        "gitnexusSymbols": symbols if isinstance(symbols, list) else [],
        "mapFile": map_file,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
