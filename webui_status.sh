#!/system/bin/sh
MODDIR=${0%/*}
YJ_PREFIX="${YJ_PREFIX:-}"
P="$YJ_PREFIX"


_VER=""
if [ -f "$MODDIR/module.prop" ]; then
  _VER="$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1 | tr -d '\r ')"
fi
echo "VER=${_VER:-?}"

_ROOT="未知"
if [ -f "${P}/data/adb/ksud" ] || [ -d "${P}/data/adb/ksu" ]; then
  _ROOT="KernelSU"
elif [ -f "${P}/data/adb/apd" ] || [ -d "${P}/data/adb/apatch" ]; then
  _ROOT="APatch"
elif [ -d "${P}/data/adb/magisk" ]; then
  _ROOT="Magisk"
fi
echo "ROOT=$_ROOT"

if [ -d "${P}/data/adb/modules/teesim" ]; then echo "TEESIM=1"; else echo "TEESIM=0"; fi
if [ -d "${P}/data/adb/modules/zygisk_lsposed" ]; then echo "LSPOSED=1"; else echo "LSPOSED=0"; fi

_MT=0
for _p in "${P}/data/data/bin.mt.plus" "${P}/data/user/0/bin.mt.plus" \
          "${P}/data/data/bin.mt.plus.canary" "${P}/data/user/0/bin.mt.plus.canary"; do
  [ -d "$_p" ] && _MT=1
done
echo "MT=$_MT"


_keybox="none"
_kb="${P}/data/adb/teesim/keybox.xml"
if [ -f "$_kb" ]; then
  _sz="$(wc -c <"$_kb" 2>/dev/null | tr -d ' ')"
  if head -c 64 "$_kb" 2>/dev/null | grep -q '<' \
     && grep -qiE '<(Keybox|keys)' "$_kb" 2>/dev/null; then
    _keybox="installed:${_sz:-0}"
  else
    _keybox="installed-invalid:${_sz:-0}"
  fi
fi
echo "KEYBOX=$_keybox"

_mt2="none"
_pf=""
for _c in "${P}/data/user/0/bin.mt.plus/shared_prefs/bin.mt.plus_preferences.xml" \
          "${P}/data/data/bin.mt.plus/shared_prefs/bin.mt.plus_preferences.xml"; do
  [ -f "$_c" ] && { _pf="$_c"; break; }
done
if [ -n "$_pf" ]; then
  _cur="$(sed -n 's|.*<string name="mt2_path">\(.*\)</string>.*|\1|p' "$_pf" 2>/dev/null | head -n1)"
  [ -n "$_cur" ] && _mt2="path:$_cur"
fi
if [ "$_mt2" = "none" ] && [ -d "${P}/sdcard/Download/MT管理器" ]; then
  _mt2="dir-only:/sdcard/Download/MT管理器"
fi
echo "MT2=$_mt2"

echo "OK=1"

_sys=""
_base="${P}/sys/class/power_supply/battery"
_cc="$(cat "$_base/charge_full_design" 2>/dev/null | tr -d ' \r\n')"
_dc="$(cat "$_base/charge_full" 2>/dev/null | tr -d ' \r\n')"
case "$_cc" in
  ''|*[!0-9]*) _sys="unavailable" ;;
  *)
    if [ "$_cc" -gt 0 ] 2>/dev/null; then
      _pct=$(( _dc * 100 / _cc ))
      _sys="${_pct}%($(( _dc / 1000 ))mAh)"
    else
      _sys="unavailable"
    fi
    ;;
esac
echo "BATTERY=$_sys"

_sat="$(cat "${P}/data/adb/yijian_hide/state.d/saturation" 2>/dev/null | tr -d ' \r\n')"
[ -n "$_sat" ] || _sat="1.0"
echo "SATURATION=$_sat"

_conf="${P}/data/adb/yijian_hide/sys.conf"
_auto="none"
[ -f "$_conf" ] && _auto="$(sed -n 's/^battery_auto=//p' "$_conf" 2>/dev/null | tail -n1)"
[ -n "$_auto" ] || _auto="none"
echo "BATT_AUTO=$_auto"

_satauto="none"
[ -f "$_conf" ] && _satauto="$(sed -n 's/^saturation_auto=//p' "$_conf" 2>/dev/null | tail -n1)"
[ -n "$_satauto" ] || _satauto="none"
echo "SAT_AUTO=$_satauto"

_scan="${P}/data/adb/yijian_hide/state.d/scan_result"
_r="none"
[ -f "$_scan" ] && _r="$(cat "$_scan" 2>/dev/null)"
[ -n "$_r" ] || _r="none"
echo "SCAN=$_r"

_BL="${P}/sys/class/backlight/panel0-backlight"
_blcur=""; _blmax=""
[ -r "$_BL/brightness" ]     && _blcur="$(cat "$_BL/brightness" 2>/dev/null | tr -d ' \r\n')"
[ -r "$_BL/max_brightness" ] && _blmax="$(cat "$_BL/max_brightness" 2>/dev/null | tr -d ' \r\n')"
[ -n "$_blcur" ] || _blcur="unavailable"
[ -n "$_blmax" ] || _blmax="unavailable"
echo "BL_CUR=$_blcur"
echo "BL_MAX=$_blmax"

_blpid="${P}/data/adb/yijian_hide/brightness_lock.pid"
_bllock="off"
if [ -f "$_blpid" ]; then
  _bp="$(cat "$_blpid" 2>/dev/null | tr -d ' \r\n')"
  if [ -n "$_bp" ] && kill -0 "$_bp" 2>/dev/null; then
    _bllock="on:$_bp"
  fi
fi
echo "BL_LOCK=$_bllock"

_blauto="none"
[ -f "$_conf" ] && _blauto="$(sed -n 's/^brightness_auto=//p' "$_conf" 2>/dev/null | tail -n1)"
[ -n "$_blauto" ] || _blauto="none"
echo "BL_AUTO=$_blauto"

exit 0
