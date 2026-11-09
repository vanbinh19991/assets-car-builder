# Tạo Assets.car + 11 PNG icon từ 1024.png — lấy từ phần PY_BUILD_ICONS của 2new2.sh.
# Đặt file này vào repo tại: .github/scripts/build_icons.py
# Đầu vào: <job_dir>/1024.png, <job_dir>/params.json {"family": [1,2], "min_os": "15.0"}
# Đầu ra:  <out>/compiled/* (Assets.car + PNG), <out>/asset-info.plist
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

job, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
source = job / "1024.png"
params = json.loads((job / "params.json").read_text(encoding="utf-8"))
family = params.get("family") or [1]
min_os = str(params.get("min_os") or "15.0")

def sips_props(path):
    info = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)], text=True)
    return dict(line.strip().split(": ", 1) for line in info.splitlines() if ": " in line)

properties = sips_props(source)
if properties.get("pixelWidth") != "1024" or properties.get("pixelHeight") != "1024":
    raise SystemExit("1024.png phải có kích thước 1024 x 1024 pixel.")
if properties.get("hasAlpha") != "no":
    # Apple không nhận icon có alpha -> tự đặt icon lên nền trắng và bỏ kênh alpha
    print("1024.png có alpha: tự xoá alpha (nền trắng)...", flush=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "pillow"], check=False)
    from PIL import Image
    img = Image.open(source).convert("RGBA")
    flat = Image.new("RGB", img.size, (255, 255, 255))
    flat.paste(img, mask=img.split()[3])
    fixed = job / "1024_noalpha.png"
    flat.save(fixed, "PNG")
    source = fixed
    if sips_props(source).get("hasAlpha") != "no":
        raise SystemExit("Không xoá được alpha của 1024.png.")
    print("Đã xoá alpha.", flush=True)

stage = Path(tempfile.mkdtemp(prefix="appicons-"))
catalog = stage / "Assets.xcassets"
iconset = catalog / "AppIcon.appiconset"
compiled = out / "compiled"
iconset.mkdir(parents=True)
compiled.mkdir(parents=True, exist_ok=True)
meta = {"info": {"version": 1, "author": "xcode"}}
(catalog / "Contents.json").write_text(json.dumps(meta), encoding="utf-8")
slots = [("ios-marketing", 1024, 1)]
if 1 in family:
    slots += [("iphone", size, scale) for size in (20, 29, 40, 60) for scale in (2, 3)]
if 2 in family:
    slots += [("ipad", size, scale) for size in (20, 29, 40, 76) for scale in (1, 2)]
    slots.append(("ipad", 83.5, 2))
images = []
for idiom, size, scale in slots:
    pixels = int(size * scale)
    filename = "Icon-{}-{}-{}x.png".format(idiom, size, scale)
    destination = iconset / filename
    if pixels == 1024:
        shutil.copy2(source, destination)
    else:
        subprocess.run(["sips", "-z", str(pixels), str(pixels), str(source), "--out", str(destination)], check=True)
    images.append({"idiom": idiom, "size": "{0}x{0}".format(size), "scale": str(scale) + "x", "filename": filename})
(iconset / "Contents.json").write_text(json.dumps(dict(meta, images=images), indent=2), encoding="utf-8")
partial = out / "asset-info.plist"
command = [
    "xcrun", "actool", "--compile", str(compiled), "--platform", "iphoneos",
    "--minimum-deployment-target", min_os,
    "--app-icon", "AppIcon", "--output-partial-info-plist", str(partial),
]
for device in family:
    command += ["--target-device", {1: "iphone", 2: "ipad"}[device]]
command.append(str(catalog))
subprocess.run(command, check=True)
car = compiled / "Assets.car"
if not car.is_file() or car.stat().st_size == 0:
    raise SystemExit("actool không tạo Assets.car.")
asset_info = plistlib.loads(partial.read_bytes())
if not any(key in asset_info for key in ("CFBundleIcons", "CFBundleIcons~ipad")):
    raise SystemExit("actool không tạo metadata icon hợp lệ.")

reference_icons = [('AppIcon1024x1024@1x.png', 1024, 1024), ('AppIcon20x20@2x.png', 40, 40), ('AppIcon20x20@3x.png', 60, 60), ('AppIcon29x29@2x.png', 58, 58), ('AppIcon29x29@3x.png', 87, 87), ('AppIcon40x40@2x.png', 80, 80), ('AppIcon40x40@3x.png', 120, 120), ('AppIcon60x60@2x.png', 120, 120), ('AppIcon60x60@3x.png', 180, 180), ('AppIcon76x76@2x.png', 152, 152), ('AppIcon83.5x83.5@2x.png', 167, 167)]
for filename, width, height in reference_icons:
    destination = compiled / filename
    if (width, height) == (1024, 1024):
        shutil.copy2(source, destination)
    else:
        subprocess.run(["sips", "-z", str(height), str(width), str(source), "--out", str(destination)], check=True)
    if not destination.is_file() or destination.stat().st_size == 0:
        raise SystemExit("Không tạo được ảnh: " + filename)
print("OK:", sorted(p.name for p in compiled.iterdir()))
