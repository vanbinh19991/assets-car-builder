#!/bin/bash
# Build project Xcode (.zip) ra .ipa chưa ký — chạy trên máy Mac của GitHub Actions.
# Đặt file này vào repo tại: .github/scripts/build_xcode.sh
# Cách dùng: bash build_xcode.sh <src.zip> <thư mục ra>
# Ra: <out>/app.ipa  (log đầy đủ ở <out>/build.log, không in ra log công khai của GitHub)
set -uo pipefail
ZIP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
LOG="$OUT/build.log"
WORK="$(mktemp -d)"
: > "$LOG"
# Chỉ ghi vào build.log (repo công khai -> không in tên project ra log GitHub)
say() { echo "== $*" >> "$LOG"; }
fail() { say "LỖI: $*"; echo "Build lỗi (chi tiết gửi riêng về web)"; exit 1; }

say "Giải nén mã nguồn"
mkdir -p "$WORK/src"
ditto -x -k "$ZIP" "$WORK/src" >> "$LOG" 2>&1 || unzip -q "$ZIP" -d "$WORK/src" >> "$LOG" 2>&1 || fail "Không giải nén được file .zip"
rm -rf "$WORK/src/__MACOSX"
cd "$WORK/src"

# Đường dẫn nông nhất khớp mẫu (bỏ qua Pods, build, bên trong .xcodeproj)
shallowest() {
  find . -name "$1" -not -path "*/Pods/*" -not -path "*.xcodeproj/*" -not -path "*/build/*" -not -path "*/DerivedData/*" -not -path "*/__MACOSX/*" 2>/dev/null \
    | awk -F/ '{print NF"\t"$0}' | sort -n | head -1 | cut -f2-
}

PROJ="$(shallowest '*.xcodeproj')"
[ -n "$PROJ" ] || fail "Không tìm thấy file .xcodeproj trong .zip"
PROJ_DIR="$(dirname "$PROJ")"
say "Project: $PROJ"

if [ -f "$PROJ_DIR/Podfile" ] && [ ! -d "$PROJ_DIR/Pods" ]; then
  say "Có Podfile — chạy pod install"
  (cd "$PROJ_DIR" && pod install >> "$LOG" 2>&1) || fail "pod install thất bại"
fi

WS="$(shallowest '*.xcworkspace')"
if [ -n "$WS" ]; then SRC=(-workspace "$WS"); say "Workspace: $WS"; else SRC=(-project "$PROJ"); fi

NAME="$(basename "$PROJ" .xcodeproj)"
xcodebuild "${SRC[@]}" -list -json > "$WORK/list.json" 2>> "$LOG" || true
SCHEME="$(python3 - "$WORK/list.json" "$NAME" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(""); sys.exit()
info = d.get("workspace") or d.get("project") or {}
schemes = [s for s in info.get("schemes", []) if not s.startswith("Pods")]
name = sys.argv[2]
print(name if name in schemes else (schemes[0] if schemes else ""))
PY
)"

BUILD_ARGS=(-configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" ONLY_ACTIVE_ARCH=NO)
if [ -n "$SCHEME" ]; then
  say "Scheme: $SCHEME"
  say "Đang build (xcodebuild)..."
  xcodebuild "${SRC[@]}" -scheme "$SCHEME" -destination 'generic/platform=iOS' -derivedDataPath "$WORK/dd" "${BUILD_ARGS[@]}" build >> "$LOG" 2>&1 \
    || fail "xcodebuild thất bại"
  PRODUCTS="$WORK/dd/Build/Products"
else
  [ -z "$WS" ] || fail "Workspace không có scheme dùng chung (Shared). Trong Xcode: Product → Scheme → Manage Schemes → tick Shared"
  TARGET="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); t=d.get('project',{}).get('targets',[]); print(t[0] if t else '')" "$WORK/list.json" 2>/dev/null)"
  [ -n "$TARGET" ] || fail "Không tìm thấy scheme hoặc target nào để build"
  say "Target: $TARGET"
  say "Đang build (xcodebuild)..."
  xcodebuild -project "$PROJ" -target "$TARGET" SYMROOT="$WORK/build" "${BUILD_ARGS[@]}" build >> "$LOG" 2>&1 \
    || fail "xcodebuild thất bại"
  PRODUCTS="$WORK/build"
fi

APP="$(find "$PRODUCTS" -maxdepth 2 -path "*-iphoneos/*.app" -type d | head -1)"
[ -n "$APP" ] || fail "Build xong nhưng không thấy file .app"
say "App: $(basename "$APP")"

# 1024.png nằm cùng chỗ với Info.plist -> chép vào gốc .app (bước Fix IPA sẽ tạo Assets.car từ ảnh này)
ICON="$(find . -name 1024.png -not -path "*/Pods/*" -not -path "*/build/*" -not -path "*/DerivedData/*" 2>/dev/null | while read -r p; do
  [ -f "$(dirname "$p")/Info.plist" ] && echo "$p"; done | head -1)"
if [ -n "$ICON" ]; then cp "$ICON" "$APP/1024.png"; say "Đã chép 1024.png vào app"; else say "Không thấy 1024.png cạnh Info.plist"; fi

say "Đóng gói .ipa"
mkdir -p "$WORK/pkg/Payload"
cp -R "$APP" "$WORK/pkg/Payload/"
(cd "$WORK/pkg" && zip -qry "$OUT/app.ipa" Payload) || fail "Không đóng gói được .ipa"
say "Xong: $(du -h "$OUT/app.ipa" | cut -f1)"
