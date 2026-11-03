#!/system/bin/sh

SKIPUNZIP=1

ui_print " "
ui_print "*******************************"

MODDIR="${MODPATH:-$MODDIR}"
[ -n "$MODDIR" ] || { abort "! 无法确定模块目录"; }

[ -f "$MODDIR/module.prop" ] || {
  unzip -o "$ZIPFILE" 'lib/*' 'webroot/*' 'payload/*' 'module.prop' 'service.sh' 'action.sh' \
        'post-fs-data.sh' 'uninstall.sh' 'webui_status.sh' 'webui_brightness.sh' -d "$MODDIR" >/dev/null 2>&1
}

_VER=""
[ -f "$MODDIR/module.prop" ] && \
  _VER="$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1 | tr -d '\r ')"
[ -n "$_VER" ] || abort "! 读不到 module.prop 的 version，安装包不完整"

ui_print "  一键隐藏模块 v$_VER"
ui_print "  作者: 酷安@KNJ蛙"
ui_print "  免费发布，禁止倒卖"
ui_print "*******************************"
ui_print " "

[ -f "$MODDIR/lib/common.sh" ] || {
  unzip -o "$ZIPFILE" 'lib/*' 'webroot/*' 'payload/*' 'module.prop' 'service.sh' 'action.sh' \
        'post-fs-data.sh' 'uninstall.sh' 'webui_status.sh' 'webui_brightness.sh' -d "$MODDIR" >/dev/null 2>&1
}
[ -f "$MODDIR/lib/common.sh" ] || abort "! 缺少 lib/common.sh，安装包不完整"

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/stages.sh"

yj_init

if command -v set_perm >/dev/null 2>&1; then
  for _f in service.sh post-fs-data.sh action.sh uninstall.sh webui_status.sh webui_brightness.sh; do
    [ -f "$MODDIR/$_f" ] && set_perm "$MODDIR/$_f" 0 0 0755 2>/dev/null
  done
  for _f in "$MODDIR"/lib/*.sh; do
    [ -f "$_f" ] && set_perm "$_f" 0 0 0644 2>/dev/null
  done
  set_perm_recursive "$MODDIR/payload" 0 0 0755 0644 2>/dev/null
fi
chmod 0755 "$MODDIR"/*.sh 2>/dev/null
chmod 0644 "$MODDIR"/lib/*.sh "$MODDIR/module.prop" 2>/dev/null

_KV="$(uname -r 2>/dev/null)"
_KM="$(yj_kernel 2>/dev/null)"
ui_print "- 内核: $_KV"
[ -n "$_KM" ] && ui_print "- KMI : $_KM"

if yj_is_legacy_kernel; then
  ui_print "! 检测到 4.x / 5.4 内核"
  ui_print "! NoMount / FuseHide / PathMask / fgetpriority / SUSFS 均不适配"
  ui_print "! 这些模块会自动跳过，其余照常安装"
fi

_IMPL="$(yj_detect_root)"
case "$_IMPL" in
  ksu)    ui_print "- Root 管理器: KernelSU" ;;
  apatch) ui_print "- Root 管理器: APatch" ;;
  magisk) ui_print "- Root 管理器: Magisk" ;;
  *)      ui_print "! 无法识别 Root 管理器" ;;
esac

ui_print " "
ui_print "- 开始按教程顺序刷入全部模块（一次性，中途不重启）"
ui_print " "

YJ_PREFIX="${YJ_PREFIX:-}" MODDIR="$MODDIR" sh -c '
  MODDIR="'"$MODDIR"'"
  YJ_PREFIX="'"${YJ_PREFIX:-}"'"
  export MODDIR YJ_PREFIX
  . "$MODDIR/lib/common.sh"
  . "$MODDIR/lib/stages.sh"
  yj_init
  yj_stage_modules
' 2>&1 | while IFS= read -r _line; do ui_print "$_line"; done

_ALL_DONE="$(yj_state_get all_done 0)"

yj_state_set boot_id_stage1 "$(yj_boot_id)"
yj_state_set phase1_done 1

ui_print " "
ui_print "================================"
if [ "$_ALL_DONE" = "1" ]; then
  ui_print " 本模块此前已完成全部配置"
  ui_print " 本次为覆盖重刷：已保留完成状态"
  ui_print " "
  ui_print " 模块与 payload 已是最新，无需再次配置"
  ui_print " 如要重跑配置：sh action.sh config"
else
  ui_print " 阶段1完成：模块已全部刷入"
  ui_print " "
  ui_print " 请【重启设备】一次"
  ui_print " 重启后自动完成参数配置"
fi
ui_print "================================"
ui_print " "
ui_print "- 其中两项需要联网（访问 GitHub），必须你手动做："
ui_print "    - PlayIntegrityFix 指纹（Autopif）"
ui_print "    - Duck ToolBox 密钥（keybox）"
ui_print "  详细步骤会在重启后写进 Download 目录，并在模块列表里显示路径"
ui_print " "
ui_print "- HMA-OSS 配置会在下次开机的【最早期】自动写入到"
ui_print "  /data/misc/hide_my_applist_*/config.json（服务端真正读取的位置），"
ui_print "  因此重启后无需手动导入，也不会出现模板空白。"
ui_print " "

if [ "$_ALL_DONE" = "1" ]; then
  _hint="$(yj_state_get checklist_hint 2>/dev/null)"
  [ -n "$_hint" ] || _hint="Download/一键隐藏_人工清单.txt"
  yj_update_desc "✅ 已完成，人工项见 $_hint"
else
  yj_update_desc "阶段1已完成，等待重启自动执行阶段2（参数配置）"
fi
