#!/usr/bin/env python3
"""Builds a README gallery for a folder of showcase screenshots named <device>--<screen>.png.

Near-blank captures (an inactive display) are dropped so the gallery only shows real screens.

    python3 scripts/make_gallery.py <shots-dir>
"""
import os
import struct
import sys


def mostly_blank(path):
    """Cheap check without Pillow: a dark, featureless PNG compresses extremely well."""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(24)
    width, height = struct.unpack(">II", head[16:24])
    return size < width * height * 0.004


shots = sys.argv[1]
files = sorted(f for f in os.listdir(shots) if f.endswith(".png"))
for f in list(files):
    if mostly_blank(os.path.join(shots, f)):
        os.remove(os.path.join(shots, f))
        files.remove(f)

devices, screens = [], []
for f in files:
    device, screen = f[:-4].split("--", 1)
    if device not in devices:
        devices.append(device)
    if screen not in screens:
        screens.append(screen)

lines = ["# Dreamsign screenshots", "", "Captured by CI with Xcode 27.1 (iPhone Duo cover + inner displays, and iPhone 17).", ""]
for screen in screens:
    lines += [f"## {screen}", "", "| " + " | ".join(devices) + " |", "|" + "---|" * len(devices)]
    cells = [f'<img src="{d}--{screen}.png" width="260">' if f"{d}--{screen}.png" in files else "—" for d in devices]
    lines += ["| " + " | ".join(cells) + " |", ""]
open(os.path.join(shots, "README.md"), "w").write("\n".join(lines))
print(f"gallery: {len(screens)} screens x {len(devices)} devices, {len(files)} images")
