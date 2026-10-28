"""ElevenLabs Sound Effects adapter. Credentials stay in ELEVENLABS_API_KEY."""
from __future__ import annotations
import json, os, urllib.error, urllib.request
ENDPOINT = "https://api.elevenlabs.io/v1/sound-generation"

def generate(request):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key: raise SystemExit("ELEVENLABS_API_KEY is not available. Follow setup/references/secrets.md; do not paste a key into this command.")
    payload = {"text": request.text, "prompt_influence": request.influence, "model_id": "eleven_text_to_sound_v2"}
    if request.duration is not None: payload["duration_seconds"] = request.duration
    if request.loop: payload["loop"] = True
    api_request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(), headers={"xi-api-key": key, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(api_request, timeout=90) as response: return response.read(), {"endpoint": ENDPOINT, "request": payload, "character_cost": response.headers.get("character-cost")}
    except urllib.error.HTTPError as error: raise SystemExit(f"ElevenLabs returned HTTP {error.code}: {error.read().decode(errors='replace')}") from error
    except urllib.error.URLError as error: raise SystemExit(f"Could not reach ElevenLabs: {error.reason}") from error
