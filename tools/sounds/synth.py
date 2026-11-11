"""Synthesizes the phase 7 sound roles (Shared/Sounds) as small WAV files in assets/sounds, with the
standard library only, so they rebuild exactly: `python tools/sounds/synth.py`.

They are made to sit in the ElevenLabs palette's family (warm wood, soil, soft chimes; no voice or
melody, quiet, short): bell-like chimes are a few decaying sine partials, wood is a struck tone
with a filtered noise click, leaves are band-passed noise, scattered as tiny grains for a rustle. Every sound has a soft attack, ends in
silence and peaks at PEAK so none of them is harsh played over and over.

Roles: Harvest (leaves rustling, a green stem snapping and soil crumbling off the roots), HarvestRare (a shimmer of three
soft chimes, layered over Harvest for a mutated crop), Chop (a soft wooden thock), TreeFall (a creak,
a leafy whoosh and a soft thud), Craft (two quick wooden taps and a click), ResearchDone (a rising
two-note chime over a warm swell), and the notice roles: NoticeError (two soft low wooden ticks,
falling), NoticeReward (two soft chimes, rising a third) and NoticeBanner (three chimes rising over
a short warm swell, for the top banner).
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
PEAK = 0.5  # -6 dBFS
OUT = Path(__file__).resolve().parents[2] / "assets" / "sounds"


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(into, sound, at, gain=1.0):
    start = int(at * RATE)
    if len(into) < start + len(sound):
        into.extend([0.0] * (start + len(sound) - len(into)))
    for i, v in enumerate(sound):
        into[start + i] += v * gain
    return into


def envelope(n, attack, decay):
    """Soft linear attack then exponential decay (time constant `decay` seconds)."""
    out = []
    a = max(1, int(attack * RATE))
    for i in range(n):
        t = i / RATE
        rise = min(1.0, i / a)
        out.append(rise * math.exp(-t / decay))
    return out


def tone(freq, seconds, decay, attack=0.004, partials=((1, 1.0),), detune=0.0):
    """A struck tone: decaying sine partials (ratio, gain), each a little quicker the higher it is."""
    n = int(seconds * RATE)
    out = [0.0] * n
    for ratio, gain in partials:
        f = freq * ratio * (1 + detune * random.uniform(-1, 1))
        env = envelope(n, attack, decay / math.sqrt(ratio))
        phase = random.random() * math.tau
        for i in range(n):
            out[i] += gain * env[i] * math.sin(phase + math.tau * f * i / RATE)
    return out


def noise(seconds):
    return [random.uniform(-1, 1) for _ in range(int(seconds * RATE))]


def lowpass(samples, cutoff):
    a = 1 - math.exp(-math.tau * cutoff / RATE)
    y, out = 0.0, []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, low)]


def bandpass(samples, low, high):
    return lowpass(highpass(samples, low), high)


def shaped(samples, attack, decay):
    env = envelope(len(samples), attack, decay)
    return [s * e for s, e in zip(samples, env)]


def bell(freq, seconds, decay):
    # Soft celesta-like partials: warm, rounded, never metallic.
    return tone(freq, seconds, decay, 0.003, ((1, 1.0), (2, 0.28), (3, 0.08), (4.2, 0.03)), 0.0015)


def wood(freq, seconds=0.2, decay=0.035):
    body = tone(freq, seconds, decay, 0.0015, ((1, 1.0), (2.7, 0.35), (5.1, 0.08)))
    click = shaped(bandpass(noise(seconds), 1500, 6000), 0.0008, 0.006)
    return mix(body, click, 0, 0.25)


def finish(samples, tail=0.05):
    """Normalise to PEAK, fade the last `tail` seconds to silence and drop the DC offset."""
    mean = sum(samples) / len(samples)
    samples = [s - mean for s in samples]
    top = max(abs(s) for s in samples) or 1
    samples = [s * PEAK / top for s in samples]
    fade = int(tail * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    return samples + silence(0.02)


def grains(seconds, count, spread, low, high, length=(0.006, 0.022), fall=0.12):
    """A rustle: `count` tiny band-passed noise grains scattered over `spread` seconds, each a
    leaf or blade brushing past, quieter the later they come."""
    out = silence(seconds)
    for _ in range(count):
        at = random.uniform(0, spread)
        size = random.uniform(*length)
        centre = random.uniform(low, high)
        grain = shaped(bandpass(noise(size + 0.01), centre * 0.6, centre * 1.4), size * 0.3, size * 0.4)
        mix(out, grain, at, random.uniform(0.5, 1.0) * math.exp(-at / fall))
    return out


def harvest():
    """A plant pulled from the ground: leaves rustling as it is grasped, a green stem snapping,
    soil crumbling off the roots, and the leaves settling. No tones: it should sound like the
    garden, not a game."""
    out = silence(0.6)
    mix(out, grains(0.3, 26, 0.16, 1800, 6500), 0, 0.5)
    # The stem: a crisp, dry click with a short woody knock under it.
    mix(out, shaped(highpass(noise(0.02), 2500), 0.0003, 0.0025), 0.11, 0.55)
    mix(out, tone(1150, 0.06, 0.008, 0.0005, ((1, 1.0), (2.3, 0.4))), 0.11, 0.18)
    # Soil letting go: a soft low thump and a few crumbs pattering down.
    mix(out, shaped(lowpass(noise(0.14), 260), 0.004, 0.035), 0.12, 0.9)
    mix(out, grains(0.35, 14, 0.24, 300, 1200, (0.004, 0.012), 0.12), 0.15, 0.55)
    # The leaves swaying back after the pull.
    mix(out, grains(0.3, 12, 0.2, 2500, 7000, fall=0.1), 0.2, 0.22)
    return finish(out, 0.08)


def harvest_rare():
    out = silence(1.0)
    for at, freq in ((0.0, 1568), (0.075, 1976), (0.15, 2349)):
        mix(out, bell(freq, 0.8, 0.28), at, 0.5)
    return finish(out, 0.12)


def chop():
    out = silence(0.4)
    mix(out, wood(190, 0.3, 0.07), 0, 1.0)
    mix(out, shaped(lowpass(noise(0.25), 1800), 0.001, 0.045), 0, 0.35)
    mix(out, shaped(bandpass(noise(0.05), 3000, 8000), 0.0005, 0.004), 0, 0.18)
    return finish(out)


def tree_fall():
    out = silence(1.7)
    # A slow creak: a low buzzy tone wandering in pitch, rounded off by a low-pass.
    n = int(0.6 * RATE)
    creak, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 95 + 25 * math.sin(math.tau * 1.7 * t) + 30 * t
        phase += math.tau * f / RATE
        wave_ = sum(math.sin(k * phase) / k for k in (1, 2, 3, 4))
        swell = math.sin(math.pi * min(1, t / 0.6))
        creak.append(wave_ * swell)
    mix(out, lowpass(creak, 900), 0, 0.35)
    # The crown sweeping through the air, then landing.
    whoosh = lowpass(noise(0.7), 1200)
    whoosh = [s * math.sin(math.pi * i / len(whoosh)) ** 2 for i, s in enumerate(whoosh)]
    mix(out, whoosh, 0.4, 0.5)
    mix(out, tone(68, 0.5, 0.12, 0.004, ((1, 1.0), (1.5, 0.3))), 1.02, 0.9)
    mix(out, shaped(lowpass(noise(0.35), 700), 0.002, 0.08), 1.02, 0.5)
    mix(out, shaped(bandpass(noise(0.5), 2000, 6000), 0.01, 0.14), 1.05, 0.16)
    return finish(out, 0.15)


def craft():
    out = silence(0.5)
    mix(out, wood(620), 0, 0.9)
    mix(out, wood(760), 0.11, 0.8)
    mix(out, shaped(bandpass(noise(0.03), 2000, 7000), 0.0005, 0.005), 0.27, 0.3)
    return finish(out)


def research_done():
    out = silence(1.9)
    # The warm swell under it: a soft fifth that breathes in and fades.
    n = int(1.8 * RATE)
    pad = [0.0] * n
    for freq in (440, 659.25):
        for i in range(n):
            t = i / RATE
            pad[i] += math.sin(math.tau * freq * t) * min(1, t / 0.35) * math.exp(-t / 0.7)
    mix(out, pad, 0, 0.16)
    mix(out, bell(659.25, 1.2, 0.45), 0.02, 0.6)
    mix(out, bell(987.77, 1.4, 0.55), 0.2, 0.6)
    return finish(out, 0.2)


def notice_error():
    out = silence(0.3)
    mix(out, wood(300, 0.16, 0.03), 0, 0.8)
    mix(out, wood(236, 0.18, 0.035), 0.085, 0.7)
    return finish(lowpass(out, 3200))


def notice_reward():
    out = silence(0.7)
    mix(out, bell(1046.5, 0.5, 0.2), 0, 0.55)
    mix(out, bell(1318.5, 0.6, 0.24), 0.09, 0.55)
    return finish(out, 0.1)


def notice_banner():
    out = silence(1.5)
    n = int(1.3 * RATE)
    pad = [0.0] * n
    for freq in (392, 523.25):
        for i in range(n):
            t = i / RATE
            pad[i] += math.sin(math.tau * freq * t) * min(1, t / 0.25) * math.exp(-t / 0.5)
    mix(out, pad, 0, 0.14)
    for at, freq in ((0.0, 783.99), (0.11, 1046.5), (0.22, 1318.5)):
        mix(out, bell(freq, 1.1, 0.4), at, 0.5)
    return finish(out, 0.2)


ROLES = {
    "Harvest": harvest,
    "HarvestRare": harvest_rare,
    "Chop": chop,
    "TreeFall": tree_fall,
    "Craft": craft,
    "ResearchDone": research_done,
    "NoticeError": notice_error,
    "NoticeReward": notice_reward,
    "NoticeBanner": notice_banner,
}


def write(path, samples):
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for role, make in ROLES.items():
        random.seed(role)
        samples = make()
        path = OUT / f"Garden_{role}.wav"
        write(path, samples)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        print(f"{path.name}: {len(samples) / RATE:.2f} s, peak {max(abs(s) for s in samples):.2f}, rms {rms:.3f}")


if __name__ == "__main__":
    main()
