"""Synthesizes most of the game's sound roles (Shared/Sounds) as small WAV files in assets/sounds,
with the standard library only, so they rebuild exactly: `python tools/sounds/synth.py [Role ...]`
(no roles: all of them).

Two families. The world sounds (Chop, TreeFall) are material: wood is a struck tone with a filtered
noise click, leaves are band-passed noise scattered as tiny grains. The game cues sound like a Roblox
simulator: bright and bouncy, built from blips (a rounded square wave that scoops up into its pitch),
bubble pops (a sine sweeping in pitch), bell pings, quick major arpeggios and a scatter of sparkles,
all in C major or its fifth, G, so cues that overlap agree. Every sound has a soft attack, ends in
silence and peaks at PEAK; Sounds.luau's volumes balance how loud they feel.

Roles: Plant (a bubbly bloop over a soil pat), Harvest (a leafy tug, a stem snap and a bright pop),
HarvestRare (a quick twinkling run up, layered over Harvest for a mutated crop), Coin (the classic
two-note coin blip), Buy (a pop and a ding), Craft (a tap, a pop and a quick arpeggio), Step (two
blips up), LevelUp (an arpeggio up to a ringing chord with sparkles), ResearchDone (a bell arpeggio
over a swell), Chop (a soft wooden thock), TreeFall (a creak, a leafy whoosh and a soft thud), and
the notice roles: NoticeError (a low "nuh-uh", two blips falling), NoticeReward (a three-note bling)
and NoticeBanner (a five-note run over a chord swell, for the top banner).
"""
import math
import random
import struct
import sys
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


