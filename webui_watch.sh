#!/system/bin/sh
MODDIR="${0%/*}"
YJ_PREFIX="${YJ_PREFIX:-}"

. "$MODDIR/lib/common.sh" 2>/dev/null
. "$MODDIR/lib/webui_ext.sh" 2>/dev/null

yj_init 2>/dev/null

[ -f "$YJ_HOME/keybox_watch_off" ] && exit 0
[ -d "$TEESIM_DIR" ] || exit 0
[ "$(yj_state_get keybox_deployed 0)" = "1" ] && exit 0

_round=0
while [ "$_round" -lt 180 ]; do
  _round=$((_round + 1))
  [ -f "$YJ_HOME/keybox_watch_off" ] && {
    yj_log "keybox watcher: 收到停止标记，退出"
    exit 0
  }

  if _c="$(yj_keybox_find_candidate 2>/dev/null)"; then
    yj_log "keybox watcher: 发现候选 $_c"
    if yj_keybox_deploy "$_c" 2>/dev/null; then
      yj_log "keybox watcher: 自动部署成功"
      exit 0
    fi
  fi
  sleep 10
done

yj_log "keybox watcher: 30 分钟内未发现下载，退出"
exit 0
