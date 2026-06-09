#!/usr/bin/env python3
"""
make_icon.py — Extract Safari's app icon, apply a red hue shift, write AppIcon.appiconset.
Usage: python3 make_icon.py
"""

import subprocess, os, shutil, sys

ICONSET = "SafariCleaner/Safari Cleaner/Assets.xcassets/AppIcon.appiconset"
SAFARI  = "/Applications/Safari.app"
SIZES   = [16, 32, 64, 128, 256, 512, 1024]

def run(cmd):
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.decode())
        sys.exit(1)

# 1. Extract the highest-res icon from Safari's icns
icns = os.path.join(SAFARI, "Contents/Resources/AppIcon.icns")
if not os.path.exists(icns):
    sys.exit(f"Safari icon not found at {icns}")

tmp = "/tmp/safari_icon_extract"
shutil.rmtree(tmp, ignore_errors=True)
os.makedirs(tmp)
run(["iconutil", "-c", "iconset", icns, "-o", f"{tmp}/safari.iconset"])

# Pick largest available source
src = None
for size in [1024, 512, 256, 128]:
    for suffix in [f"icon_{size}x{size}@2x.png", f"icon_{size}x{size}.png"]:
        candidate = f"{tmp}/safari.iconset/{suffix}"
        if os.path.exists(candidate):
            src = candidate; break
    if src:
        break
if not src:
    sys.exit("Could not find a suitable source icon in Safari's icns")

print(f"Source: {src}")

# 2. Apply red hue rotation using sips (built-in macOS tool doesn't do hue)
#    Use Core Image via a small Swift one-liner instead.
# 2. Apply red hue rotation via a temp Swift script
shifted = "/tmp/safari_red.png"
swift_script = "/tmp/hue_shift.swift"
with open(swift_script, "w") as f:
    f.write(f"""
import AppKit
import CoreImage

let url = URL(fileURLWithPath: "{src}")
guard let img = CIImage(contentsOf: url) else {{ fatalError("Could not load image") }}

let hue = CIFilter(name: "CIHueAdjust")!
hue.setValue(img, forKey: kCIInputImageKey)
hue.setValue(Float(3.0), forKey: "inputAngle")
let out = hue.outputImage!

let ctx = CIContext()
let cgImg = ctx.createCGImage(out, from: out.extent)!
let bmp = NSBitmapImageRep(cgImage: cgImg)
let data = bmp.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "{shifted}"))
""")
run(["swift", swift_script])
print(f"Hue-shifted icon saved to {shifted}")

# 3. Resize into all required sizes and write Contents.json
os.makedirs(ICONSET, exist_ok=True)

images = []
for size in SIZES:
    for scale in ([1, 2] if size <= 512 else [1]):
        pixels = size * scale
        scale_str = f"{scale}x"
        filename = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        out = os.path.join(ICONSET, filename)
        run(["sips", "-z", str(pixels), str(pixels), shifted, "--out", out])
        images.append({
            "size": f"{size}x{size}",
            "scale": scale_str,
            "filename": filename,
            "idiom": "mac",
        })
        print(f"  {filename}")

import json
contents = {
    "images": [
        {"idiom": e["idiom"], "scale": e["scale"], "size": e["size"], "filename": e["filename"]}
        for e in images
    ],
    "info": {"author": "xcode", "version": 1}
}
with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print(f"\nDone. Icon written to {ICONSET}")
print("Rebuild the app in Xcode to pick up the new icon.")
