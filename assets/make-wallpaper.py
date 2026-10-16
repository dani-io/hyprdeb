#!/usr/bin/env python3
# hyprdeb: generate the default wallpaper (a plain vertical gradient, no artwork).
# Standard library only; output is byte-for-byte reproducible.
#   python3 assets/make-wallpaper.py assets/wallpaper.png
import struct
import sys
import zlib

# The first argument is the output path. An option-looking argument (e.g. --help) used to be taken as a file name and
# wrote a PNG called "--help"; refuse it instead.
if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1].startswith("-")):
    sys.exit("usage: make-wallpaper.py [OUTPUT.png]   (default wallpaper.png; the path must not start with '-')")

W, H = 1920, 1080
TOP = (0x56, 0x64, 0x8a)      # slate blue
BOTTOM = (0x1c, 0x22, 0x32)   # dark navy (not near-black: a darker gradient read as plain black)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


rows = bytearray()
for y in range(H):
    t = y / (H - 1)
    px = bytes(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    rows += b"\x00" + px * W   # filter type 0, then RGB pixels

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
       + chunk(b"IEND", b""))

with open(sys.argv[1] if len(sys.argv) > 1 else "wallpaper.png", "wb") as f:
    f.write(png)
