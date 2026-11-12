"""Measures sound files so they can be tuned by numbers rather than by guessing:
`python tools/sounds/analyze.py [names or paths...]`.

With no arguments it reads every WAV in assets/sounds; a bare name such as `NoticeReward` means
assets/sounds/Garden_NoticeReward.wav. For each file it prints length, peak, loudness, where the
sound starts and dies away, brightness (spectral centroid and the share of energy per band), and
each note: when it starts, its strongest new pitch with the note name, and the step from the last
pitched note in semitones; a start whose new energy is spread out (a rustle, click or thud) is
reported as a noisy hit with no pitch. It also writes a spectrogram PNG per file to tools/sounds/analysis/ (ignored
by git): time runs left to right, frequency runs up on a log scale from 50 Hz to 16 kHz with faint
guide lines at 100 Hz, 1 kHz and 10 kHz, ticks along the bottom every 0.1 s, and a white line at
each detected note start.

Needs numpy only. Loudness is K-weighted (ITU-R BS.1770) over the audible part of the sound, not
gated integrated LUFS, since UI cues are shorter than the 400 ms gating blocks.
"""
import argparse
import math
import struct
import sys
import wave
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOUNDS = ROOT / "assets" / "sounds"
OUT = Path(__file__).resolve().parent / "analysis"

FRAME = 2048
HOP = 256
SILENT_DB = -60  # below this (relative to peak) counts as silence
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
BANDS = ((0, 250, "low"), (250, 2000, "mid"), (2000, 6000, "high"), (6000, 24000, "air"))


def load(path):
    with wave.open(str(path), "rb") as file:
        rate, channels, width, count = file.getframerate(), file.getnchannels(), file.getsampwidth(), file.getnframes()
        raw = file.readframes(count)
    if width == 2:
        data = np.frombuffer(raw, "<i2").astype(np.float64) / 32768
    elif width == 3:
        bytes3 = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        ints = (bytes3[:, 0].astype(np.int32) | (bytes3[:, 1].astype(np.int32) << 8) | (bytes3[:, 2].astype(np.int32) << 16))
        ints[ints >= 1 << 23] -= 1 << 24
        data = ints / float(1 << 23)
    elif width == 4:
        data = np.frombuffer(raw, "<i4").astype(np.float64) / 2**31
    else:
        data = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128) / 128
    return data.reshape(-1, channels).mean(axis=1), rate


def db(x):
    return 20 * math.log10(max(x, 1e-12))


def biquad(x, b, a):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    _, a1, a2 = a
    for i, v in enumerate(x):
        out = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, out
        y[i] = out
    return y


