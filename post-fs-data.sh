#!/system/bin/sh
MODDIR=${0%/*}
YJ_PREFIX="${YJ_PREFIX:-}"

resetprop ro.build.version.security_patch 2026-10-05
resetprop ro.bootimage.build.date 2026-10-05
resetprop ro.vendor.build.security_patch 2026-10-05

[ -f "$MODDIR/lib/common.sh" ]  || exit 0
. "$MODDIR/lib/common.sh" 2>/dev/null || exit 0
[ -f "$MODDIR/lib/stages.sh" ]  || exit 0
. "$MODDIR/lib/stages.sh" 2>/dev/null || exit 0

mkdir -p "$YJ_HOME" "$YJ_STATE_D" 2>/dev/null

yj_init

[ "$(yj_state_get phase1_done 0)" = "1" ] || exit 0

yj_hma_early >/dev/null 2>&1 || true

exit 0
