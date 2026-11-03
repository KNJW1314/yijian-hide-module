#!/system/bin/sh
MODDIR=${0%/*}
YJ_PREFIX="${YJ_PREFIX:-}"

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/stages.sh"
. "$MODDIR/lib/runner.sh"
. "$MODDIR/lib/webui_ext.sh"
. "$MODDIR/lib/sys_ext.sh"
. "$MODDIR/lib/brightness_ext.sh"

_i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  _i=$((_i + 1))
  [ "$_i" -gt 90 ] && break
  sleep 1
done
sleep 12

yj_init
yj_autorun

yj_start_keybox_watch() {
  [ -f "$YJ_HOME/keybox_watch_off" ] && return 0
  [ -f "$MODDIR/webui_watch.sh" ] || return 0
  [ "$(yj_state_get keybox_deployed 0)" = "1" ] && return 0
  [ -d "$TEESIM_DIR" ] || return 0

  mkdir -p "$YJ_HOME" 2>/dev/null
  setsid sh "$MODDIR/webui_watch.sh" >>"$YJ_LOG" 2>&1 &
  yj_log "keybox watcher 已在后台启动"
  return 0
}

yj_start_keybox_watch

yj_sys_autorun

yj_bl_lock_autoresume

exit 0
