#!/system/bin/sh

YJ_SYS_CONF="$YJ_HOME/sys.conf"

yj_sys_conf_get() {
  _k="$1"; _d="${2:-}"
  [ -f "$YJ_SYS_CONF" ] || { printf '%s' "$_d"; return 0; }
  _v="$(sed -n "s/^${_k}=//p" "$YJ_SYS_CONF" 2>/dev/null | tail -n1)"
  if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "$_d"; fi
}

yj_sys_conf_set() {
  _k="$1"; _v="$2"
  mkdir -p "$YJ_HOME" 2>/dev/null
  [ -f "$YJ_SYS_CONF" ] || : >"$YJ_SYS_CONF"
  if grep -q "^${_k}=" "$YJ_SYS_CONF" 2>/dev/null; then
    _tmp="$YJ_SYS_CONF.tmp.$$"
    sed "s|^${_k}=.*|${_k}=${_v}|" "$YJ_SYS_CONF" >"$_tmp" 2>/dev/null
    mv -f "$_tmp" "$YJ_SYS_CONF" 2>/dev/null
  else
    printf '%s=%s\n' "$_k" "$_v" >>"$YJ_SYS_CONF" 2>/dev/null
  fi
  return 0
}

yj_battery_life() {
  _base="${YJ_PREFIX}/sys/class/power_supply/battery"

  yj_say "  → 电池寿命"

  for _n in charge_full_design charge_full cycle_count; do
    if [ ! -r "$_base/$_n" ]; then
      yj_err "    ✗ 读不到 $_base/$_n"
      yj_err "    本机可能不暴露该节点，无法查询电池寿命"
      return 1
    fi
  done

  _cc="$(cat "$_base/charge_full_design" 2>/dev/null | tr -d ' \r\n')"
  _dc="$(cat "$_base/charge_full" 2>/dev/null | tr -d ' \r\n')"
  _xh="$(cat "$_base/cycle_count" 2>/dev/null | tr -d ' \r\n')"

  case "$_cc" in ''|*[!0-9]*) yj_err "    ✗ charge_full_design 非数字：[$_cc]"; return 1 ;; esac
  case "$_dc" in ''|*[!0-9]*) yj_err "    ✗ charge_full 非数字：[$_dc]"; return 1 ;; esac
  [ "$_cc" -gt 0 ] 2>/dev/null || { yj_err "    ✗ 设计容量为 0，无法计算"; return 1; }

  _design=$((_cc / 1000))
  _now=$((_dc / 1000))
  _pct=$(( _dc * 100 / _cc ))

  yj_say "    ────────────────────────"
  yj_say "    出厂设计容量：${_design} mAh"
  yj_say "    当前电池容量：${_now} mAh"
  yj_say "    电池循环次数：${_xh} 次"
  yj_say "    剩余容量百分比：${_pct}%"
  yj_say "    ────────────────────────"

  if [ "$_pct" -lt 80 ] 2>/dev/null; then
    yj_warn "    健康度低于 80%，电池衰减较明显"
  fi

  yj_state_set battery_pct "$_pct"
  return 0
}

yj_battery_status() {
  _base="${YJ_PREFIX}/sys/class/power_supply/battery"
  _cc="$(cat "$_base/charge_full_design" 2>/dev/null | tr -d ' \r\n')"
  _dc="$(cat "$_base/charge_full" 2>/dev/null | tr -d ' \r\n')"
  case "$_cc" in ''|*[!0-9]*) printf 'unavailable'; return 1 ;; esac
  [ "$_cc" -gt 0 ] 2>/dev/null || { printf 'unavailable'; return 1; }
  _pct=$(( _dc * 100 / _cc ))
  _now=$(( _dc / 1000 ))
  _des=$(( _cc / 1000 ))
  printf '%d:%d/%d' "$_pct" "$_now" "$_des"
  return 0
}

yj_open_google_settings() {
  _comp="com.google.android.gms/com.google.android.gms.app.settings.GoogleSettingsIALink"

  yj_say "  → 打开隐藏 Google 设置"

  if ! command -v am >/dev/null 2>&1; then
    yj_err "    ✗ 没有 am 命令"
    return 1
  fi

  if command -v dumpsys >/dev/null 2>&1; then
    if ! dumpsys package com.google.android.gms 2>/dev/null | grep -q 'GoogleSettingsIALink'; then
      yj_err "    ✗ 本机 GMS 里没有 GoogleSettingsIALink"
      yj_err "    可能是 GMS 版本不同，或未安装 Google 服务"
      return 1
    fi
  fi

  _out="$(am start --user 0 -n "$_comp" 2>&1)"
  case "$_out" in
    *Error*|*Exception*|*"not found"*)
      yj_err "    ✗ 启动失败：$_out"
      return 1
      ;;
    *Starting*)
      yj_say "    ✓ 已打开 Google 设置"
      return 0
      ;;
    *)
      yj_say "    ℹ 返回：$_out"
      return 0
      ;;
  esac
}