def k_weight(x, rate):
    # The BS.1770 pre-filter (high shelf) and RLB high-pass, derived for any sample rate.
    f0, gain, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = math.tan(math.pi * f0 / rate)
    vh = 10 ** (gain / 20)
    vb = vh**0.4996667741545416
    a0 = 1 + k / q + k * k
    shelf_b = ((vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0)
    shelf_a = (1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / rate)
    a0 = 1 + k / q + k * k
    hp_b = (1, -2, 1)
    hp_a = (1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
    return biquad(biquad(x, shelf_b, shelf_a), hp_b, hp_a)


def stft(x):
    pad = np.concatenate([np.zeros(FRAME // 2), x, np.zeros(FRAME)])
    window = np.hanning(FRAME)
    count = max(1, (len(pad) - FRAME) // HOP)
    frames = np.stack([pad[i * HOP : i * HOP + FRAME] * window for i in range(count)])
    return np.abs(np.fft.rfft(frames, axis=1))


def note_name(freq):
    midi = 69 + 12 * math.log2(freq / 440)
    nearest = round(midi)
    cents = round((midi - nearest) * 100)
    return f"{NOTE_NAMES[nearest % 12]}{nearest // 12 - 1}{cents:+d}c", midi


ONSET_FRAME = 512
ONSET_HOP = 64


def onsets(x, rate):
    """Note start times in seconds: spectral-flux peaks on a short frame, kept only where the
    sound's power actually jumps, so the beating of a decaying tail is not counted as a note."""
    pad = np.concatenate([np.zeros(ONSET_FRAME), x, np.zeros(ONSET_FRAME)])
    window = np.hanning(ONSET_FRAME)
    count = (len(pad) - ONSET_FRAME) // ONSET_HOP
    mag = np.abs(np.fft.rfft(np.stack([pad[i * ONSET_HOP : i * ONSET_HOP + ONSET_FRAME] * window for i in range(count)]), axis=1))
    power = (mag**2).sum(axis=1)
    logmag = np.log1p(100 * mag / (mag.max() or 1))
    flux = np.concatenate([[0], np.maximum(0, np.diff(logmag, axis=0)).sum(axis=1)])
    if flux.max() <= 0:
        return []
    flux /= flux.max()
    floor = power.max() * 10 ** (-30 / 10)
    reach, gap = 3, int(0.03 * rate / ONSET_HOP)
    found = []
    for i in range(1, len(flux) - 1):
        if not (flux[i] >= flux[i - 1] and flux[i] > flux[i + 1] and flux[i] > 0.15):
            continue
        before, after = power[max(0, i - reach)], power[min(len(power) - 1, i + reach)]
        if after < floor or after < 1.25 * before:
            continue
        if found and i - found[-1] < gap:
            if flux[i] > flux[found[-1]]:
                found[-1] = i
            continue
        found.append(i)
    # Frame i is centred at (i * hop + frame / 2 - pad) samples into the sound.
    return [max(0.0, (i * ONSET_HOP + ONSET_FRAME / 2 - ONSET_FRAME) / rate) for i in found]


def new_pitch(x, rate, at):
    """The strongest frequency that appears at `at` seconds: spectrum just after minus just before."""
    n = 8192
    after = x[int(at * rate) : int((at + 0.06) * rate)]
    before = x[max(0, int((at - 0.03) * rate)) : int(at * rate)]
    if len(after) < 64:
        return None
    spec = lambda seg: np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n)) / max(1, len(seg))
    diff = spec(after) - (spec(before) if len(before) >= 64 else 0)
    freqs = np.fft.rfftfreq(n, 1 / rate)
    diff[freqs < 40] = 0
    i = int(np.argmax(diff))
    if diff[i] <= 0 or 0 >= i or i >= len(diff) - 1:
        return None
    # A pitched note's new energy sits in a narrow peak; noise spreads it out. Within +-1/4 octave
    # of the peak, a tone puts most of the new energy within +-3 % of it, or within the window's
    # own blur (2 bins of a 60 ms window, about 33 Hz) for low notes, with the outer band kept
    # three times wider than that.
    blur = 2 * rate / len(after)
    tight_width = max(freqs[i] * 0.03, blur)
    near_width = max(freqs[i] * 0.19, 3 * tight_width)
    near = np.abs(freqs - freqs[i]) < near_width
    tight = np.abs(freqs - freqs[i]) < tight_width
    positive = np.maximum(diff, 0)
    if positive[tight].sum() < 0.6 * (positive[near].sum() or 1):
        return None
    a, b, c = diff[i - 1], diff[i], diff[i + 1]
    shift = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0
    return (i + shift) * rate / n


def colour(v):
    stops = ((0.0, (8, 8, 24)), (0.35, (60, 30, 110)), (0.6, (190, 60, 90)), (0.8, (245, 150, 50)), (1.0, (255, 245, 200)))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if v <= p1:
            t = (v - p0) / (p1 - p0)
            return tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(3))
    return stops[-1][1]


def write_png(path, pixels):
    height, width = len(pixels), len(pixels[0])
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in pixels)
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def spectrogram(path, mag, rate, duration, note_times):
    width, height, low, high = 900, 320, 50.0, min(16000.0, rate / 2)
    freqs = np.fft.rfftfreq(FRAME, 1 / rate)
    level = 20 * np.log10(mag / (mag.max() or 1) + 1e-9)
    norm = np.clip((level + 80) / 80, 0, 1)
    palette = [colour(i / 255) for i in range(256)]
    rows = []
    for y in range(height):
        f = low * (high / low) ** (1 - y / (height - 1))
        bin_ = min(len(freqs) - 1, int(round(f * FRAME / rate)))
        row = []
        for x in range(width):
            frame = min(len(norm) - 1, int(x / width * len(norm)))
            row.append(palette[int(norm[frame, bin_] * 255)])
        rows.append(row)
    for guide in (100, 1000, 10000):
        if low < guide < high:
            y = int(round((1 - math.log(guide / low) / math.log(high / low)) * (height - 1)))
            rows[y] = [tuple(min(255, c + 40) for c in px) for px in rows[y]]
    tick = 0.1
    while tick < duration:
        x = int(tick / duration * width)
        for y in range(height - 8, height):
            rows[y][x] = (230, 230, 230)
        tick += 0.1
    for at in note_times:
        x = min(width - 1, int(at / duration * width))
        for y in range(0, height, 2):
            rows[y][x] = (255, 255, 255)
    write_png(path, rows)


def analyse(path, write_image=True):
    x, rate = load(path)
    duration = len(x) / rate
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    clipped = int(np.sum(np.abs(x) >= 0.999))
    dc = float(np.mean(x)) if len(x) else 0.0

    # Where it is audible: a 5 ms envelope above SILENT_DB relative to the peak.
    win = max(1, int(0.005 * rate))
    env = np.sqrt(np.convolve(x * x, np.ones(win) / win, "same"))
    loud = np.nonzero(env > peak * 10 ** (SILENT_DB / 20))[0]
    start, end = (loud[0] / rate, loud[-1] / rate) if len(loud) else (0.0, 0.0)

    active = x[int(start * rate) : int(end * rate) + 1]
    weighted = k_weight(active, rate) if len(active) else active
    loudness = -0.691 + 10 * math.log10(max(float(np.mean(weighted**2)) if len(weighted) else 0, 1e-12))

    mag = stft(x)
    power = (mag**2).sum(axis=0)
    freqs = np.fft.rfftfreq(FRAME, 1 / rate)
    total = power.sum() or 1
    centroid = float((freqs * power).sum() / total)
    bands = {name: float(power[(freqs >= lo) & (freqs < hi)].sum() / total) for lo, hi, name in BANDS}

    note_times = onsets(x, rate)
    notes, last = [], None
    for at in note_times:
        freq = new_pitch(x, rate, at)
        if freq is None:
            notes.append((at, None, None, None))
            continue
        name, midi = note_name(freq)
        notes.append((at, freq, name, None if last is None else midi - last))
        last = midi

    lines = [
        f"{path.name}",
        f"  length    {duration:.3f} s   audible {start:.3f}-{end:.3f} s ({end - start:.3f} s, silence {SILENT_DB} dB below peak)",
        f"  peak      {db(peak):.1f} dBFS   loudness {loudness:.1f} LUFS (K-weighted, audible part)   clipped samples {clipped}   DC {dc:+.4f}",
        f"  bright    centroid {centroid:.0f} Hz   " + "  ".join(f"{k} {v * 100:.0f}%" for k, v in bands.items()),
        f"  notes     {len(notes)}",
    ]
    for at, freq, name, step in notes:
        if freq is None:
            lines.append(f"    {at:.3f} s   noisy hit, no clear pitch")
        else:
            step_text = "" if step is None else f"   {step:+.1f} st from last"
            lines.append(f"    {at:.3f} s   {freq:7.1f} Hz  {name}{step_text}")
    if write_image:
        OUT.mkdir(exist_ok=True)
        image = OUT / (path.stem + ".png")
        spectrogram(image, mag, rate, duration, note_times)
        lines.append(f"  image     {image.relative_to(ROOT)}")
    return "\n".join(lines)


def resolve(arg):
    path = Path(arg)
    if path.suffix.lower() == ".wav":
        return path if path.is_absolute() else Path.cwd() / path
    candidate = SOUNDS / f"Garden_{arg}.wav"
    return candidate if candidate.exists() else SOUNDS / f"{arg}.wav"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("sounds", nargs="*", help="sound names (NoticeReward) or WAV paths; default: all of assets/sounds")
    parser.add_argument("--no-image", action="store_true", help="skip the spectrogram PNGs")
    args = parser.parse_args()
    paths = [resolve(a) for a in args.sounds] or sorted(SOUNDS.glob("*.wav"))
    missing = [p for p in paths if not p.exists()]
    if missing:
        sys.exit("not found: " + ", ".join(str(p) for p in missing))
    for path in paths:
        print(analyse(path, not args.no_image))
        print()


if __name__ == "__main__":
    main()
