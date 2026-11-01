#!/usr/bin/env python3
"""Synthesizes Dreamsign's alarm sounds (original, royalty-free).

Each is 28 s (AlarmKit/notification sounds must stay under 30 s), mono 16-bit 44.1 kHz WAV,
and builds in intensity inside the file — useful if iOS plays custom alarm sounds once
rather than looping (see docs/DEVICE_TESTING.md).

    python3 scripts/generate_sounds.py
"""
import os
import wave
import numpy as np

RATE = 44_100
LENGTH = 28.0
OUT = os.path.join(os.path.dirname(__file__), "..", "Dreamsign", "Resources", "Sounds")
t_all = np.arange(int(RATE * LENGTH)) / RATE


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def envelope(n, attack, decay):
    t = np.arange(n) / RATE
    env = np.exp(-t / decay)
    a = max(int(attack * RATE), 1)
    env[:a] *= np.linspace(0, 1, a)
    return env


def place(buffer, signal, start):
    i = int(start * RATE)
    j = min(i + len(signal), len(buffer))
    if i < len(buffer):
        buffer[i:j] += signal[: j - i]


def bell(freq, dur=3.2):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    partials = [(1.0, 1.0, 2.6), (2.0, 0.42, 1.6), (2.76, 0.22, 1.0), (5.40, 0.08, 0.45), (8.93, 0.03, 0.25)]
    out = np.zeros(n)
    for ratio, amp, decay in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * envelope(n, 0.004, decay)
    return out


def marimba(freq, dur=1.4):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    body = np.sin(2 * np.pi * freq * t) * envelope(n, 0.002, 0.55)
    overtone = 0.35 * np.sin(2 * np.pi * freq * 3.93 * t) * envelope(n, 0.001, 0.09)
    knock = 0.15 * np.sin(2 * np.pi * freq * 9.2 * t) * envelope(n, 0.0005, 0.02)
    return body + overtone + knock


def beep(freq, dur):
    """Band-limited square-ish tone: bright and piercing without harsh aliasing."""
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    out = sum(np.sin(2 * np.pi * freq * k * t) / k for k in (1, 3, 5, 7))
    gate = np.ones(n)
    edge = int(0.006 * RATE)
    gate[:edge] = np.linspace(0, 1, edge)
    gate[-edge:] = np.linspace(1, 0, edge)
    return out * gate


def echo(signal, delay, gain, taps=4):
    out = signal.copy()
    d = int(delay * RATE)
    for k in range(1, taps + 1):
        out[d * k:] += signal[: len(signal) - d * k] * (gain ** k)
    return out


def ramp(start, end, curve=1.6):
    x = t_all / LENGTH
    return start + (end - start) * x ** curve


def normalize(signal, peak=0.89):
    return signal / np.max(np.abs(signal)) * peak


def fade_edges(signal, seconds=0.05):
    n = int(seconds * RATE)
    signal[:n] *= np.linspace(0, 1, n)
    signal[-n:] *= np.linspace(1, 0, n)
    return signal


def dawn():
    """Soft pentatonic bells over a quiet pad, rising from a whisper."""
    buf = np.zeros_like(t_all)
    scale = [69, 72, 74, 76, 79, 81, 84]          # A minor pentatonic, bright register
    pattern = [0, 2, 4, 3, 5, 4, 2, 1, 3, 5, 6, 4]
    step = 0.62
    for i in range(int(LENGTH / step)):
        note = scale[pattern[i % len(pattern)]]
        place(buf, bell(midi(note)) * (0.9 if i % 4 == 0 else 0.6), i * step)
    pad = sum(np.sin(2 * np.pi * midi(n) * t_all) for n in (57, 64, 69)) * 0.05
    pad *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.1 * t_all)
    mix = echo(buf, 0.31, 0.32) + pad
    return fade_edges(normalize(mix) * ramp(0.10, 1.0, 1.4))


def tide():
    """Warm marimba motif that keeps returning, steadily louder."""
    buf = np.zeros_like(t_all)
    motif = [(62, 0.0), (66, 0.18), (69, 0.36), (74, 0.54), (69, 0.9), (74, 1.08)]
    bar = 1.6
    for b in range(int(LENGTH / bar)):
        lift = 12 if (b // 4) % 2 else 0
        for note, offset in motif:
            place(buf, marimba(midi(note + lift)), b * bar + offset)
        place(buf, marimba(midi(50)) * 0.7, b * bar)
    return fade_edges(normalize(echo(buf, 0.2, 0.18, 2)) * ramp(0.35, 1.0, 1.2))


def beacon():
    """Insistent two-tone bursts and rising sweeps, near full scale within seconds."""
    buf = np.zeros_like(t_all)
    cycle = 1.5
    for c in range(int(LENGTH / cycle)):
        start = c * cycle
        for k in range(4):
            place(buf, beep(988 if k % 2 == 0 else 1319, 0.11), start + k * 0.14)
        if c % 2 == 1:
            n = int(0.5 * RATE)
            t = np.arange(n) / RATE
            sweep_freq = np.linspace(700, 1800, n)
            phase = 2 * np.pi * np.cumsum(sweep_freq) / RATE
            sweep = sum(np.sin(phase * k) / k for k in (1, 3, 5)) * np.hanning(n) ** 0.3
            place(buf, sweep * 0.8, start + 0.8)
    level = np.clip(0.55 + t_all / 6.0, 0, 1.0)
    return fade_edges(normalize(buf, 0.94) * level)


def write(name, signal):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(signal, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


if __name__ == "__main__":
    write("Dawn.wav", dawn())
    write("Tide.wav", tide())
    write("Beacon.wav", beacon())
    print("wrote", os.path.abspath(OUT))
