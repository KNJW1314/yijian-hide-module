#!/system/bin/sh

MAX="${1:-}"
PIDF="${2:-/data/adb/yijian_hide/brightness_lock.pid}"
BL="/sys/class/backlight/panel0-backlight/brightness"

case "$MAX" in
  ''|*[!0-9]*|0)
    echo "webui_brightness: 上限参数无效 [$MAX]" >&2
    exit 1
    ;;
esac

[ -w "$BL" ] || { echo "webui_brightness: $BL 不可写" >&2; exit 1; }

mkdir -p "${PIDF%/*}" 2>/dev/null
echo $$ >"$PIDF" 2>/dev/null

trap 'rm -f "$PIDF" 2>/dev/null; exit 0' TERM INT

while true; do
  [ -f "$PIDF" ] || exit 0

  CUR="$(cat "$BL" 2>/dev/null | tr -d ' \r\n')"
  [ "$CUR" = "$MAX" ] || echo "$MAX" >"$BL" 2>/dev/null

  sleep 1
done