yj_battery_optimize_apply() {
  _mode="$1"
  case "$_mode" in
    off|on) : ;;
    *) yj_err "  ✗ 模式只能是 off 或 on，收到：[$_mode]"; return 1 ;;
  esac

  for _c in pm dumpsys; do
    command -v "$_c" >/dev/null 2>&1 || { yj_err "  ✗ 缺少命令：$_c"; return 1; }
  done

  _ts="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
  [ -n "$_ts" ] || _ts="bak"
  mkdir -p "$YJ_HOME/backup" 2>/dev/null
  _snap="$YJ_HOME/backup/deviceidle-$_ts.txt"
  dumpsys deviceidle whitelist >"$_snap" 2>/dev/null
  yj_say "    ✓ 操作前白名单已快照：$(basename "$_snap")"

  _pkgs="$(pm list packages 2>/dev/null | sed 's/^package://' | tr -d '\r')"
  _n="$(printf '%s\n' "$_pkgs" | grep -c . 2>/dev/null)"
  [ -n "$_n" ] || _n=0
  if [ "$_n" = "0" ]; then
    yj_err "    ✗ 取不到包列表（pm list packages 返回空）"
    return 1
  fi
  yj_say "    共 $_n 个包，开始处理…"

  if [ "$_mode" = "off" ]; then
    _i=0
    printf '%s\n' "$_pkgs" | while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      dumpsys deviceidle whitelist +"$_p" >/dev/null 2>&1
    done
    yj_say "    ✓ 全部包已加入电池优化白名单"

    if command -v appops >/dev/null 2>&1 && command -v am >/dev/null 2>&1; then
      _3rd="$(pm list packages -3 2>/dev/null | sed 's/^package://' | tr -d '\r')"
      _m="$(printf '%s\n' "$_3rd" | grep -c . 2>/dev/null)"
      [ -n "$_m" ] || _m=0
      printf '%s\n' "$_3rd" | while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        am set-standby-bucket "$_p" active >/dev/null 2>&1
        appops set "$_p" RUN_IN_BACKGROUND allow >/dev/null 2>&1
        appops set "$_p" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
      done
      yj_say "    ✓ 三方应用（$_m 个）已设 active + 放开后台"
    else
      yj_warn "    缺少 appops 或 am，三方应用后台限制未放开"
    fi

  else
    printf '%s\n' "$_pkgs" | while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      dumpsys deviceidle whitelist -"$_p" >/dev/null 2>&1
    done
    yj_say "    ✓ 全部包已移出电池优化白名单"
  fi

  yj_state_set battery_opt_mode "$_mode"
  yj_say "  ✓ 电池优化策略已应用：$( [ "$_mode" = "off" ] && echo '全部不优化' || echo '全部优化' )"
  return 0
}

yj_battery_optimize_status() {
  _m="$(yj_sys_conf_get battery_auto none)"
  _cur="$(yj_state_get battery_opt_mode none)"
  printf 'auto:%s:cur:%s' "$_m" "$_cur"
  return 0
}

YJ_SAT_MIN="0.1"
YJ_SAT_MAX="3.0"

yj_sat_valid() {
  awk -v v="$1" -v lo="$YJ_SAT_MIN" -v hi="$YJ_SAT_MAX" \
    'BEGIN{ if (v+0==v && v>=lo && v<=hi) print "1"; else print "0" }' 2>/dev/null
}

yj_set_saturation() {
  _v="${1:-}"

  if [ -z "$_v" ]; then
    _cur="$(yj_state_get saturation 1.0)"
    yj_say "  ℹ 当前饱和度：$_cur（1.0 = 系统默认）"
    yj_say "  ℹ 用法：sh action.sh saturation <值>   范围 0.1 ~ 3.0"
    yj_say "  ℹ 例：0.5 偏灰 / 1.0 默认 / 1.5 鲜艳 / 2.0 很艳"
    return 2
  fi

  case "$_v" in
    ''|*[!0-9.]*) yj_err "  ✗ 饱和度必须是数字：[$_v]"; return 1 ;;
  esac
  if [ "$(yj_sat_valid "$_v")" != "1" ]; then
    yj_err "  ✗ 超出范围（0.1 ~ 3.0）：[$_v]"
    return 1
  fi

  if ! command -v service >/dev/null 2>&1; then
    yj_err "  ✗ 没有 service 命令"
    return 1
  fi

  _old="$(yj_state_get saturation 1.0)"

  _out="$(service call SurfaceFlinger 1022 f "$_v" 2>&1)"

  case "$_out" in
    *"Transaction failed"*|*"Permission denied"*|*"Exception"*|*"not found"*)
      yj_err "  ✗ 设置失败：$_out"
      return 1
      ;;
  esac

  yj_state_set saturation "$_v"
  yj_say "  ✓ 饱和度已设为 $_v（原为 $_old）"
  yj_say "  ℹ 即时生效，无需重启。恢复默认：sh action.sh saturation 1.0"
  return 0
}

