#!/usr/bin/env python3
"""Generate one sound effect through a selected provider adapter."""
from __future__ import annotations
import argparse, importlib, json
from dataclasses import asdict, dataclass
from pathlib import Path

@dataclass(frozen=True)
class SoundRequest:
    name: str; text: str; duration: float | None; influence: float; loop: bool; output: Path

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", default="elevenlabs", help="Adapter name in scripts/providers")
    parser.add_argument("--name", required=True); parser.add_argument("--text", required=True)
    parser.add_argument("--out", required=True, type=Path); parser.add_argument("--duration", type=float)
    parser.add_argument("--influence", type=float, default=.3); parser.add_argument("--loop", action="store_true")
    args = parser.parse_args()
    if args.duration is not None and not .5 <= args.duration <= 30: parser.error("--duration must be between 0.5 and 30 seconds")
    if not 0 <= args.influence <= 1: parser.error("--influence must be between 0 and 1")
    try: provider = importlib.import_module(f"providers.{args.provider}")
    except ModuleNotFoundError: parser.error(f"unknown provider '{args.provider}'. Add scripts/providers/{args.provider}.py; do not fork the skill or change its prompt contract.")
    request = SoundRequest(args.name, args.text, args.duration, args.influence, args.loop, args.out)
    audio, receipt = provider.generate(request)
    request.output.parent.mkdir(parents=True, exist_ok=True); request.output.write_bytes(audio)
    request.output.with_suffix(request.output.suffix + ".json").write_text(json.dumps({"provider": args.provider, "request": {**asdict(request), "output": str(request.output)}, **receipt}, indent=2) + "\n")
    print(request.output); return 0

if __name__ == "__main__": raise SystemExit(main())
