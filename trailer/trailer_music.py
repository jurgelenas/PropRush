#!/usr/bin/env python3
"""Trailer soundtrack in the radio's beeper voice: square and triangle tones, noise drums, the game's own cues.
Scored to the cuts: a motor intro, the arming chime on the title, the race start on the drop, the music dying at the
crash and the best-score fanfare on the end card.
Usage: trailer_music.py out.wav name=seconds ... (the scenes in order)."""

import array
import math
import random
import sys
import wave

RATE = 44100
BEAT = 60 / 140
# Seconds into the crash scene the quad hits the wall
IMPACT = 2.55
# Seconds into the menu scene of its key presses (trailer/trailer.lua)
MENU_KEYS = (0.6, 1.2, 1.8)

random.seed(7)


def hz(semis, base=880.0):
    return base * 2 ** (semis / 12)


class Track:
    def __init__(self, seconds):
        self.n = int(seconds * RATE) + 1
        self.s = array.array("f", [0.0]) * self.n

    def _span(self, t0, dur):
        a = max(0, int(t0 * RATE))
        return a, min(self.n, int((t0 + dur) * RATE))

    def tone(self, t0, f, dur, vol, duty=0.5, slide=0.0, attack=0.004, release=0.03, wave_="square"):
        """slide: Hz per second"""
        a, b = self._span(t0, dur)
        phase, s = 0.0, self.s
        for i in range(a, b):
            t = (i - a) / RATE
            fi = f + slide * t
            if fi < 20:
                break
            phase = (phase + fi / RATE) % 1.0
            if wave_ == "square":
                v = 1.0 if phase < duty else -1.0
            else:
                v = 4 * abs(phase - 0.5) - 1
            env = min(1.0, t / attack, (dur - t) / release)
            s[i] += v * vol * env

    def noise(self, t0, dur, vol, decay, bright=1.0):
        """decay: seconds to fall to 1/e; bright 0..1, less is a one-pole low-pass"""
        a, b = self._span(t0, dur)
        last, s = 0.0, self.s
        for i in range(a, b):
            t = (i - a) / RATE
            last += (random.uniform(-1, 1) - last) * bright
            s[i] += last * vol * math.exp(-t / decay) * min(1.0, (dur - t) / 0.005)

    def kick(self, t0, vol=0.9):
        a, b = self._span(t0, 0.22)
        phase, s = 0.0, self.s
        for i in range(a, b):
            t = (i - a) / RATE
            phase += (45 + 110 * math.exp(-t / 0.03)) / RATE
            s[i] += math.sin(2 * math.pi * phase) * vol * math.exp(-t / 0.07)

    def snare(self, t0, vol=0.45):
        self.noise(t0, 0.18, vol, 0.05, 0.7)
        self.tone(t0, 190, 0.06, vol * 0.4, wave_="tri", release=0.04)

    def hat(self, t0, vol=0.12):
        self.noise(t0, 0.05, vol, 0.012)

    def cymbal(self, t0, vol=0.3):
        self.noise(t0, 1.6, vol, 0.35)

    def cue(self, t0, notes, vol):
        """notes as the game's cues: (Hz, length ms, pause ms, slide Hz per ms)"""
        for f, d, p, slide in notes:
            self.tone(t0, f, d / 1000, vol, slide=slide * 1000, release=0.01)
            t0 += (d + p) / 1000
        return t0


ARMED = ((880, 60, 20, 0), (1109, 60, 20, 0), (1319, 100, 0, 0))
START = ((1760, 250, 0, 0),)
BEST = ((880, 70, 10, 0), (1109, 70, 10, 0), (1319, 70, 10, 0), (1760, 70, 60, 0), (1319, 70, 10, 0),
        (1760, 250, 0, 0))

# A, F#m, D, E: bass roots (A2 up) and the lead's eighths, semitones from A5 (None rests)
ROOTS = (0, -3, -7, -5)
LEAD = (
    (0, None, 7, 4, 12, None, 7, 4),
    (9, None, 4, 1, 9, None, 11, 12),
    (5, None, 9, 12, 9, 5, 4, 2),
    (7, None, 11, 14, 11, None, 7, None),
)
# Sixteenths over each chord in the second half
ARP = ((0, 4, 7, 12), (-3, 0, 4, 9), (-7, -3, 0, 5), (-5, -1, 2, 7))