yj_saturation_status() {
  _v="$(yj_state_get saturation 1.0)"
  [ -n "$_v" ] || _v="1.0"
  printf '%s' "$_v"
  return 0
}

yj_saturation_reapply() {
  _v="$(yj_state_get saturation 1.0)"
  case "$_v" in
    ''|1.0|1) return 0 ;;
  esac
  if [ "$(yj_sat_valid "$_v")" = "1" ]; then
    service call SurfaceFlinger 1022 f "$_v" >/dev/null 2>&1
    yj_log "saturation_reapply: 已恢复饱和度 $_v"
  fi
  return 0
}


yj_zwj() {
  printf '\342\200\215'
}

_yj_list_as_shell() {
  _p="$1"
  if command -v su >/dev/null 2>&1; then
    su shell -c "ls '$_p' 2>&1" 2>&1
  else
    ls "$_p" 2>&1
  fi
}

yj_scan_storage() {
  _zwj="$(yj_zwj)"

  yj_say "  → 扫盘漏洞检测"

  _uid=""
  if command -v su >/dev/null 2>&1; then
    _uid="$(su shell -c 'id -u' 2>/dev/null | tr -d ' \r\n')"
  fi
  if [ "$_uid" != "2000" ]; then
    yj_err "    ✗ 无法降权到 shell（当前 uid=[$_uid]）"
    yj_err "    root 身份下检测结果不可信（root 能读一切）"
    yj_err "    请在手机上直接运行本选项，或手动执行 sh action.sh scan-storage"
    return 1
  fi
  yj_say "    已降权到 shell(uid=2000) 执行检测"

  _vuln_list=""
  _chk=""
  for _pair in \
      "data:零宽:/sdcard/Android/data${_zwj}" \
      "obb:零宽:/sdcard/Android/obb${_zwj}" \
      "data:正常:/sdcard/Android/data" \
      "obb:正常:/sdcard/Android/obb" ; do
    _sub="${_pair%%:*}"
    _desc="$(printf '%s' "$_pair" | cut -d: -f2)"
    _path="$(printf '%s' "$_pair" | cut -d: -f3-)"
    _out="$(_yj_list_as_shell "$_path")"

    case "$_out" in
      *"Permission denied"*|*"Not a directory"*|*"No such file"*|'')
        _chk="$_chk
    ✓ Android/$_sub（$_desc）读不到，安全"
        ;;
      *)
        _chk="$_chk
    ❌ Android/$_sub（$_desc）能读取！共 $(printf '%s\n' "$_out" | grep -c . ) 项"
        _vuln_list="$_vuln_list
=== $_desc 访问 /sdcard/Android/$_sub ===
$(printf '%s\n' "$_out" | head -100)"
        ;;
    esac
  done

  printf '%s\n' "$_chk" | while IFS= read -r _l; do
    [ -n "$_l" ] && yj_say "$_l"
  done

  if [ -n "$_vuln_list" ]; then
    yj_err "系统存在访问漏洞（零宽字符可绕过 Android/data 限制）"
    printf '%s\n' "$_vuln_list" | while IFS= read -r _l; do
      [ -n "$_l" ] && yj_say "      $_l"
    done
    yj_state_set scan_result vulnerable
    return 1
  fi

  yj_say "    ✓ 系统安全，零宽字符无法绕过受限目录"
  yj_state_set scan_result safe
  return 0
}

yj_scan_status() {
  _r="$(yj_state_get scan_result none)"
  printf '%s' "$_r"
  return 0
}

yj_sys_autorun() {
  _bo="$(yj_sys_conf_get battery_auto none)"
  case "$_bo" in
    off|on)
      yj_log "sys_autorun: 开机执行电池优化策略 = $_bo"
      yj_battery_optimize_apply "$_bo" >>"$YJ_LOG" 2>&1
      ;;
  esac

  _sat="$(yj_sys_conf_get saturation_auto none)"
  case "$_sat" in
    none|'') : ;;
    *)
      if [ "$(yj_sat_valid "$_sat")" = "1" ]; then
        yj_log "sys_autorun: 开机应用饱和度 = $_sat"
        _n=0
        while [ "$_n" -lt 20 ]; do
          if pidof surfaceflinger >/dev/null 2>&1; then break; fi
          sleep 1
          _n=$((_n + 1))
        done
        service call SurfaceFlinger 1022 f "$_sat" >/dev/null 2>&1
        yj_state_set saturation "$_sat"
      else
        yj_log "sys_autorun: 饱和度值非法（$_sat），跳过"
      fi
      ;;
  esac
  return 0
}
