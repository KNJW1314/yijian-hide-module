#!/system/bin/sh

YJ_BL_BASE="${YJ_PREFIX}/sys/class/backlight/panel0-backlight"
YJ_BL_PID="$YJ_HOME/brightness_lock.pid"

yj_bl_exists() {
  [ -r "$YJ_BL_BASE/brightness" ] && [ -r "$YJ_BL_BASE/max_brightness" ]
}

yj_bl_cur() { cat "$YJ_BL_BASE/brightness" 2>/dev/null | tr -d ' \r\n'; }
yj_bl_max() { cat "$YJ_BL_BASE/max_brightness" 2>/dev/null | tr -d ' \r\n'; }

yj_bl_show_current() {
  yj_bl_exists || { yj_err "  ✗ 读不到背光节点：$YJ_BL_BASE"; return 1; }
  _cur="$(yj_bl_cur)"
  _max="$(yj_bl_max)"

  yj_say "  → 当前亮度"
  yj_say "    节点值：$_cur"
  yj_say "    硬件上限：$_max"

  case "$_cur" in ''|*[!0-9]*) : ;; *)
    case "$_max" in ''|*[!0-9]*|0) : ;; *)
      yj_say "    相当于上限的：$(( _cur * 100 / _max ))%"
      ;;
    esac
    ;;
  esac

  _sb="$(settings get system screen_brightness 2>/dev/null | tr -d ' \r\n')"
  [ -n "$_sb" ] && case "$_sb" in
    *[!0-9]*) : ;;
    *) yj_say "    系统亮度值：$_sb / 255" ;;
  esac

  yj_state_set bl_cur "$_cur"
  return 0
}

yj_bl_show_max() {
  yj_bl_exists || { yj_err "  ✗ 读不到背光节点：$YJ_BL_BASE"; return 1; }
  _max="$(yj_bl_max)"
  yj_say "  → 亮度上限"
  yj_say "    max_brightness：$_max"
  yj_state_set bl_max "$_max"
  return 0
}

yj_bl_unlock() {
  yj_bl_exists || { yj_err "  ✗ 读不到背光节点：$YJ_BL_BASE"; return 1; }

  _max="$(yj_bl_max)"
  case "$_max" in
    ''|*[!0-9]*|0) yj_err "  ✗ max_brightness 取值异常：[$_max]"; return 1 ;;
  esac

  _old="$(yj_bl_cur)"
  yj_say "  → 解锁最大亮度"
  yj_say "    上限 $_max（当前 $_old）"

  echo "$_max" >"$YJ_BL_BASE/brightness" 2>/dev/null || {
    yj_err "  ✗ 写入失败（节点可能只读或被 SELinux 限制）"
    return 1
  }

  sleep 1
  _new="$(yj_bl_cur)"
  [ "$_new" = "$_max" ] || { yj_err "  ✗ 回读不一致（期望 $_max，实际 $_new）"; return 1; }

  yj_say "  ✓ 已设为 $_max"
  yj_state_set bl_cur "$_new"
  return 0
}

yj_bl_lock_start() {
  yj_bl_exists || { yj_err "  ✗ 读不到背光节点"; return 1; }

  if yj_bl_lock_running; then
    yj_say "  ℹ 已在运行（pid $(cat "$YJ_BL_PID" 2>/dev/null)）"
    return 0
  fi

  _max="$(yj_bl_max)"
  case "$_max" in
    ''|*[!0-9]*|0) yj_err "  ✗ 上限取值异常：[$_max]"; return 1 ;;
  esac

  if command -v settings >/dev/null 2>&1; then
    settings put system screen_brightness_mode 0 2>/dev/null
    [ "$(settings get system screen_brightness_mode 2>/dev/null | tr -d ' \r\n')" = "0" ] && \
      yj_say "    ✓ 已关闭自动亮度"
  fi

  rm -f "$YJ_BL_PID" 2>/dev/null

  if command -v setsid >/dev/null 2>&1; then
    setsid sh "${MODDIR:-/data/adb/modules/yijian_hide}/webui_brightness.sh" "$_max" "$YJ_BL_PID" >/dev/null 2>&1 &
  else
    sh "${MODDIR:-/data/adb/modules/yijian_hide}/webui_brightness.sh" "$_max" "$YJ_BL_PID" >/dev/null 2>&1 &
  fi

  _i=0
  while [ "$_i" -lt 6 ]; do
    [ -f "$YJ_BL_PID" ] && break
    sleep 1
    _i=$((_i + 1))
  done

  _pid="$(cat "$YJ_BL_PID" 2>/dev/null | tr -d ' \r\n')"
  if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
    yj_say "  ✓ 已启动（pid $_pid，锁定 $_max）"
    yj_say "    ℹ 解除：sh action.sh brightness-lock-off"
    yj_state_set bl_lock 1
    return 0
  fi

  yj_err "  ✗ 后台进程没能启动（pid=[$_pid]），详见 $YJ_LOG"
  rm -f "$YJ_BL_PID" 2>/dev/null
  return 1
}

yj_bl_lock_running() {
  [ -f "$YJ_BL_PID" ] || return 1
  _p="$(cat "$YJ_BL_PID" 2>/dev/null | tr -d ' \r\n')"
  [ -n "$_p" ] || return 1
  kill -0 "$_p" 2>/dev/null || return 1

  if [ -r "/proc/$_p/cmdline" ]; then
    case "$(tr '\0' ' ' <"/proc/$_p/cmdline" 2>/dev/null)" in
      *webui_brightness.sh*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

yj_bl_lock_stop() {
  if [ ! -f "$YJ_BL_PID" ]; then
    yj_say "  ℹ 当前没有在运行"
    yj_state_set bl_lock 0
    return 0
  fi

  _p="$(cat "$YJ_BL_PID" 2>/dev/null | tr -d ' \r\n')"
  if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    kill "$_p" 2>/dev/null
    sleep 1
    kill -0 "$_p" 2>/dev/null && { kill -9 "$_p" 2>/dev/null; sleep 1; }
    if kill -0 "$_p" 2>/dev/null; then
      yj_err "  ✗ 进程 $_p 仍未结束，请重启设备"
      return 1
    fi
    yj_say "  ✓ 已停止（pid $_p）"
  else
    yj_say "  ℹ pid 已不存在（$_p），清理标记"
  fi

  rm -f "$YJ_BL_PID" 2>/dev/null
  yj_state_set bl_lock 0

  if yj_bl_exists; then
    _max="$(yj_bl_max)"
    case "$_max" in ''|*[!0-9]*|0) : ;; *)
      echo "$(( _max * 40 / 100 ))" > "$YJ_BL_BASE/brightness" 2>/dev/null && \
        yj_say "    ℹ 已降到 40%"
      ;;
    esac
  fi
  return 0
}

yj_bl_lock_status() {
  if yj_bl_lock_running; then
    printf 'on:%s' "$(cat "$YJ_BL_PID" 2>/dev/null | tr -d ' \r\n')"
  else
    [ "$(yj_state_get bl_lock 0)" = "1" ] && yj_state_set bl_lock 0
    printf 'off'
  fi
  return 0
}

yj_bl_lock_autoresume() {
  [ "$(yj_sys_conf_get brightness_auto none)" = "on" ] || return 0
  yj_bl_lock_running && return 0
  yj_log "bl_lock_autoresume: 开机恢复持续解锁"
  yj_bl_lock_start >>"$YJ_LOG" 2>&1
  return 0
}
