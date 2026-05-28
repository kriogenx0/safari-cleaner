#!/usr/bin/env python3
"""Creates icons by compositing the blue bookmark ribbon over the Safari app icon."""
import struct, zlib, subprocess, os, sys, tempfile
from pathlib import Path

SIZES = [48, 96, 128, 256]
OUT_DIR = Path(__file__).parent / "images"
SAFARI_ICON = Path("/Applications/Safari.app/Contents/Resources/AppIcon.icns")

# ── PNG reader ─────────────────────────────────────────────────────────────────

def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

def read_png_rgba(path):
    with open(path, 'rb') as f:
        data = f.read()
    pos = 8
    width = height = color_type = 0
    idat = bytearray()
    while pos < len(data):
        n = struct.unpack('>I', data[pos:pos+4])[0]
        tag = data[pos+4:pos+8]
        body = data[pos+8:pos+8+n]
        pos += 12 + n
        if tag == b'IHDR':
            width, height = struct.unpack('>II', body[:8])
            color_type = body[9]
        elif tag == b'IDAT':
            idat.extend(body)
        elif tag == b'IEND':
            break
    bpp = {2: 3, 6: 4}.get(color_type, 4)
    raw = zlib.decompress(bytes(idat))
    stride = 1 + width * bpp
    pixels = []
    prev = bytearray(width * bpp)
    for i in range(height):
        row = bytearray(raw[i*stride : i*stride+stride])
        ftype, row = row[0], bytearray(row[1:])
        if ftype == 1:
            for j in range(bpp, len(row)):
                row[j] = (row[j] + row[j-bpp]) & 0xFF
        elif ftype == 2:
            for j in range(len(row)):
                row[j] = (row[j] + prev[j]) & 0xFF
        elif ftype == 3:
            for j in range(len(row)):
                a = row[j-bpp] if j >= bpp else 0
                row[j] = (row[j] + (a + prev[j]) // 2) & 0xFF
        elif ftype == 4:
            for j in range(len(row)):
                a = row[j-bpp] if j >= bpp else 0
                b, c = prev[j], (prev[j-bpp] if j >= bpp else 0)
                row[j] = (row[j] + _paeth(a, b, c)) & 0xFF
        for j in range(0, len(row), bpp):
            pixels.append((row[j], row[j+1], row[j+2], row[j+3] if bpp == 4 else 255))
        prev = row
    return width, height, pixels

# ── PNG writer ─────────────────────────────────────────────────────────────────

def write_png_rgba(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixels[y*w+x])
    def chunk(tag, body):
        payload = tag + bytes(body)
        return struct.pack('>I', len(body)) + payload + struct.pack('>I', zlib.crc32(payload) & 0xFFFFFFFF)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n'
                + chunk(b'IHDR', ihdr)
                + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
                + chunk(b'IEND', b''))

# ── Compositing ────────────────────────────────────────────────────────────────

def over(base, overlay):
    br, bg, bb, ba = base
    or_, og, ob, oa = overlay
    ao, ab = oa / 255.0, ba / 255.0
    aout = ao + ab * (1 - ao)
    if aout == 0:
        return (0, 0, 0, 0)
    f = 1 - ao
    return (
        int((or_ * ao + br * ab * f) / aout),
        int((og * ao + bg * ab * f) / aout),
        int((ob * ao + bb * ab * f) / aout),
        int(aout * 255),
    )

# ── Blue bookmark ribbon ────────────────────────────────────────────────────────

def sample(fx, fy, size):
    left  = 0.536 * size
    right = 0.80 * size
    top   = 0.09 * size
    bot   = 0.475 * size
    w = right - left
    h = bot - top
    rx = fx - left
    ry = fy - top
    if rx < 0 or rx >= w or ry < 0 or ry >= h:
        return (0, 0, 0, 0)
    notch_h = h * 0.22
    if ry >= h - notch_h:
        t = (ry - (h - notch_h)) / notch_h
        if abs(rx - w / 2) <= t * (w / 2):
            return (0, 0, 0, 0)
    cr = w * 0.10
    if ry < cr:
        if rx < cr and ((rx - cr)**2 + (ry - cr)**2) > cr**2:
            return (0, 0, 0, 0)
        if rx > w - cr and ((rx - (w - cr))**2 + (ry - cr)**2) > cr**2:
            return (0, 0, 0, 0)
    return (220, 30, 30, 255)

def make_ribbon(size):
    N = 4
    pixels = []
    for y in range(size):
        for x in range(size):
            r = g = b = a = 0
            for dy in range(N):
                for dx in range(N):
                    c = sample(x + (dx + 0.5) / N, y + (dy + 0.5) / N, size)
                    r += c[0]; g += c[1]; b += c[2]; a += c[3]
            n = N * N
            pixels.append((r // n, g // n, b // n, a // n))
    return pixels

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    if not SAFARI_ICON.exists():
        sys.exit(f"Safari icon not found: {SAFARI_ICON}")

    OUT_DIR.mkdir(exist_ok=True)

    for size in SIZES:
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
            tmp = f.name
        try:
            subprocess.run([
                'sips', '-s', 'format', 'png',
                '--resampleHeightWidth', str(size), str(size),
                str(SAFARI_ICON), '--out', tmp,
            ], check=True, capture_output=True)
            _, _, base = read_png_rgba(tmp)
        finally:
            os.unlink(tmp)

        ribbon = make_ribbon(size)
        composited = [over(b, r) for b, r in zip(base, ribbon)]

        out = OUT_DIR / f"icon-{size}.png"
        write_png_rgba(str(out), size, size, composited)
        print(f"  {out}")

    print("Done.")

if __name__ == "__main__":
    main()
