#!/system/bin/sh

YJ_KEYBOX_DIR="$YJ_HOME/keybox"
YJ_KEYBOX_TARGET="$TEESIM_DIR/keybox.xml"
YJ_KEYBOX_BACKUP="$YJ_HOME/backup/keybox"

YJ_KEYBOX_SCAN_DIRS="
$DOWNLOAD_DIR
$MEDIA_DOWNLOAD_DIR
$DOWNLOAD_DIR/MT管理器
$DOWNLOAD_DIR/Browser
${YJ_PREFIX}/sdcard/Download/Telegram
${YJ_PREFIX}/storage/emulated/0/Download
"

YJ_MT_PKG="bin.mt.plus"

YJ_MT2_NEW_DIR="${YJ_PREFIX}/sdcard/Download/MT管理器目录"
YJ_MT2_NEW_PATH="/sdcard/Download/MT管理器目录"

YJ_MT2_OLD_DIRS="
${YJ_PREFIX}/sdcard/MT2
${YJ_PREFIX}/storage/emulated/0/MT2
${YJ_PREFIX}/sdcard/mt2
${YJ_PREFIX}/storage/emulated/0/mt2
"

YJ_MT_PREFS_FILES="
${YJ_PREFIX}/data/user/0/${YJ_MT_PKG}/shared_prefs/${YJ_MT_PKG}_preferences.xml
${YJ_PREFIX}/data/data/${YJ_MT_PKG}/shared_prefs/${YJ_MT_PKG}_preferences.xml
${YJ_PREFIX}/data/user/0/bin.mt.plus.canary/shared_prefs/bin.mt.plus.canary_preferences.xml
"

yj_keybox_is_valid() {
  _f="$1"
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1

  _sz="$(wc -c <"$_f" 2>/dev/null | tr -d ' ')"
  [ -n "$_sz" ] || return 1
  [ "$_sz" -ge 200 ] 2>/dev/null || return 1
  [ "$_sz" -le 200000 ] 2>/dev/null || return 1

  _head="$(head -c 64 "$_f" 2>/dev/null | tr -d '\r\n\000 \t')"
  case "$_head" in
    "<"*) : ;;
    *) return 1 ;;
  esac

  if grep -qiE '<!doctype[[:space:]]+html|<html' "$_f" 2>/dev/null; then
    return 1
  fi

  if ! grep -qiE '<(Keybox|keys|KeyboxXml|KeyBox)' "$_f" 2>/dev/null; then
    return 1
  fi

  if ! grep -qiE '<(privateKey|PrivateKey|certificate|Certificate|algorithm)' "$_f" 2>/dev/null; then
    return 1
  fi

  return 0
}

