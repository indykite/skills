#!/usr/bin/env python3
"""build-manifests.py — generate per-agent plugin manifests from manifest.yaml.

Reads the canonical bundle metadata from `manifest.yaml` at the repo root and
emits:

    .claude-plugin/plugin.json       # Claude Code plugin manifest
    .claude-plugin/marketplace.json  # Claude Code marketplace listing
    gemini-extension.json            # Gemini CLI extension manifest

The generated files are committed so installers can fetch them directly from
the repo without running this script. Run the script whenever `manifest.yaml`
changes, then commit the regenerated outputs.

Usage:
    python3 scripts/build-manifests.py    # run from the repo root

Requires: PyYAML (`pip install pyyaml`).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML is required: pip install pyyaml\n")
    sys.exit(1)


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "manifest.yaml"


def load_manifest() -> dict:
    if not SOURCE.exists():
        sys.stderr.write(f"{SOURCE} not found\n")
        sys.exit(1)
    cfg = yaml.safe_load(SOURCE.read_text())
    for required in ("common", "skills", "config"):
        if required not in cfg:
            sys.stderr.write(f"manifest.yaml missing required top-level key: {required}\n")
            sys.exit(1)
    return cfg


def build_claude_plugin(cfg: dict) -> dict:
    common = cfg["common"]
    skills = cfg["skills"]
    config = cfg["config"]
    return {
        "name": common["name"],
        "version": common["version"],
        "description": common["description"],
        "author": common["author"],
        "homepage": common["homepage"],
        "license": common["license"],
        "repository": common["repository"],
        "skills": [f"./{name}" for name in skills],
        "userConfig": {
            key: {
                "title": entry["title"],
                "description": entry["description"],
                "type": "string",
                "sensitive": bool(entry.get("sensitive", False)),
            }
            for key, entry in config.items()
        },
    }


def build_claude_marketplace(cfg: dict) -> dict:
    common = cfg["common"]
    return {
        "name": f"{common['name']}-marketplace",
        "owner": common["author"],
        "metadata": {"description": common["description"]},
        "plugins": [{"name": common["name"], "source": "./"}],
    }


def build_gemini_extension(cfg: dict) -> dict:
    common = cfg["common"]
    config = cfg["config"]
    context_file = cfg.get("gemini_context_file", "README.md")
    return {
        "name": common["name"],
        "version": common["version"],
        "description": common["description"],
        "contextFileName": context_file,
        "settings": [
            {
                "name": entry["title"],
                "description": entry["description"],
                "envVar": key,
            }
            for key, entry in config.items()
        ],
    }


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {path.relative_to(REPO_ROOT)}")


def main() -> None:
    cfg = load_manifest()
    write_json(REPO_ROOT / ".claude-plugin" / "plugin.json", build_claude_plugin(cfg))
    write_json(REPO_ROOT / ".claude-plugin" / "marketplace.json", build_claude_marketplace(cfg))
    write_json(REPO_ROOT / "gemini-extension.json", build_gemini_extension(cfg))


if __name__ == "__main__":
    main()