def fade_out(samples, seconds=0.04):
    """Ease the last `seconds` to silence (a half-cosine), so a tone that is still ringing when
    it ends does not stop dead: a cut at about -22 dB is heard as a click."""
    n = min(len(samples) // 2, int(seconds * RATE))
    for i in range(n):
        samples[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / n)
    return samples


def tone(freq, seconds, decay, attack=0.004, partials=((1, 1.0),), detune=0.0):
    """A struck tone: decaying sine partials (ratio, gain), each a little quicker the higher it
    is, eased out at the end (fade_out)."""
    n = int(seconds * RATE)
    out = [0.0] * n
    for ratio, gain in partials:
        f = freq * ratio * (1 + detune * random.uniform(-1, 1))
        env = envelope(n, attack, decay / math.sqrt(ratio))
        phase = random.random() * math.tau
        for i in range(n):
            out[i] += gain * env[i] * math.sin(phase + math.tau * f * i / RATE)
    return fade_out(out)


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


# Game-cue building blocks ------------------------------------------------------------------------

# Harmonic recipes (ratio, gain): a rounded square for the chiptune blip, kept gentle so it never
# buzzes, and a near-sine for bubbles.
SQUARE = ((1, 1.0), (3, 0.24), (5, 0.08), (7, 0.025))
BUBBLE = ((1, 1.0), (2, 0.12))


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


# MIDI numbers for the notes the cues use.
C4, E4, G4, C5, D5, E5, G5, B5 = 60, 64, 67, 72, 74, 76, 79, 83
C6, D6, E6, G6, A6, B6, C7, D7, E7, G7 = 84, 86, 88, 91, 93, 95, 96, 98, 100, 103


def sweep(f0, f1, seconds, decay, glide, attack=0.002, harmonics=SQUARE, vibrato=0.0):
    """A tone whose pitch glides from f0 to f1 (evenly in pitch) over `glide` seconds, then holds,
    with decaying `harmonics`; `vibrato` is its depth as a fraction of the pitch, at 6 Hz."""
    n = int(seconds * RATE)
    env = envelope(n, attack, decay)
    out, phase = [0.0] * n, 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** min(1.0, t / glide)
        f *= 1 + vibrato * min(1.0, t / 0.15) * math.sin(math.tau * 6 * t)
        phase += math.tau * f / RATE
        out[i] = env[i] * sum(g * math.sin(r * phase) for r, g in harmonics)
    return fade_out(out, 0.02)


def blip(note, seconds=0.2, decay=0.07, harmonics=SQUARE):
    """A game blip: scoops up a semitone into its note in 15 ms, which is what makes it bounce."""
    f = hz(note)
    return sweep(f * 0.944, f, seconds, decay, 0.015, 0.002, harmonics)


def ping(note, seconds=0.5, decay=0.16):
    """A bright bell on a note, for the shine over a blip."""
    return bell(hz(note), seconds, decay)


def pop(f0, f1, seconds=0.09, decay=0.03):
    """A bubble pop: a near-sine sweeping from f0 to f1 over most of its life."""
    return sweep(f0, f1, seconds, decay, seconds * 0.7, 0.001, BUBBLE)


def sparkles(seconds, count, notes, spread, fall=0.25):
    """Twinkles: short high bell pings on `notes`, scattered over `spread` seconds, fading out."""
    out = silence(seconds)
    for _ in range(count):
        at = random.uniform(0, spread)
        mix(out, bell(hz(random.choice(notes)), 0.25, 0.05), at, random.uniform(0.4, 1.0) * math.exp(-at / fall))
    return out


def chord(notes, seconds, decay, rise=0.01, vibrato=0.004):
    """Held blips together: a ringing chord with a gentle vibrato."""
    out = silence(seconds)
    for note in notes:
        f = hz(note)
        mix(out, sweep(f, f, seconds, decay, 0.01, rise, SQUARE, vibrato), 0, 1 / len(notes))
    return fade_out(out)


def swell(freqs, seconds, rise, decay):
    """A warm pad of sines that breathes in and fades, under a run of notes."""
    n = int(seconds * RATE)
    pad = [0.0] * n
    for f in freqs:
        for i in range(n):
            t = i / RATE
            pad[i] += math.sin(math.tau * f * t) * min(1, t / rise) * math.exp(-t / decay)
    return fade_out(pad)


def soil_pat(seconds=0.14):
    return shaped(lowpass(noise(seconds), 300), 0.003, 0.03)


# Roles --------------------------------------------------------------------------------------------


def plant():
    """A seed popped into the ground: a bubbly bloop dropping in pitch over a soft soil pat."""
    out = silence(0.32)
    mix(out, soil_pat(0.16), 0, 0.8)
    mix(out, pop(820, 300, 0.14, 0.05), 0.005, 0.7)
    return finish(out, 0.06)


def harvest():
    """A crop pulled up: a quick leafy tug and stem snap, then a bright bubble pop rising out of it
    with a little blip on top."""
    out = silence(0.45)
    mix(out, grains(0.15, 14, 0.07, 2000, 6500), 0, 0.35)
    mix(out, shaped(highpass(noise(0.02), 2500), 0.0003, 0.0025), 0.06, 0.4)
    mix(out, soil_pat(0.12), 0.06, 0.45)
    mix(out, pop(420, 1050, 0.11, 0.04), 0.07, 1.0)
    mix(out, blip(G6, 0.18, 0.045), 0.1, 0.22)
    return finish(out, 0.06)


def harvest_rare():
    """A mutated crop: a quick twinkling run up the C major pentatonic, and sparkles after it."""
    out = silence(1.0)
    for k, note in enumerate((C6, D6, E6, G6, A6, C7)):
        mix(out, ping(note, 0.45, 0.12), k * 0.035, 0.45)
        mix(out, blip(note, 0.12, 0.035), k * 0.035, 0.12)
    mix(out, sparkles(0.8, 10, (C7, D7, E7, G7), 0.5), 0.2, 0.3)
    return finish(out, 0.12)


def coin():
    """The classic coin: a short B5 jumping to a ringing E6."""
    out = silence(0.42)
    mix(out, blip(B5, 0.08, 0.05), 0, 0.6)
    mix(out, blip(E6, 0.36, 0.11), 0.065, 0.6)
    mix(out, ping(E7, 0.3, 0.07), 0.065, 0.18)
    return finish(out, 0.06)


def buy():
    """A purchase: a bubble pop up into a bright two-note ding."""
    out = silence(0.45)
    mix(out, pop(380, 900, 0.07, 0.025), 0, 0.7)
    mix(out, blip(C6, 0.12, 0.05), 0.06, 0.45)
    mix(out, blip(G6, 0.34, 0.1), 0.12, 0.45)
    mix(out, ping(G6, 0.34, 0.12), 0.12, 0.3)
    return finish(out, 0.06)


def craft():
    """Something made: a wooden tap, a pop and a quick arpeggio up to a ping."""
    out = silence(0.62)
    mix(out, wood(520, 0.15, 0.03), 0, 0.6)
    mix(out, pop(500, 1000, 0.06, 0.02), 0.05, 0.5)
    for k, note in enumerate((C6, E6, G6)):
        last = k == 2
        mix(out, blip(note, 0.4 if last else 0.16, 0.12 if last else 0.05), 0.09 + k * 0.05, 0.42)
    mix(out, ping(C7, 0.4, 0.12), 0.19, 0.25)
    return finish(out, 0.08)


def step():
    """An onboarding step done: two blips up a fourth, with a ping."""
    out = silence(0.45)
    mix(out, blip(G5, 0.12, 0.05), 0, 0.55)
    mix(out, blip(C6, 0.38, 0.11), 0.08, 0.55)
    mix(out, ping(C6, 0.38, 0.13), 0.08, 0.3)
    return finish(out, 0.06)


def level_up():
    """A new level: a bouncy arpeggio up to a ringing C major chord, and sparkles over it."""
    out = silence(1.7)
    for k, note in enumerate((C5, E5, G5)):
        mix(out, blip(note, 0.15, 0.06), k * 0.075, 0.5)
        mix(out, ping(note + 12, 0.3, 0.09), k * 0.075, 0.18)
    mix(out, chord((C6, E6, G6), 1.3, 0.45), 0.225, 0.85)
    mix(out, ping(C7, 1.0, 0.35), 0.225, 0.3)
    mix(out, sparkles(1.3, 16, (C7, D7, E7, G7), 0.8, 0.4), 0.25, 0.32)
    return finish(out, 0.25)


def research_done():
    """A project finished: a slower bell arpeggio up G major over a warm swell, then twinkles."""
    out = silence(1.9)
    mix(out, swell((hz(G4), hz(B5 - 12), hz(D5)), 1.7, 0.3, 0.6), 0, 0.12)
    for k, note in enumerate((G5, B5, D6, G6)):
        last = k == 3
        mix(out, ping(note, 1.1 if last else 0.6, 0.4 if last else 0.18), k * 0.1, 0.5)
        mix(out, blip(note, 0.16, 0.05), k * 0.1, 0.2)
    mix(out, sparkles(1.2, 12, (G6, B6, D7, G7), 0.7, 0.35), 0.35, 0.28)
    return finish(out, 0.2)


def notice_error():
    """A refusal: a low "nuh-uh", two short blips falling, the second sagging flat."""
    out = silence(0.36)
    mix(out, blip(E4, 0.1, 0.05), 0, 0.7)
    f = hz(C4)
    mix(out, sweep(f, f * 0.94, 0.2, 0.07, 0.15), 0.11, 0.7)
    return finish(lowpass(out, 2400), 0.06)


def notice_reward():
    """A reward, quest or rare notice: a three-note bling up C major."""
    out = silence(0.7)
    for k, note in enumerate((C6, E6, G6)):
        last = k == 2
        mix(out, blip(note, 0.5 if last else 0.14, 0.14 if last else 0.05), k * 0.055, 0.42)
        mix(out, ping(note, 0.5, 0.15), k * 0.055, 0.25)
    mix(out, sparkles(0.5, 5, (C7, E7, G7), 0.25, 0.2), 0.15, 0.2)
    return finish(out, 0.1)


def notice_banner():
    """The top banner: a five-note run up over a chord swell, with sparkles."""
    out = silence(1.5)
    mix(out, swell((hz(C4), hz(G4), hz(E5)), 1.3, 0.2, 0.45), 0, 0.12)
    for k, note in enumerate((C5, E5, G5, C6, E6)):
        last = k == 4
        mix(out, blip(note, 0.5 if last else 0.13, 0.15 if last else 0.05), k * 0.05, 0.4)
        mix(out, ping(note + 12, 0.9 if last else 0.4, 0.3 if last else 0.1), k * 0.05, 0.22)
    mix(out, sparkles(1.0, 10, (C7, E7, G7), 0.6, 0.3), 0.25, 0.25)
    return finish(out, 0.2)


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


ROLES = {
    "Plant": plant,
    "Harvest": harvest,
    "HarvestRare": harvest_rare,
    "Chop": chop,
    "TreeFall": tree_fall,
    "Coin": coin,
    "Buy": buy,
    "Craft": craft,
    "Step": step,
    "LevelUp": level_up,
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
    for role in sys.argv[1:] or list(ROLES):
        make = ROLES[role]
        random.seed(role)
        samples = make()
        path = OUT / f"Garden_{role}.wav"
        write(path, samples)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        print(f"{path.name}: {len(samples) / RATE:.2f} s, peak {max(abs(s) for s in samples):.2f}, rms {rms:.3f}")


if __name__ == "__main__":
    main()