yj_keybox_find_candidate() {
  _inbox="$YJ_KEYBOX_DIR/inbox"
  if [ -d "$_inbox" ]; then
    for _f in "$_inbox"/*; do
      [ -f "$_f" ] || continue
      if yj_keybox_is_valid "$_f"; then
        printf '%s' "$_f"
        return 0
      fi
    done
  fi

  _now="$(date +%s 2>/dev/null)"
  [ -n "$_now" ] || _now=0

  : >"$YJ_HOME/.keybox_candidates" 2>/dev/null
  for _d in "$DOWNLOAD_DIR" "$MEDIA_DOWNLOAD_DIR" "$DOWNLOAD_DIR/MT管理器目录" \
            "$DOWNLOAD_DIR/Browser" "$YJ_PREFIX/sdcard/Download/Telegram" \
            "$YJ_PREFIX/storage/emulated/0/Download"; do
    [ -d "$_d" ] || continue
    ls -t "$_d"/*.xml "$_d"/*.XML 2>/dev/null | head -n 20 >>"$YJ_HOME/.keybox_candidates" 2>/dev/null
  done

  [ -s "$YJ_HOME/.keybox_candidates" ] || {
    rm -f "$YJ_HOME/.keybox_candidates" 2>/dev/null
    return 1
  }

  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _mt="$(stat -c %Y "$_f" 2>/dev/null)"
    if [ -n "$_mt" ] && [ "$_now" -gt 0 ]; then
      _age=$((_now - _mt))
      if [ "$_age" -gt 172800 ] 2>/dev/null; then
        continue
      fi
    fi
    if yj_keybox_is_valid "$_f"; then
      rm -f "$YJ_HOME/.keybox_candidates" 2>/dev/null
      printf '%s' "$_f"
      return 0
    fi
  done <"$YJ_HOME/.keybox_candidates"

  rm -f "$YJ_HOME/.keybox_candidates" 2>/dev/null
  return 1
}

yj_keybox_deploy() {
  _src="${1:-}"
  if [ -z "$_src" ]; then
    _src="$(yj_keybox_find_candidate)" || {
      yj_say "  ℹ 未在下载目录找到可用 keybox.xml"
      return 1
    }
  fi

  if ! yj_keybox_is_valid "$_src"; then
    yj_err "  ✗ 文件不是有效 keybox：$_src"
    return 2
  fi

  mkdir -p "$TEESIM_DIR" "$YJ_KEYBOX_BACKUP" 2>/dev/null

  if [ -f "$YJ_KEYBOX_TARGET" ]; then
    _ts="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    [ -n "$_ts" ] || _ts="bak"
    cp -f "$YJ_KEYBOX_TARGET" "$YJ_KEYBOX_BACKUP/keybox-$_ts.xml" 2>/dev/null \
      && yj_say "  ✓ 旧 keybox 已备份：keybox-$_ts.xml"
  fi

  _tmp="$YJ_KEYBOX_TARGET.tmp.$$"
  if ! cp -f "$_src" "$_tmp" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null
    yj_err "  ✗ 复制失败：$_src"
    return 2
  fi

  _a="$(wc -c <"$_src" 2>/dev/null | tr -d ' ')"
  _b="$(wc -c <"$_tmp" 2>/dev/null | tr -d ' ')"
  if [ "$_a" != "$_b" ]; then
    rm -f "$_tmp" 2>/dev/null
    yj_err "  ✗ 复制不完整（源 $_a 字节，目标 $_b 字节）"
    return 2
  fi

  mv -f "$_tmp" "$YJ_KEYBOX_TARGET" 2>/dev/null || {
    rm -f "$_tmp" 2>/dev/null
    yj_err "  ✗ 写入失败：$YJ_KEYBOX_TARGET"
    return 2
  }

  yj_say "  ✓ keybox 已部署到 TEESimulator（$_b 字节）"

  _inbox="$YJ_KEYBOX_DIR/inbox"
  case "$_src" in
    "$_inbox"/*)
      yj_say "  ℹ 保留 inbox 内的原始文件"
      ;;
    *)
      rm -f "$_src" 2>/dev/null && yj_say "  ✓ 已清理下载的临时文件"
      ;;
  esac

  yj_state_set keybox_deployed 1
  yj_state_set keybox_source "$_src"

  return 0
}

yj_keybox_status() {
  if [ -f "$YJ_KEYBOX_TARGET" ]; then
    _sz="$(wc -c <"$YJ_KEYBOX_TARGET" 2>/dev/null | tr -d ' ')"
    if yj_keybox_is_valid "$YJ_KEYBOX_TARGET"; then
      printf 'installed:%s' "${_sz:-0}"
      return 0
    fi
    printf 'installed-invalid:%s' "${_sz:-0}"
    return 1
  fi
  if _c="$(yj_keybox_find_candidate)"; then
    printf 'pending:%s' "$_c"
    return 2
  fi
  printf 'none'
  return 3
}

yj_keybox_open_page() {
  _url="https://keybox.kowx712.cc/?id=32"
  if command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$_url" >/dev/null 2>&1 \
      && { yj_say "  ✓ 已在浏览器打开 keybox 下载页"; return 0; }
  fi
  yj_say "  ℹ 请手动在浏览器打开：$_url"
  return 1
}

yj_keybox_device_id() {
  _id="$(getprop ro.serialno 2>/dev/null | tr -d ' \r\n')"
  [ -n "$_id" ] || _id="$(getprop ro.boot.serialno 2>/dev/null | tr -d ' \r\n')"
  [ -n "$_id" ] || _id="$(getprop ro.product.device 2>/dev/null | tr -d ' \r\n')"
  [ -n "$_id" ] || _id="unknown"
  printf '%s' "$_id"
}

yj_keybox_tool_path() {
  for _t in "${YJ_PREFIX}/vendor/lib64/hw/KmInstallKeybox" \
            /vendor/lib64/hw/KmInstallKeybox \
            /vendor/lib/hw/KmInstallKeybox \
            /system/lib64/hw/KmInstallKeybox; do
    [ -e "$_t" ] && { printf '%s' "$_t"; return 0; }
  done
  printf 'KmInstallKeybox'
  return 1
}

# 手动执行：把 keybox 写进 KeyMint / Keymaster
#   strict → 只走 RKP：KmInstallKeybox keybox.xml <设备号> true rkp
#   loose  → 先 RKP，失败回退传统模式：… true rkp || … true true
# 需要先部署好 keybox.xml（WebUI 的「检测并部署」那一步）。
yj_keybox_install() {
  _opt="${1:-loose}"
  _kb="$YJ_KEYBOX_TARGET"
  [ -s "$_kb" ] || {
    yj_err "  ✗ 还没部署 keybox.xml：$YJ_KEYBOX_TARGET"
    yj_say "  ℹ 先在 WebUI 点「检测并部署已下载的 keybox」"
    return 1
  }

  _tool="$(yj_keybox_tool_path)"
  _id="$(yj_keybox_device_id)"
  _dir="$YJ_HOME/keybox-install"
  mkdir -p "$_dir" 2>/dev/null
  cp -f "$_kb" "$_dir/keybox.xml" 2>/dev/null || { yj_err "  ✗ 准备 workdir 失败：$_dir"; return 2; }

  _cmd="LD_LIBRARY_PATH=/vendor/lib64/hw $_tool keybox.xml $_id true rkp"
  [ "$_opt" = "loose" ] && _cmd="$_cmd  ||  LD_LIBRARY_PATH=/vendor/lib64/hw $_tool keybox.xml $_id true true"
  yj_say "  keybox : $_kb"
  yj_say "  执行   : $_cmd"

  _rc=1
  if [ -n "${YJ_PREFIX}" ]; then
    yj_say "  ℹ 离线测试模式：只走流程，不真正调用工具"
    _rc=0
    rm -f "$_dir/keybox.xml" 2>/dev/null
    rmdir "$_dir" 2>/dev/null
    return $_rc
  fi

  (
    cd "$_dir" || exit 2
    if [ "$_opt" = "strict" ]; then
      LD_LIBRARY_PATH=/vendor/lib64/hw "$_tool" keybox.xml "$_id" true rkp
    else
      LD_LIBRARY_PATH=/vendor/lib64/hw "$_tool" keybox.xml "$_id" true rkp \
        || LD_LIBRARY_PATH=/vendor/lib64/hw "$_tool" keybox.xml "$_id" true true
    fi
  ) 2>&1
  _rc=$?

  rm -f "$_dir/keybox.xml" 2>/dev/null
  rmdir "$_dir" 2>/dev/null
  return $_rc
}

yj_mt2_find_prefs() {
  for _p in "$YJ_PREFIX/data/user/0/$YJ_MT_PKG/shared_prefs/$YJ_MT_PKG"_preferences.xml \
            "$YJ_PREFIX/data/data/$YJ_MT_PKG/shared_prefs/$YJ_MT_PKG"_preferences.xml \
            "$YJ_PREFIX/data/user/0/bin.mt.plus.canary/shared_prefs/bin.mt.plus.canary"_preferences.xml; do
    if [ -f "$_p" ]; then
      printf '%s' "$_p"
      return 0
    fi
  done
  return 1
}

yj_mt2_is_workdir() {
  _d="$1"
  [ -d "$_d" ] || return 1
  case "$_d" in
    "$YJ_MT2_NEW_DIR") return 1 ;;
  esac
  _b="$(basename "$_d")"
  case "$(printf '%s' "$_b" | tr 'A-Z' 'a-z')" in
    mt2) : ;;
    *) return 1 ;;
  esac
  return 0
}

yj_mt2_set_path() {
  _want="${1:-$YJ_MT2_NEW_PATH}"
  _pf="$(yj_mt2_find_prefs)" || {
    yj_err "    ✗ 找不到 MT 配置文件（MT 管理器可能没装或没运行过）"
    return 1
  }

  yj_say "    配置文件：$_pf"

  if grep -qF "<string name=\"mt2_path\">$_want</string>" "$_pf" 2>/dev/null; then
    yj_say "    ℹ mt2_path 已是 $_want，无需改写"
    return 2
  fi

  _ts="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
  [ -n "$_ts" ] || _ts="bak"
  mkdir -p "$YJ_HOME/backup/mt2" 2>/dev/null
  cp -f "$_pf" "$YJ_HOME/backup/mt2/$(basename "$_pf").$_ts.bak" 2>/dev/null \
    && yj_say "    ✓ 已备份原配置"

  _tmp="$LOCAL_TMP/mt2_cfg.$$"
  mkdir -p "$LOCAL_TMP" 2>/dev/null
  _have=0
  grep -q 'name="mt2_path"' "$_pf" 2>/dev/null && _have=1

  if [ "$_have" = "1" ]; then
    sed "s|<string name=\"mt2_path\">.*</string>|<string name=\"mt2_path\">$_want</string>|g" \
      "$_pf" >"$_tmp" 2>/dev/null
  else
    sed "/<\/map>/i\\    <string name=\"mt2_path\">$_want</string>" \
      "$_pf" >"$_tmp" 2>/dev/null
  fi

  if [ ! -s "$_tmp" ]; then
    rm -f "$_tmp" 2>/dev/null
    yj_err "    ✗ 生成新配置失败"
    return 1
  fi

  _cnt="$(grep -c "name=\"mt2_path\">$_want</string>" "$_tmp" 2>/dev/null)"
  if [ "$_cnt" != "1" ]; then
    rm -f "$_tmp" 2>/dev/null
    yj_err "    ✗ 校验失败：mt2_path 出现 $_cnt 次（应为 1）"
    return 1
  fi
  if ! head -n 3 "$_tmp" 2>/dev/null | grep -q '<?xml' \
     || ! grep -q '</map>' "$_tmp" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null
    yj_err "    ✗ 校验失败：生成的文件不是完整 XML"
    return 1
  fi

  if cat "$_tmp" >"$_pf" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null
  elif mv "$_tmp" "$_pf" 2>/dev/null; then
    :
  else
    rm -f "$_tmp" 2>/dev/null
    yj_err "    ✗ 写回失败：$_pf"
    return 1
  fi

  if grep -qF "<string name=\"mt2_path\">$_want</string>" "$_pf" 2>/dev/null; then
    yj_say "    ✓ mt2_path 已写入：$_want"
    return 0
  fi
  yj_err "    ✗ 回读校验失败"
  return 1
}

yj_mt2_migrate() {
  _new="$YJ_MT2_NEW_DIR"
  _did=0
  _err=0
  _cfg_changed=0

  yj_say "  → MT2 目录迁移"

  if [ ! -d "$_new" ]; then
    if mkdir -p "$_new" 2>/dev/null; then
      yj_say "    ✓ 已创建：$_new"
      _did=1
    else
      yj_err "    ✗ 创建失败：$_new"
      return 1
    fi
  else
    yj_say "    ℹ 新目录已存在：$_new"
  fi

  for _sub in keys keystore; do
    [ -d "$_new/$_sub" ] || mkdir -p "$_new/$_sub" 2>/dev/null
  done

  yj_mt2_move_item() {
    _mi_src="$1"
    _mi_dst="$2"
    _mi_base="$(basename "$_mi_src")"
    _mi_target="$_mi_dst/$_mi_base"

    if [ ! -e "$_mi_target" ]; then
      if mv "$_mi_src" "$_mi_target" 2>/dev/null; then
        yj_say "    ✓ 已迁移：$_mi_base"
        return 0
      fi
      yj_warn "    ⚠ 迁移失败：$_mi_base"
      return 1
    fi

    if [ -d "$_mi_src" ] && [ -d "$_mi_target" ]; then
      _mi_ok=0
      for _mi_child in "$_mi_src"/*; do
        [ -e "$_mi_child" ] || continue
        yj_mt2_move_item "$_mi_child" "$_mi_target" || _mi_ok=1
      done
      rmdir "$_mi_src" 2>/dev/null
      return "$_mi_ok"
    fi

    _mi_alt="$_mi_target.old"
    _mi_n=1
    while [ -e "$_mi_alt" ]; do
      _mi_alt="$_mi_target.old$_mi_n"
      _mi_n=$((_mi_n + 1))
    done
    if mv "$_mi_src" "$_mi_alt" 2>/dev/null; then
      yj_say "    ✓ 同名文件改名保留：$(basename "$_mi_alt")"
      return 0
    fi
    yj_warn "    ⚠ 改名失败：$_mi_base"
    return 1
  }

  : >"$YJ_HOME/.mt2_old" 2>/dev/null
  for _old in "$YJ_PREFIX/sdcard/MT2" "$YJ_PREFIX/storage/emulated/0/MT2" \
              "$YJ_PREFIX/sdcard/mt2" "$YJ_PREFIX/storage/emulated/0/mt2"; do
    yj_mt2_is_workdir "$_old" || continue
    echo "OLD:$_old" >>"$YJ_HOME/.mt2_old" 2>/dev/null
  done

  if [ -s "$YJ_HOME/.mt2_old" ]; then
    while IFS= read -r _line; do
      _old="${_line#OLD:}"
      [ -d "$_old" ] || continue

      _ts="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
      [ -n "$_ts" ] || _ts="bak"
      mkdir -p "$YJ_HOME/backup/mt2" 2>/dev/null
      ls -laR "$_old" >"$YJ_HOME/backup/mt2/$_ts-$(basename "$_old").list" 2>/dev/null

      _did=1
      for _item in "$_old"/*; do
        [ -e "$_item" ] || continue
        yj_mt2_move_item "$_item" "$_new" || _err=1
      done

      if [ -d "$_old" ]; then
        if rmdir "$_old" 2>/dev/null; then
          yj_say "    ✓ 已删除空目录：$_old"
        else
          yj_warn "    ⚠ 旧目录仍有内容，保留：$_old"
        fi
      fi
    done <"$YJ_HOME/.mt2_old"
  else
    yj_say "    ℹ 未发现旧 MT2 目录"
  fi
  rm -f "$YJ_HOME/.mt2_old" 2>/dev/null

  yj_mt2_set_path "$YJ_MT2_NEW_PATH"
  _rc=$?
  case "$_rc" in
    0) _cfg_changed=1; _did=1 ;;
    2) : ;;
    *) _err=2 ;;
  esac

  if [ "$_cfg_changed" = "1" ]; then
    yj_warn "  ⚠ 配置已改，请【强制停止 MT 管理器】再重开，否则会被它覆写回去"
  fi
  if [ "$_err" = "1" ]; then
    yj_warn "  ⚠ 部分文件迁移失败，请检查上面输出"
    return 1
  fi
  if [ "$_did" = "1" ]; then
    yj_state_set mt2_migrated 1
    yj_say "  ✓ MT2 迁移完成：$_new"
    return 0
  fi
  yj_say "  ℹ MT2 已是目标状态，无需操作"
  return 2
}

yj_mt2_status() {
  _new="$YJ_MT2_NEW_DIR"
  _pf="$(yj_mt2_find_prefs 2>/dev/null)"
  _cur=""
  if [ -n "$_pf" ]; then
    _cur="$(sed -n 's|.*<string name="mt2_path">\(.*\)</string>.*|\1|p' "$_pf" 2>/dev/null | head -n1)"
  fi
  if [ -n "$_cur" ]; then
    printf 'path:%s' "$_cur"
    return 0
  fi
  if [ -d "$_new" ]; then
    printf 'dir-only:%s' "$_new"
    return 2
  fi
  printf 'none'
  return 1
}

yj_mt2_open_dir() {
  yj_say "  ℹ 新 MT2 目录：$YJ_MT2_NEW_DIR"
  yj_say "  ℹ mt2_path 目标值：$YJ_MT2_NEW_PATH"
  return 0
}

yj_clear_logd_size() {
  yj_say "  → 清空 logd 尺寸属性"

  if ! command -v setprop >/dev/null 2>&1; then
    yj_err "    ✗ 没有 setprop 命令"
    return 1
  fi

  _bad=0
  for _p in persist.logd.size persist.logd.size.crash persist.logd.size.system persist.logd.size.main; do
    if setprop "$_p" "" 2>/dev/null; then
      yj_say "    ✓ ${_p} 已清空"
    else
      yj_err "    ✗ ${_p} 设置失败"
      _bad=1
    fi
  done

  _after="$(getprop persist.logd.size 2>/dev/null)"
  if [ -n "$_after" ]; then
    yj_warn "    ⚠ 回读仍有值：$_after（可能需要重启 logd 生效）"
  fi

  [ "$_bad" = "0" ] || return 1
  yj_state_set logd_size_cleared 1
  yj_say "  ✓ logd 尺寸已清空"
  return 0
}

yj_clear_usb_debug() {
  yj_say "  → 关闭 USB 调试"

  _bad=0

  if command -v settings >/dev/null 2>&1; then
    for _kv in "global adb_enabled 0" "secure usb_debugging_enabled 0" "global wireless_adb_enabled 0"; do
      _ns="$(echo "$_kv" | cut -d' ' -f1)"
      _key="$(echo "$_kv" | cut -d' ' -f2)"
      _val="$(echo "$_kv" | cut -d' ' -f3)"
      if settings put "$_ns" "$_key" "$_val" >/dev/null 2>&1; then
        yj_say "    ✓ ${_ns}/${_key} = $_val"
      else
        yj_warn "    ⚠ ${_ns}/${_key} 设置失败"
        _bad=1
      fi
    done
  else
    yj_warn "    ⚠ 没有 settings 命令，跳过 settings 部分"
  fi

  if command -v setprop >/dev/null 2>&1; then
    for _p in sys.usb.adb.disabled persist.security.adbinput persist.service.adb.enable persist.security.adbinstall; do
      if setprop "$_p" "" 2>/dev/null; then
        yj_say "    ✓ ${_p} 已清空"
      else
        yj_warn "    ⚠ ${_p} 设置失败"
        _bad=1
      fi
    done
  else
    yj_err "    ✗ 没有 setprop 命令"
    return 1
  fi

  if command -v settings >/dev/null 2>&1; then
    _adb="$(settings get global adb_enabled 2>/dev/null)"
    case "$_adb" in
      0) yj_say "    ✓ 复查：adb_enabled=$_adb" ;;
      *) yj_warn "    ⚠ 复查：adb_enabled=$_adb（未生效）" ;;
    esac
  fi

  [ "$_bad" = "0" ] || return 1
  yj_state_set usb_debug_cleared 1
  yj_say "  ✓ USB 调试已关闭"
  return 0
}
