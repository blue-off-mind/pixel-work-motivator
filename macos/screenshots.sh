#!/bin/bash
# 生成英文 README 使用的全部截图；只在内存里注入设置，不读写用户配置。
set -euo pipefail
cd "$(dirname "$0")/.."

./macos/build.sh
BIN="build/上班激励器.app/Contents/MacOS/PixelWorkMotivator"
OUT="docs/screenshots/en"
SETTINGS='{"salary":8000,"payday":15,"language":"en"}'
mkdir -p "$OUT"

"$BIN" --snapshot "$OUT/working.png" --now 2026-11-03T15:05:39 --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/receipt.png" --now 2026-11-03T10:42:00 --expanded --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/lunch.png" --now 2026-11-03T12:30:00 --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/offwork.png" --now 2026-11-03T18:00:00 --celebrate --anim 0.7 --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/fishing.png" --now 2026-11-03T16:40:00 --fishing 25 --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/weekend.png" --now 2026-11-07T10:00:00 --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/small.png" --now 2026-11-03T15:05:39 --size small --settings "$SETTINGS"
"$BIN" --snapshot "$OUT/large.png" --now 2026-11-03T15:05:39 --size large --settings "$SETTINGS"
"$BIN" --menubar-snapshot "$OUT/menubar.png" --now 2026-11-03T15:05:39 --settings "$SETTINGS"
"$BIN" --settings-snapshot docs/screenshots/settings.png
"$BIN" --settings-snapshot "$OUT/settings.png" --settings '{"language":"en"}'

echo "✓ 英文截图已生成：$OUT"