def main():
    out = sys.argv[1]
    scenes = [(a.split("=")[0], float(a.split("=")[1])) for a in sys.argv[2:]]
    start, t = {}, 0.0
    for name, d in scenes:
        start[name] = t
        t += d
    length = t
    cuts = [start[name] for name, _ in scenes[1:]]

    music, sfx = Track(length), Track(length)
    title, drop = start["title"], start["racing"]
    impact = start["crash"] + IMPACT

    # Drift: the motor buzz spooling up as in flight (platform/sound), a low drone and a riser into the title
    frame, odd = 1 / 30, False
    for k in range(int(title / frame)):
        rpm = 0.45 + 0.3 * k * frame / title
        odd = not odd
        sfx.tone(k * frame, (300 + 600 * rpm) * (0.95 if odd else 1.05), frame, 0.07, attack=0.001, release=0.001)
    music.tone(0, 55, title, 0.25, wave_="tri", attack=1.5)
    a, b = music._span(title - 1.2, 1.2)
    for i in range(a, b):
        music.s[i] += random.uniform(-1, 1) * 0.18 * ((i - a) / (b - a)) ** 2
    for k in range(int(title / BEAT)):
        music.tone(k * BEAT, 1319, 0.03, 0.05, duty=0.25)

    # Title: the arming chime over a hit and a ringing A chord
    music.kick(title)
    music.cymbal(title, 0.35)
    sfx.cue(title, ARMED, 0.22)
    for f in (110, 220, 277.2, 329.6):
        music.tone(title, f, start["menu"] - title, 0.12, wave_="tri", release=1.2)

    # Menu: key clicks, a pulse counting into the drop, a snare roll over the last bar
    for k in MENU_KEYS:
        sfx.tone(start["menu"] + k, 2000, 0.012, 0.15, release=0.004)
    k = 1
    while drop - k * BEAT >= start["menu"]:
        music.kick(drop - k * BEAT, 0.7)
        music.tone(drop - k * BEAT, hz(0, 110), BEAT * 0.9, 0.18, wave_="tri")
        k += 1
    for k in range(16):
        music.snare(drop - (16 - k) * BEAT / 4, 0.08 + 0.3 * k / 16)

    # The groove from the race start to the crash; the arpeggio joins from the trainyard
    sfx.cue(drop, START, 0.22)
    arp_from = start["trainyard"]
    beat = 0
    while drop + beat * BEAT < impact:
        t0 = drop + beat * BEAT
        bar, b4 = divmod(beat, 4)
        chord = bar % 4
        music.kick(t0)
        if b4 % 2:
            music.snare(t0)
        music.hat(t0 + BEAT / 2)
        root = hz(ROOTS[chord], 110)
        music.tone(t0, root, BEAT / 2 * 0.9, 0.22, wave_="tri")
        music.tone(t0 + BEAT / 2, root * (2 if b4 % 2 else 1), BEAT / 2 * 0.9, 0.22, wave_="tri")
        for e in range(2):
            n = LEAD[chord][b4 * 2 + e]
            if n is not None:
                music.tone(t0 + e * BEAT / 2, hz(n), BEAT / 2 * 0.85, 0.06, duty=0.25)
        if t0 >= arp_from:
            for e in range(4):
                n = ARP[chord][e]
                music.tone(t0 + e * BEAT / 4, hz(n + 12), BEAT / 4 * 0.6, 0.03, duty=0.125)
        beat += 1
    for c in cuts:
        if drop < c < impact:
            music.cymbal(c, 0.22)

    # Crash: the music stops dead on the hit, the game's crash sound, then the static fading with the picture
    a, _ = music._span(impact, 0)
    for i in range(a, music.n):
        if i < start["end"] * RATE:
            music.s[i] *= max(0.0, 1 - (i - a) / (0.01 * RATE))
    sfx.tone(impact, 2000, 0.03, 0.3, slide=-60000)
    sfx.tone(impact, 760, 0.45, 0.12, slide=-2000, release=0.15)
    music.kick(impact, 1.0)
    fade = 2.0
    k = impact
    while k < impact + fade:
        loss = 1 - (k - impact) / fade
        if random.random() < loss:
            sfx.tone(k, 2000 + random.randint(0, 1600), 0.01, 0.08 * loss, release=0.003)
        k += 0.02
    a, b = sfx._span(impact, fade)
    for i in range(a, b):
        sfx.s[i] += random.uniform(-1, 1) * 0.1 * (1 - (i - a) / (b - a)) ** 2

    # End card: the best-score fanfare, then the chord to the end
    t0 = sfx.cue(start["end"] + 0.3, BEST, 0.22)
    music.kick(t0)
    music.cymbal(t0, 0.3)
    for f in (110, 220, 277.2, 329.6, 440):
        music.tone(t0, f, length - t0, 0.11, wave_="tri", release=length - t0)
    music.tone(t0, 880, length - t0, 0.03, duty=0.25, release=length - t0)

    # Squares softened by a one-pole low-pass, then the mix to -1 dBFS
    s, last = music.s, 0.0
    for i in range(music.n):
        last += (s[i] + sfx.s[i] - last) * 0.45
        s[i] = last
    peak = max(abs(v) for v in s) or 1.0
    k = 0.89 / peak
    pcm = array.array("h", (int(v * k * 32767) for v in s))
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
