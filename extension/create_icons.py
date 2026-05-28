#!/usr/bin/env python3
"""Generate bookmark ribbon PNG icons for Safari Swipe."""
import struct, zlib, os

def write_png(path, size, pixel_fn):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(pixel_fn(x, y, size))

    def chunk(tag, data):
        payload = tag + bytes(data)
        return struct.pack('>I', len(data)) + payload + struct.pack('>I', zlib.crc32(payload) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)

def sample(fx, fy, size):
    left  = 0.22 * size
    right = 0.78 * size
    top   = 0.10 * size
    bot   = 0.92 * size
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
    return (0, 122, 255, 255)

def pixel(x, y, size):
    N = 4
    r = g = b = a = 0
    for dy in range(N):
        for dx in range(N):
            c = sample(x + (dx + 0.5) / N, y + (dy + 0.5) / N, size)
            r += c[0]; g += c[1]; b += c[2]; a += c[3]
    n = N * N
    return bytes([r // n, g // n, b // n, a // n])

os.makedirs('images', exist_ok=True)
for s in [48, 96, 128, 256]:
    path = f'images/icon-{s}.png'
    write_png(path, s, pixel)
    print(f'  {path}')
print('Done.')
