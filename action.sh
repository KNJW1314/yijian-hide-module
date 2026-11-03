#!/system/bin/sh
MODDIR=${0%/*}
YJ_PREFIX="${YJ_PREFIX:-}"

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/stages.sh"
. "$MODDIR/lib/runner.sh"
. "$MODDIR/lib/webui_ext.sh"
. "$MODDIR/lib/sys_ext.sh"
. "$MODDIR/lib/brightness_ext.sh"

yj_init

case "${1:-status}" in
  run)
    yj_manual_run
    ;;
  config)
    yj_run_stage config
    ;;
  hma)
    yj_hma_early
    echo ""
    echo "已重做 HMA 写入。请重启一次让服务端按新配置重建运行环境。"
    ;;
  noautoreboot)
    case "${2:-}" in
      1) yj_state_set hma_auto_reboot 0; echo "已关闭自动重启：需要重启时会提示你手动重启" ;;
      0) yj_state_set hma_auto_reboot 1; echo "已开启自动重启：需要重启时会自动重启" ;;
      *) echo "当前 hma_auto_reboot = $(yj_state_get hma_auto_reboot 1)（1=开启 0=关闭）"
         echo "用法: sh action.sh noautoreboot 1|0" ;;
    esac
    ;;
  log)
    yj_show_log
    ;;
  keybox-open)
    yj_keybox_open_page
    ;;
  keybox-deploy)
    yj_keybox_deploy
    _rc=$?
    echo ""
    case "$_rc" in
      0) echo "keybox 部署完成" ;;
      1) echo "未找到可用 keybox.xml：请先在浏览器下载" ;;
      *) echo "部署失败，请检查上面输出" ;;
    esac
    exit $_rc
    ;;
  keybox-status)
    yj_keybox_status
    echo ""
    ;;
  keybox-fix)
    case "${2:-loose}" in
      loose|strict) ;;
      *) echo "用法: sh action.sh keybox-fix loose|strict"; exit 1 ;;
    esac
    yj_keybox_install "${2:-loose}"
    exit $?
    ;;
  mt2-migrate)
    yj_mt2_migrate
    _rc=$?
    echo ""
    case "$_rc" in
      0) echo "MT2 迁移完成" ;;
      2) echo "MT2 已是目标状态，无需操作" ;;
      *) echo "迁移未完全成功，请检查上面输出" ;;
    esac
    exit $_rc
    ;;
  mt2-open)
    yj_mt2_open_dir
    ;;
  mt2-status)
    yj_mt2_status
    echo ""
    ;;
  mt2-path)
    yj_mt2_set_path "${2:-$YJ_MT2_NEW_PATH}"
    ;;
  logd-clear)
    yj_clear_logd_size
    ;;
  usb-clear)
    yj_clear_usb_debug
    ;;
  battery-life)
    yj_battery_life
    ;;
  battery-status)
    yj_battery_status
    echo ""
    ;;
  google-settings)
    yj_open_google_settings
    ;;
  battery-opt)
    case "${2:-}" in
      off|on) yj_battery_optimize_apply "${2}" ;;
      '')
        echo "当前策略: $(yj_battery_optimize_status)"
        echo ""
        echo "用法: sh action.sh battery-opt off   # 全部不优化"
        echo "      sh action.sh battery-opt on    # 全部优化"
        ;;
      *) echo "参数只能是 off 或 on"; exit 1 ;;
    esac
    ;;
  battery-auto)
    case "${2:-}" in
      none|off|on)
        yj_sys_conf_set battery_auto "${2}"
        echo "✓ 开机自动电池策略已设为：${2}"
        echo "  none=不自动  off=全部不优化  on=全部优化"
        ;;
      *)
        echo "当前: $(yj_sys_conf_get battery_auto none)"
        echo "用法: sh action.sh battery-auto none|off|on"
        ;;
    esac
    ;;
  saturation)
    yj_set_saturation "${2:-}"
    _rc=$?
    [ "$_rc" = "0" ] && exit 0
    exit 0
    ;;
  saturation-status)
    yj_saturation_status
    echo ""
    ;;
  saturation-auto)
    case "${2:-}" in
      none|'')
        yj_sys_conf_set saturation_auto none
        echo "✓ 开机自动饱和度：已关闭"
        ;;
      *)
        _v="$2"
        case "$_v" in
          *[!0-9.]*) echo "值必须是数字"; exit 1 ;;
        esac
        _ok="$(awk -v v="$_v" 'BEGIN{ if (v>=0.1 && v<=3.0) print "1"; else print "0" }' 2>/dev/null)"
        if [ "$_ok" != "1" ]; then echo "超出范围 0.1~3.0"; exit 1; fi
        yj_sys_conf_set saturation_auto "$_v"
        echo "✓ 开机自动饱和度已设为：$_v"
        ;;
    esac
    ;;
  scan-storage)
    yj_scan_storage
    _rc=$?
    exit $_rc
    ;;
  scan-status)
    yj_scan_status
    echo ""
    ;;
  brightness)
    yj_bl_show_current
    ;;
  brightness-max)
    yj_bl_show_max
    ;;
  brightness-unlock)
    if [ -z "${2:-}" ]; then
      yj_bl_unlock
    else
      _want="$2"
      _max="$(yj_bl_max)"
      case "$_want" in
        ''|*[!0-9]*) echo "亮度值必须是整数"; exit 1 ;;
      esac
      case "$_max" in
        ''|*[!0-9]*|0) echo "读不到 max_brightness"; exit 1 ;;
      esac
      if [ "$_want" -gt "$_max" ] 2>/dev/null; then
        echo "超过硬件上限 $_max，拒绝写入：[$_want]"
        echo "请用：sh action.sh brightness-unlock    （自动取上限）"
        exit 1
      fi
      if echo "$_want" >"$YJ_BL_BASE/brightness" 2>/dev/null; then
        echo "✓ 亮度已设为 $_want（上限 $_max）"
        yj_state_set bl_cur "$_want"
      else
        echo "✗ 写入失败"
        exit 1
      fi
    fi
    ;;
  brightness-lock-on)
    yj_bl_lock_start
    ;;
  brightness-lock-off)
    yj_bl_lock_stop
    ;;
  brightness-lock-status)
    yj_bl_lock_status
    echo ""
    ;;
  brightness-auto)
    case "${2:-}" in
      none|on)
        yj_sys_conf_set brightness_auto "${2}"
        echo "✓ 开机自动持续解锁已设为：${2}"
        ;;
      *)
        echo "当前: $(yj_sys_conf_get brightness_auto none)"
        echo "用法: sh action.sh brightness-auto none|on"
        ;;
    esac
    ;;
  *)
    yj_show_status
    echo ""
    echo "----------------------------------------"
    echo " 进度      : $(yj_current_phase) （0=未装 1=待重启 2=待配置 9=已完成）"
    echo " 阶段1完成 : $(yj_state_get phase1_done 0)"
    echo " 全部完成  : $(yj_state_get all_done 0)"
    echo " HMA 写入  : $(yj_state_get hma_early_done 0)"
    echo " HMA 生效  : $(yj_state_get hma_done 0)"
    echo " 人工清单  : $(yj_state_get checklist_hint 见 Download 目录)"
    echo "----------------------------------------"
    echo " 可用参数:"
    echo "   sh action.sh run            重跑未完成的阶段（幂等）"
    echo "   sh action.sh config         只重跑阶段2（参数配置）"
    echo "   sh action.sh hma            重做 HMA 写入（清残留 + 写配置）"
    echo "   sh action.sh noautoreboot 1 关闭自动重启（默认开启）"
    echo "   sh action.sh log            查看日志"
    echo "----------------------------------------"
    echo " 1.9 新增:"
    echo "   sh action.sh keybox-open    打开 keybox 下载页"
    echo "   sh action.sh keybox-deploy  部署已下载的 keybox"
    echo "   sh action.sh mt2-migrate    迁移 MT2 目录"
    echo "   keybox 状态: $(yj_keybox_status 2>/dev/null)"
    echo "   MT2 状态   : $(yj_mt2_status 2>/dev/null)"
    echo "----------------------------------------"
    echo " 作者 酷安@KNJ蛙　免费发布，禁止倒卖"
    echo "----------------------------------------"
    ;;
esac
exit 0
