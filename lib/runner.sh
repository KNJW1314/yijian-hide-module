#!/system/bin/sh

yj_all_done() {
  [ "$(yj_state_get all_done 0)" = "1" ]
}

yj_current_phase() {
  if yj_all_done; then
    printf '9'
    return 0
  fi
  if [ "$(yj_state_get phase1_done 0)" != "1" ]; then
    printf '0'
    return 0
  fi
  if yj_rebooted_since_stage1; then
    printf '2'
  else
    printf '1'
  fi
}

yj_autorun() {
  _p="$(yj_current_phase)"
  case "$_p" in
    9)
      yj_hma_verify >/dev/null 2>&1 || true
      return 0
      ;;
    1)
      yj_log "autorun: 等待重启（phase=1）"
      return 0
      ;;
    0)
      yj_log "autorun: 阶段1未完成，跳过"
      return 0
      ;;
    2)
      yj_say "──────── 检测到重启，自动执行阶段2 ────────"
      if yj_run_stage config; then
        yj_stage_final 1
      else
        yj_stage_final 0
      fi
      ;;
  esac
  return 0
}

yj_manual_run() {
  _p="$(yj_current_phase)"
  case "$_p" in
    9)
      yj_say "已全部完成。"
      yj_say "如需重跑配置（幂等，不会破坏已有数据）："
      yj_say "   sh $MODDIR/action.sh config"
      ;;
    0)
      yj_say "阶段1未完成（模块未刷入），无法在模块内补刷。"
      yj_say "请在管理器内重新刷入本模块 zip。"
      ;;
    1)
      yj_say "阶段1已完成，请先【重启设备】，重启后会自动执行阶段2。"
      yj_say "（也可以重启前直接手动跑：sh $MODDIR/action.sh config）"
      ;;
    2)
      yj_say "──────── 手动执行阶段2 ────────"
      if yj_run_stage config; then
        yj_stage_final 1
      else
        yj_stage_final 0
      fi
      ;;
  esac
  return 0
}

yj_run_stage() {
  _what="$1"
  case "$_what" in
    config)
      yj_stage_config
      return $?
      ;;
    hma)
      yj_hma_early
      return $?
      ;;
    modules)
      yj_stage_modules
      return $?
      ;;
    final)
      yj_stage_final 1
      return $?
      ;;
    *)
      yj_warn "未知阶段：$_what"
      return 1
      ;;
  esac
}

yj_add_fgetpriority() {
  [ -n "$(yj_module_dir fgetpriority)" ]
}
