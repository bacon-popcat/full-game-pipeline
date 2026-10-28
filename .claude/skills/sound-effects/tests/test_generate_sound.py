"""Offline contracts for the sound generator and bundled provider."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SKILL = Path(__file__).resolve().parent.parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


GENERATOR = load_module("sound_generate_test", SKILL / "scripts/generate_sound.py")
ELEVENLABS = load_module(
    "sound_elevenlabs_test", SKILL / "scripts/providers/elevenlabs.py"
)


class GenerateSoundTests(unittest.TestCase):
    def test_fake_provider_writes_audio_and_receipt(self):
        fake = SimpleNamespace(
            generate=lambda request: (
                b"RIFFoffline",
                {"adapter": "fake", "reported_duration": request.duration},
            )
        )
        with tempfile.TemporaryDirectory(prefix="humane-sound-test-") as tmp:
            output = Path(tmp) / "cue.wav"
            argv = [
                "generate_sound.py",
                "--provider", "fake",
                "--name", "panel-settle",
                "--text", "soft settle",
                "--duration", "0.5",
                "--out", str(output),
            ]
            stdout = StringIO()
            with (
                patch.object(sys, "argv", argv),
                patch.object(GENERATOR.importlib, "import_module", return_value=fake),
                redirect_stdout(stdout),
            ):
                self.assertEqual(GENERATOR.main(), 0)

            receipt_path = output.with_suffix(".wav.json")
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            self.assertEqual(output.read_bytes(), b"RIFFoffline")
            self.assertEqual(stdout.getvalue().strip(), str(output))
            self.assertEqual(receipt["provider"], "fake")
            self.assertEqual(receipt["request"]["name"], "panel-settle")
            self.assertEqual(receipt["request"]["duration"], 0.5)
            self.assertEqual(receipt["request"]["output"], str(output))
            self.assertEqual(receipt["adapter"], "fake")

    def test_missing_elevenlabs_key_never_calls_network_or_writes_output(self):
        with tempfile.TemporaryDirectory(prefix="humane-sound-test-") as tmp:
            output = Path(tmp) / "cue.mp3"
            argv = [
                "generate_sound.py",
                "--name", "confirm",
                "--text", "quiet confirmation",
                "--out", str(output),
            ]
            clean_env = {key: value for key, value in os.environ.items()
                         if key != "ELEVENLABS_API_KEY"}
            with (
                patch.object(sys, "argv", argv),
                patch.object(
                    GENERATOR.importlib, "import_module", return_value=ELEVENLABS
                ),
                patch.dict(os.environ, clean_env, clear=True),
                patch.object(ELEVENLABS.urllib.request, "urlopen") as urlopen,
            ):
                with self.assertRaisesRegex(SystemExit, "ELEVENLABS_API_KEY"):
                    GENERATOR.main()

            urlopen.assert_not_called()
            self.assertFalse(output.exists())
            self.assertFalse(output.with_suffix(".mp3.json").exists())

    def test_invalid_duration_fails_before_loading_provider(self):
        with tempfile.TemporaryDirectory(prefix="humane-sound-test-") as tmp:
            output = Path(tmp) / "cue.wav"
            argv = [
                "generate_sound.py",
                "--name", "settle",
                "--text", "soft settle",
                "--duration", "0.1",
                "--out", str(output),
            ]
            stderr = StringIO()
            with (
                patch.object(sys, "argv", argv),
                patch.object(GENERATOR.importlib, "import_module") as load_provider,
                redirect_stderr(stderr),
                self.assertRaises(SystemExit) as raised,
            ):
                GENERATOR.main()

            self.assertEqual(raised.exception.code, 2)
            self.assertIn("--duration must be between 0.5 and 30 seconds", stderr.getvalue())
            load_provider.assert_not_called()
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
