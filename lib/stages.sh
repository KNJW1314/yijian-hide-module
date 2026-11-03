#!/system/bin/sh

yj_hma_early() {
  _md="$(yj_module_dir hma_oss_zygisk)"
  if [ -z "$_md" ]; then
    return 0
  fi
  _src="$(yj_payload_file 'HMA-OSS_config_*.json')"
  if [ -z "$_src" ]; then
    return 0
  fi

  _sha="$(yj_sha1 "$_src")"

  if yj_hma_locate >/dev/null 2>&1 && [ -s "$HMA_CFG" ]; then
    if [ "$(yj_state_get hma_early_done 0)" = "1" ] \
       && [ -n "$_sha" ] && [ "$(yj_state_get hma_cfg_sha)" = "$_sha" ]; then
      yj_log "HMA: 配置已是当前预设且存在于 $HMA_CFG，跳过（不动用户改动）"
      return 0
    fi
  fi

  yj_say "──────── HMA-OSS 配置写入 ────────"

  if ! grep -q '"configVersion"' "$_src" 2>/dev/null; then
    yj_warn "预设 json 缺少 configVersion，疑似损坏，放弃写入（不动现有配置）"
    return 1
  fi

  if ! yj_hma_locate >/dev/null 2>&1 || [ -z "$HMA_DATA_DIR" ]; then
    HMA_DATA_DIR="$(yj_hma_target_dir)"
    HMA_CFG="$HMA_DATA_DIR/config.json"
  fi
  if ! mkdir -p "$HMA_DATA_DIR" 2>/dev/null; then
    if [ -d "$HMA_DATA_DIR" ]; then
      yj_say "  ℹ 目录已存在，跳过创建：$HMA_DATA_DIR"
    else
      yj_err "无法创建 HMA 数据目录：$HMA_DATA_DIR"
      return 1
    fi
  fi

  if ! cat "$_src" >"$HMA_CFG" 2>/dev/null || [ ! -s "$HMA_CFG" ]; then
    yj_err "写入失败：$HMA_CFG"
    return 1
  fi
  chmod 0660 "$HMA_CFG" 2>/dev/null
  chmod 0770 "$HMA_DATA_DIR" 2>/dev/null

  yj_restorecon "$HMA_DATA_DIR" "$HMA_CFG"

  chown 1000:1000 "$HMA_DATA_DIR" "$HMA_CFG" 2>/dev/null

  yj_say "  ✓ 主配置已写入 $HMA_CFG"

  mkdir -p "$DOWNLOAD_DIR" 2>/dev/null
  cp -f "$_src" "$DOWNLOAD_DIR/" 2>/dev/null

  yj_state_set hma_early_done 1
  yj_state_set hma_cfg_sha "$_sha"
  yj_state_set hma_data_dir "$HMA_DATA_DIR"
  yj_state_set hma_write_ts "$(date +%s 2>/dev/null)"
  yj_state_set hma_dir_gone 0
  yj_say "  ℹ 配置位置（服务端实际读取）：$HMA_CFG"
  return 0
}

yj_hma_verify() {
  [ "$(yj_state_get hma_early_done 0)" = "1" ] || return 0

  if ! yj_hma_locate; then
    yj_state_set hma_needs_reboot 1
    yj_state_set hma_dir_gone 1
    yj_warn "  HMA 数据目录不存在（可能被清除残留配置删掉了）—— 需要重写并重启"
    return 1
  fi

  if [ ! -s "$HMA_CFG" ]; then
    yj_state_set hma_needs_reboot 1
    yj_warn "  HMA 配置文件不存在：$HMA_CFG —— 需要重写并重启"
    return 1
  fi

  _ver="$(yj_json_int "$HMA_CFG" configVersion 4096)"
  if [ "$_ver" != "93" ]; then
    yj_state_set hma_needs_reboot 1
    yj_warn "  HMA configVersion=${_ver:-?}，服务端要求 93 —— 会判为不匹配并留空配置，重新写入"
    return 1
  fi

  _st="$HMA_DATA_DIR/status.json"
  if [ -s "$_st" ]; then
    _mode="$(yj_json_int "$_st" workMode 512)"
    case "$_mode" in
      1) yj_state_set hma_needs_reboot 0
         yj_state_set hma_runtime_confirmed 1
         yj_say "  ✓ HMA 服务已加载配置（configVersion=93，workMode=1）"
         yj_say "    $HMA_DATA_DIR"
         return 0 ;;
      4) yj_state_set hma_needs_reboot 1
         yj_warn "  HMA 服务崩溃过（workMode=4）—— 建议重写配置并重启"
         return 1 ;;
      *)
         yj_state_set hma_needs_reboot 0
         yj_say "  ℹ HMA workMode=${_mode:-?}（配置正确，服务按需加载）"
         return 0 ;;
    esac
  fi

  yj_state_set hma_needs_reboot 0
  yj_say "  ✓ HMA 配置已就位且 configVersion=93（$HMA_CFG），服务重启后加载"
  return 0
}

yj_stage_modules() {
  yj_say "──────── 阶段1. 刷入核心模块 ────────"

  if [ ! -d "$YJ_PAYLOAD" ]; then
    yj_err "payload 目录不存在：$YJ_PAYLOAD"
    return 1
  fi

  yj_build_plan | while IFS='|' read -r _pat _id _name; do
    [ -n "$_id" ] || continue

    if [ "$_pat" = "!FUSEHIDE!" ]; then
      _fh="$(yj_payload_file 'FuseHide_*.apk')"
      if [ -z "$_fh" ]; then
        yj_warn "  FuseHide：payload 内无文件"
        continue
      fi
      if yj_is_legacy_kernel; then
        yj_say "  ⏭ FuseHide：4.x/5.4 内核不适配"
        continue
      fi

      _fwhy="$(yj_should_install zygisk_fusehide "$_fh")"
      if [ $? -ne 0 ]; then
        yj_say "  ✓ FuseHide 模块：$_fwhy"
      else
        yj_say "  → 刷入 FuseHide 模块 (zygisk_fusehide)：$_fwhy ..."
        if yj_install_module "$_fh"; then
          if yj_module_installed "zygisk_fusehide"; then
            yj_say "  ✓ FuseHide 模块刷入成功"
          else
            yj_warn "  FuseHide 模块刷入命令成功，但未检测到模块目录"
          fi
        else
          yj_err "  FuseHide 模块刷入失败"
        fi
      fi

      yj_say "  → 安装/更新 FuseHide 配置界面 ..."
      if yj_install_apk "$_fh"; then
        yj_say "  ✓ FuseHide 配置界面就绪"
      else
        yj_warn "  FuseHide 配置界面未装上（不影响隐藏功能，可用 pm install 手动补）"
      fi
      continue
    fi

    _why_inst="$(yj_should_install "$_id" '')"
    _need_inst=$?
    if [ "$_pat" = "@PATHMASK@" ]; then
      _zip="$(yj_pathmask_zip)"
    else
      _zip="$(yj_payload_file "$_pat")"
    fi
    if [ -n "$_zip" ]; then
      _why_inst="$(yj_should_install "$_id" "$_zip")"
      _need_inst=$?
    fi

    _why="$(yj_plan_skip_reason "$_id" 2>/dev/null || true)"
    if [ -n "$_why" ]; then
      yj_say "  ⏭ $_name：$_why"
      continue
    fi

    if [ -z "$_zip" ]; then
      if [ "$_pat" = "@PATHMASK@" ]; then
        yj_say "  ⏭ PathMask：无法匹配内核 $(yj_kernel 2>/dev/null)"
      else
        yj_warn "  $_name：payload 内无匹配包 $_pat"
      fi
      continue
    fi

    if [ "$_need_inst" -ne 0 ]; then
      yj_say "  ✓ $_name：$_why_inst"
      continue
    fi

    if [ "$_id" = "nomount" ]; then
      yj_say "  → 刷入 $_name ($_id)：$_why_inst ...（最后一个：装好即生效）"
    else
      yj_say "  → 刷入 $_name ($_id)：$_why_inst ..."
    fi
    if yj_install_module "$_zip"; then
      if yj_module_installed "$_id"; then
        yj_say "  ✓ $_name 刷入成功"
      else
        yj_warn "  $_name 刷入命令成功，但未检测到模块目录"
      fi
    else
      yj_err "  $_name 刷入失败"
    fi

    if [ "$_id" = "pathmask" ]; then
      yj_pathmask_config || yj_warn "PathMask 配置写入不完整，可在 WebUI 补"
    fi
  done

  _miss_n=0
  yj_build_plan | while IFS='|' read -r _pat _id _name; do
    [ -n "$_id" ] || continue
    if [ "$_id" = "zygisk_fusehide" ]; then
      yj_module_installed "zygisk_fusehide" && continue
      yj_is_legacy_kernel && continue
    else
      yj_module_installed "$_id" && continue
      _why="$(yj_plan_skip_reason "$_id" 2>/dev/null || true)"
      [ -n "$_why" ] && continue
    fi
    yj_warn "  $_name 未安装成功"
    printf 'x' >>"$YJ_STATE_D/.missmark" 2>/dev/null
  done

  if [ -s "$YJ_STATE_D/.missmark" ]; then
    _miss_n="$(wc -c <"$YJ_STATE_D/.missmark" 2>/dev/null)"
    rm -f "$YJ_STATE_D/.missmark" 2>/dev/null
    yj_say ""
    yj_err "有 $_miss_n 个模块未成功刷入。可按【操作】重跑（幂等）。"
    return 1
  fi
  rm -f "$YJ_STATE_D/.missmark" 2>/dev/null

  yj_say ""
  yj_say "✓ 阶段1完成：模块已全部刷入"
  return 0
}

yj_pathmask_config() {
  _md="$(yj_module_dir pathmask)"
  if [ -z "$_md" ]; then
    yj_warn "PathMask 未安装，跳过其配置"
    return 0
  fi
  if yj_is_legacy_kernel; then
    yj_say "  ℹ 4.x/5.4 内核：跳过 PathMask 配置"
    return 0
  fi

  yj_say "  → PathMask 配置"
  _d="$PATHMASK_DIR"
  if ! mkdir -p "$_d" 2>/dev/null; then
    if [ -d "$_d" ]; then
      yj_say "  ℹ $_d 已存在，跳过创建"
    else
      yj_warn "  无法创建 $_d"
      return 1
    fi
  fi
  chmod 0700 "$_d" 2>/dev/null

  cat >"$_d/target_path.conf" <<'EOF'
/dev/cpuset/scene-daemon
dir:/dev/???/scene_mode_category
EOF

  printf 'deny\n'        >"$_d/scope_mode.conf"
  printf '1\n'           >"$_d/hide_dirents.conf"
  printf '1\n'           >"$_d/enable_syscall_hooks.conf"
  printf '1\n'           >"$_d/auto_scene_debugfs.conf"
  printf '60\n'          >"$_d/wait_seconds.conf"
  printf 'passthrough\n' >"$_d/write_op_policy.conf"
  printf '1\n'           >"$_d/procguard.conf"

  cat >"$_d/deny_packages.conf" <<'EOF'
com.chunqiunativecheck
com.eltavine.duckdetector
luna.safe.luna
me.garfieldhan.holmes
EOF

  : >"$_d/allow_packages.conf"
  : >"$_d/allow_uids.conf"
  printf '0\n1000\n2000\n' >"$_d/allow_system_uids.conf"

  _n=0
  for _f in target_path.conf scope_mode.conf hide_dirents.conf enable_syscall_hooks.conf \
            auto_scene_debugfs.conf procguard.conf deny_packages.conf wait_seconds.conf \
            write_op_policy.conf allow_packages.conf allow_uids.conf allow_system_uids.conf; do
    [ -f "$_d/$_f" ] || continue
    if cp -f "$_d/$_f" "$_md/$_f" 2>/dev/null; then
      _n=$((_n + 1))
    fi
  done

  yj_say "  ✓ PathMask 配置已写入 $_d（并回填模块目录 $_n 个 conf）"
  yj_state_set pathmask_done 1
  return 0
}

yj_stage_config() {
  yj_say "──────── 阶段2. 参数配置 ────────"
  _bad=0
  yj_cfg_zygisknext    || _bad=$((_bad + 1))
  yj_cfg_hma           || _bad=$((_bad + 1))
  yj_cfg_pathmask      || _bad=$((_bad + 1))
  yj_cfg_teesim        || _bad=$((_bad + 1))
  yj_cfg_fgetpriority  || _bad=$((_bad + 1))
  yj_cfg_susfs         || _bad=$((_bad + 1))
  yj_cfg_duck          || _bad=$((_bad + 1))
  yj_cfg_pif           || _bad=$((_bad + 1))
  yj_cfg_lsposed       || _bad=$((_bad + 1))
  if [ "$_bad" -gt 0 ]; then
    yj_say "⚠️  参数配置完成，但有 $_bad 项未成功（多为守护进程未就绪）"
    yj_say "    本模块会在下次开机自动重试未完成项（已成功的不重复写）"
    return 1
  fi
  yj_say "✓ 参数配置完成"
  return 0
}

yj_cfg_zygisknext() {
  _md="$(yj_module_dir zygisksu)"
  if [ -z "$_md" ]; then
    yj_warn "Zygisk Next 未安装，跳过其配置"
    return 0
  fi
  yj_say "  → Zygisk Next 配置"
  mkdir -p "$ZYGISKSU_DIR" 2>/dev/null
  _ok=1

  _zn_write() {
    mkdir -p "$ZYGISKSU_DIR" 2>/dev/null
    printf '%s' "$2" >"$ZYGISKSU_DIR/$1" 2>/dev/null || return 1
    chmod 0600 "$ZYGISKSU_DIR/$1" 2>/dev/null
    [ "$(cat "$ZYGISKSU_DIR/$1" 2>/dev/null)" = "$2" ]
  }

  if _zn_write denylist_enforce 2; then
    yj_say "    ✓ 排除列表策略 = 仅还原挂载（denylist_enforce=2）"
  else
    yj_warn "    写入 denylist_enforce 失败"
    _ok=0
  fi
  if _zn_write memory_type 1; then
    yj_say "    ✓ 使用匿名内存（memory_type=1）"
  else
    yj_warn "    写入 memory_type 失败"
    _ok=0
  fi
  if _zn_write linker 1; then
    yj_say "    ✓ 使用 Zygisk Next 链接器（linker=1）"
  else
    yj_warn "    写入 linker 失败"
    _ok=0
  fi
  if [ -f "$ZYGISKSU_DIR/denylist_policy" ]; then
    rm -f "$ZYGISKSU_DIR/denylist_policy" 2>/dev/null
    yj_say "    ✓ 排除列表语义 = 黑名单（已清除旧的 whitelist 标记）"
  else
    yj_say "    ✓ 排除列表语义 = 黑名单（default，无需写文件）"
  fi

  _zd="$_md/bin/zygiskd"
  _zn_cli() {
    [ -x "$_zd" ] || return 1
    "$_zd" "$@" >/dev/null 2>&1
    _r=$?
    [ "$_r" -eq 0 ] || [ "$_r" -eq 1 ]
  }

  if _zn_cli status; then
    yj_say "    ✓ 守护进程在线，同步一次立即生效"
    _zn_cli enforce-denylist just_umount
    _zn_cli memory-type anonymous
    _zn_cli linker builtin
    _zn_cli denylist-policy default
    _st="$("$_zd" status 2>/dev/null)"
    case "$_st" in
      *"enforce_denylist=2"*) yj_say "    ✓ 读回确认 enforce_denylist=2" ;;
      *enforce_denylist=*)    yj_say "    ℹ 已设置（status: $(printf '%s' "$_st" | tr '\n' ' ')）" ;;
      *)                      yj_say "    ℹ 文件已就位（status 未回显该字段）" ;;
    esac
  else
    yj_say "    ℹ 守护进程未在线；文件已就位，下次开机会由 zygiskd 载入"
  fi

  if [ "$(cat "$ZYGISKSU_DIR/denylist_enforce" 2>/dev/null)" = "2" ] \
     && [ "$(cat "$ZYGISKSU_DIR/memory_type" 2>/dev/null)" = "1" ] \
     && [ "$(cat "$ZYGISKSU_DIR/linker" 2>/dev/null)" = "1" ]; then
    [ "$_ok" = "1" ] && yj_state_set zygisknext_done 1
    return 0
  fi
  yj_warn "    配置未全部落盘"
  return 1
}

yj_cfg_hma() {
  _md="$(yj_module_dir hma_oss_zygisk)"
  if [ -z "$_md" ]; then
    yj_warn "HMA-OSS 未安装，跳过其配置"
    return 0
  fi
  yj_say "  → HMA-OSS 配置校验"

  _src="$(yj_payload_file 'HMA-OSS_config_*.json')"
  if [ -z "$_src" ]; then
    yj_warn "    payload 内无 HMA 预设配置"
    return 0
  fi

  if command -v am >/dev/null 2>&1; then
    am force-stop "$HMA_PKG" >/dev/null 2>&1
  fi

  _need_write=0
  if ! yj_hma_locate >/dev/null 2>&1 || [ ! -s "$HMA_CFG" ]; then
    _need_write=1
  elif [ -n "$(yj_sha1 "$_src")" ] && [ "$(yj_state_get hma_cfg_sha)" != "$(yj_sha1 "$_src")" ]; then
    _need_write=1
  fi

  if [ "$_need_write" = "1" ]; then
    yj_say "    ℹ 配置缺失或与预设不一致，现在写入"
    yj_hma_early || true
    yj_state_set hma_selfheal_try 0
  fi

  if ! yj_hma_locate >/dev/null 2>&1 || [ ! -s "$HMA_CFG" ]; then
    yj_warn "    HMA 配置未能写入：请打开 HMA → 导入配置 → 选 Download/ 里的 json"
    return 1
  fi
  yj_say "    ✓ 配置就位：$HMA_CFG"

  if yj_hma_verify; then
    yj_state_set hma_done 1
    yj_say "  ✓ HMA 预设配置已生效（不用手动导入）"
    return 0
  fi

  _try="$(yj_state_get hma_selfheal_try 0)"
  case "$_try" in ''|*[!0-9]*) _try=0 ;; esac
  if [ "$_try" -ge 1 ]; then
    yj_warn "  已重启过一次仍未加载，请打开 HMA → 导入配置 → 选 Download/ 里的 json"
    return 1
  fi

  if [ "$(yj_state_get hma_auto_reboot 1)" = "1" ]; then
    yj_state_set hma_selfheal_try $((_try + 1))
    yj_say "  ℹ 需要重启一次让 HMA 服务加载新配置"
    yj_say "    （不想要自动重启：sh action.sh noautoreboot 1）"
    yj_state_set hma_reboot_pending 1
  else
    yj_warn "  已禁用自动重启：请手动重启一次"
  fi
  return 1
}

yj_cfg_pathmask() { yj_pathmask_config; }

yj_cfg_teesim() {
  _md="$(yj_module_dir teesim)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ 无 TEESimulator，跳过"
    return 0
  fi
  yj_say "  → TEESimulator 配置"

  _dir="$TEESIM_DIR"
  _cfg="$_dir/config.json"
  mkdir -p "$_dir" 2>/dev/null

  _apps="$(yj_teesim_app_scope 2>/dev/null)"
  if [ -z "$_apps" ]; then
    yj_err "    无法枚举已安装应用（packages.list / cmd / pm 均不可用）"
    yj_err "    已放弃写入 config.json，避免作用域被写成错误的占位列表"
    yj_err "    请在 TEESimulator WebUI 内点「全选」，本模块重启后会再试"
    return 1
  fi
  _n="$(printf '%s\n' "$_apps" | grep -c . 2>/dev/null)"
  [ -n "$_n" ] || _n=0

  if [ -f "$_cfg" ]; then
    _exist="$(yj_teesim_cfg_apps_count "$_cfg" 2>/dev/null)"
    if [ -n "$_exist" ] && [ "$_exist" = "$_n" ]; then
      yj_say "    ℹ 作用域已是 $_n 个应用，无需重写"
      yj_state_set teesim_done 1
      return 0
    fi
    yj_say "    现有作用域 $_exist 项、应为 $_n 项（占位或不完整），重新写入"
  fi

  _kb="keybox.xml"
  if [ ! -f "$_dir/keybox.xml" ]; then
    if [ -f "${YJ_PREFIX}/data/adb/tricky_store/keybox.xml" ]; then
      cp -f "${YJ_PREFIX}/data/adb/tricky_store/keybox.xml" "$_dir/keybox.xml" 2>/dev/null \
        && yj_say "    ✓ 已从 Tricky Store 借用 keybox.xml"
    fi
  fi

  _tmp="$_cfg.tmp.$$"
  {
    printf '{\n'
    printf '  "version": 1,\n'
    printf '  "profiles": {\n'
    printf '    "default": {\n'
    printf '      "keybox": "%s",\n' "$_kb"
    printf '      "mode": "patch",\n'
    printf '      "patchLevel": { "system": "system_property", "vendor": "system_property", "boot": "system_property" },\n'
    printf '      "osVersion": "system_property",\n'
    printf '      "brand": "",\n'
    printf '      "device": "",\n'
    printf '      "product": "",\n'
    printf '      "manufacturer": "",\n'
    printf '      "model": "",\n'
    printf '      "serial": "",\n'
    printf '      "imei": "",\n'
    printf '      "meid": "",\n'
    printf '      "imei2": "",\n'
    printf '      "autoIncludeNewApps": true,\n'
    printf '      "apps": [\n'
    _first=1
    printf '%s\n' "$_apps" | while IFS= read -r _p; do
      [ -n "$_p" ] || continue
      if [ "$_first" = "1" ]; then
        printf '        "%s"' "$_p"
        _first=0
      else
        printf ',\n        "%s"' "$_p"
      fi
    done
    printf '\n      ]\n'
    printf '    }\n'
    printf '  }\n'
    printf '}\n'
  } >"$_tmp" 2>/dev/null

  if [ -s "$_tmp" ] \
     && grep -q '"profiles"' "$_tmp" 2>/dev/null \
     && grep -q '"default"' "$_tmp" 2>/dev/null \
     && [ "$(grep -c '"apps"' "$_tmp" 2>/dev/null)" = "1" ] \
     && [ "$(yj_teesim_cfg_apps_count "$_tmp" 2>/dev/null)" = "$_n" ] \
     && grep -q '"system": "system_property"' "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_cfg" 2>/dev/null
    chmod 0600 "$_cfg" 2>/dev/null
    yj_state_set teesim_done 1
    yj_say "    ✓ mode=patch，keybox=$_kb，作用域 $_n 个应用（系统 + 用户 全选）"
    yj_say "    ✓ 安全日期 system/vendor/boot/osVersion 全为 system_property"
  else
    rm -f "$_tmp" 2>/dev/null
    yj_err "    config.json 生成或校验失败，已放弃写入（未置完成标记）"
    return 1
  fi
  return 0
}

yj_cfg_fgetpriority() {
  _md="$(yj_module_dir fgetpriority)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ 无 fgetpriority，跳过"
    return 0
  fi
  yj_say "  → fgetpriority 校验"

  if [ ! -f "$_md/ko/fgetpriority.ko" ]; then
    if [ -f "$_md/ko/fgetpriority.ko.try" ]; then
      yj_warn "    本机 KMI 无匹配 .ko（仅有 .ko.try 备用），未自动加载"
    else
      yj_warn "    未找到已选定的 .ko"
    fi
    return 0
  fi
  yj_say "    ✓ 已选定 ko：$(basename "$_md"/ko/fgetpriority.ko)"

  if lsmod 2>/dev/null | grep -q '^fgetpriority '; then
    yj_say "    ✓ 内核模块已加载"
  else
    yj_say "    ℹ 尚未加载（重启后由它自己的 service.sh 载入）"
  fi
  yj_say "    ℹ 由它自己的 service.sh 在开机时 insmod，无需本模块额外配置"
  return 0
}

yj_cfg_susfs() {
  _md="$(yj_module_dir SUSFS-LKM)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ 无 SUSFS LKM，跳过"
    return 0
  fi
  yj_say "  → SUSFS LKM 状态检查"

  if [ -d "/sys/module/susfs_guard_lkm" ]; then
    yj_say "    ✓ susfs_guard_lkm 已加载"
    yj_state_set susfs_ok 1
    return 0
  fi
  if [ -f "${SUSFS_DIR}/state.d/loaded_at" ]; then
    yj_say "    ℹ 上次加载于 $(cat "${SUSFS_DIR}/state.d/loaded_at" 2>/dev/null)，当前未在 sysfs 中"
  fi
  if [ "$(yj_state_get susfs_ok 0)" = "1" ]; then
    yj_say "    ✓ 曾成功加载（本次未检出，交给其自身 service 重试）"
    return 0
  fi
  yj_say "    ℹ 尚未加载：其日志见 Download/SUSFS_日志.txt（内核/页大小不匹配会自动跳过）"
  return 0
}

yj_cfg_duck() {
  _md="$(yj_module_dir duck-toolbox)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ 无 Duck ToolBox，跳过"
    return 0
  fi
  yj_say "  → Duck ToolBox 就位检查"
  mkdir -p "$DUCK_DIR/var" 2>/dev/null
  yj_say "    ℹ 密钥（keybox）与目标列表请在 Duck ToolBox WebUI 内操作"
  yj_say "    ℹ 在线拉取需要能正常访问 GitHub，故保留为手动步骤"
  return 0
}

yj_cfg_pif() {
  _md="$(yj_module_dir playintegrityfix)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ 无 Play Integrity Fix 模块，跳过，见人工清单"
    return 0
  fi
  yj_say "  → Play Integrity Fix 配置"

  for _p in com.google.android.gms com.android.vending com.google.android.apps.walletnfcrel; do
    yj_clear_cache "$_p"
  done

  yj_say "  ℹ 设备指纹需联网拉取（Autopif），已改为手动：见人工清单"

  _dst="$PIF_PROP"
  if [ -f "$_dst" ]; then
    yj_say "    ℹ 已有 $PIF_PROP，保留"
  elif [ -f "$_md/pif.prop" ]; then
    mkdir -p "$(dirname "$_dst")" 2>/dev/null
    if cp -f "$_md/pif.prop" "$_dst" 2>/dev/null; then
      yj_say "    ✓ 已铺底 $PIF_PROP（模块自带值）"
    fi
  fi

  if [ -f "$_dst" ]; then
    for _kv in spoofBuild=true spoofProps=true spoofVendingBuild=true; do
      _k="${_kv%%=*}"
      if grep -q "^${_k}=" "$_dst" 2>/dev/null; then
        sed -i "s|^${_k}=.*|${_kv}|" "$_dst" 2>/dev/null
      else
        printf '%s\n' "$_kv" >>"$_dst" 2>/dev/null
      fi
    done
    yj_say "    ✓ 三个 Spoof 开关已写入（其余保持关闭）"
  fi
  yj_state_set pif_done 1
  return 0
}

yj_cfg_lsposed() {
  _md="$(yj_module_dir zygisk_lsposed)"
  if [ -z "$_md" ]; then
    yj_say "  ℹ LSPosed 未安装，跳过"
    return 0
  fi
  yj_say "  → LSPosed 配置"

  if [ -n "$(yj_module_dir zygisk_fusehide)" ]; then
    yj_say "    ✓ FuseHide 模块已就位（Zygisk 注入，无需 LSPosed 作用域）"
    if [ -f "$(yj_module_dir zygisk_fusehide)/disable" ]; then
      yj_warn "    ⚠ FuseHide 模块被标记为禁用，请删除其 disable 文件"
    fi
  else
    yj_say "    ℹ 未装 FuseHide 模块，跳过"
  fi

  yj_say "    ℹ LSPosed 设置项需手动开启：禁用详细日志 / 输出日志到守护进程 / 状态通知"
  yj_say "    ℹ 并保持「Xposed API 调用保护」关闭"
  return 0
}

yj_stage_final() {
  _ok="$1"
  yj_write_checklist
  _cl_ok=$?
  _hint="$(yj_state_get checklist_hint)"
  [ -n "$_hint" ] || _hint="Download/一键隐藏_人工清单.txt"
  yj_say ""
  if [ "$_cl_ok" != "0" ]; then
    yj_say "⚠️  人工清单生成失败（存储不可写）"
    yj_say "    配置本身已完成，未置「全部完成」，下次开机会重试"
    yj_update_desc "⚠️ 配置完成但清单写入失败，下次开机重试"
    return 1
  fi
  if [ "$_ok" = "1" ]; then
    yj_state_set all_done 1
    yj_say "🎉 全部完成"
    yj_say " 人工清单：$_hint"
    yj_update_desc "✅ 已完成，人工项见 $_hint"
  else
    yj_say "⚠️  已生成清单，但有项目未自动完成"
    yj_say "    未置「全部完成」，下次开机会自动重试未完成项"
    yj_say "    人工清单：$_hint"
    yj_update_desc "⚠️ 部分项待重试（清单：$_hint）"
  fi

  if [ "$(yj_state_get hma_reboot_pending 0)" = "1" ]; then
    yj_state_set hma_reboot_pending 0
    if [ "$(yj_state_get hma_auto_reboot 1)" = "1" ]; then
      yj_say ""
      yj_say "ℹ 配置已全部写入。HMA 需要重启一次才会加载新配置，30 秒后自动重启"
      yj_say "  （不想自动重启：sh action.sh noautoreboot 1，然后自己重启）"
      setsid sh -c 'sleep 30; sync; reboot' \
        </dev/null >/dev/null 2>&1 &
    else
      yj_say ""
      yj_warn "配置已全部写入；已禁用自动重启，请自己重启一次让 HMA 加载配置"
    fi
  fi
  return 0
}

yj_write_checklist() {
  _home="$YJ_HOME/一键隐藏_人工清单.txt"

  _has_fgp=0; _has_duck=0; _has_pif=0; _has_pm=0; _has_tee=0; _has_susfs=0
  [ -n "$(yj_module_dir fgetpriority)" ] && _has_fgp=1
  [ -n "$(yj_module_dir duck-toolbox)" ] && _has_duck=1
  [ -n "$(yj_module_dir playintegrityfix)" ] && _has_pif=1
  [ -n "$(yj_module_dir pathmask)" ] && _has_pm=1
  [ -n "$(yj_module_dir teesim)" ] && _has_tee=1
  [ -n "$(yj_module_dir SUSFS-LKM)" ] && _has_susfs=1

  _body() {
    echo "=================================================="
    echo " 一键隐藏模块 · 剩余人工步骤清单"
    echo " 作者：酷安@KNJ蛙　版本：$(yj_self_version)"
    echo " 生成时间: $(yj_now)"
    echo "=================================================="
    echo ""
    echo "设备: $(getprop ro.product.manufacturer 2>/dev/null) $(getprop ro.product.model 2>/dev/null)"
    echo "内核: $(uname -r 2>/dev/null)"
    echo "KMI : $(yj_kernel 2>/dev/null)"
    echo "Root: $(yj_detect_root)"
    echo ""
    if yj_is_legacy_kernel; then
      echo "⚠️  4.x/5.4 内核：NoMount / FuseHide / PathMask / fgetpriority / SUSFS"
      echo "    均不适配，已自动跳过（教程也明确禁止刷入）。"
      echo ""
    fi
    echo "已自动完成:"
    echo "  [x] 核心模块按教程顺序一次性刷入"
    if [ "$_has_pm" = "1" ] && ! yj_is_legacy_kernel; then
      echo "  [x] PathMask 配置（黑名单 / 遮蔽路径 / syscall）"
    fi
    if [ "$_has_susfs" = "1" ]; then
      echo "  [x] SUSFS LKM 已按内核/页大小匹配安装"
    fi
    if [ "$_has_fgp" = "1" ]; then
      echo "  [x] fgetpriority 就位（隐藏部分 syscall 结果，自带加载脚本）"
    fi
    echo "  [x] Zygisk Next（排除列表=仅还原挂载 / 匿名内存 / ZN 链接器）"
    if [ "$(yj_state_get hma_done)" = "1" ]; then
      echo "  [x] HMA 预设配置已写入并为服务所加载"
      echo "      位置：$(yj_state_get hma_data_dir 见 /data/misc/hide_my_applist_*/config.json)"
    elif [ "$(yj_state_get hma_early_done 0)" = "1" ]; then
      echo "  [x] HMA 预设配置已写入服务端数据目录"
      echo "      位置：$(yj_state_get hma_data_dir 见 /data/misc/hide_my_applist_*/config.json)"
      echo "  [ ] 服务尚未加载 —— 重启一次即可"
    fi
    if [ "$_has_tee" = "1" ]; then
      _tee_ok="$(yj_state_get teesim_done 0)"
      if [ "$_tee_ok" != "1" ] && [ -s "$TEESIM_DIR/config.json" ] \
         && grep -q '"system": "system_property"' "$TEESIM_DIR/config.json" 2>/dev/null; then
        _tee_ok=1
      fi
      if [ "$_tee_ok" = "1" ]; then
        echo "  [x] TEESimulator：作用域全选（系统+用户）+ 安全日期全 system_property"
        if [ -s "$TEESIM_DIR/keybox.xml" ]; then
          echo "  [x] keybox 已就位（$(wc -c <"$TEESIM_DIR/keybox.xml" 2>/dev/null | tr -d ' ') 字节）"
        else
          echo "  [ ] keybox 需自备，见下方待办"
        fi
      else
        echo "  [ ] TEESimulator 作用域未自动写入（枚举失败），见下方待办"
      fi
    fi
    if [ "$_has_pif" = "1" ]; then
      echo "  [x] Play Integrity Fix 三个 Spoof 开关已写入"
      echo "  [ ] 指纹拉取需联网（访问 GitHub），见下方待办"
    fi
    if [ "$_has_duck" = "1" ]; then
      echo "  [ ] Duck ToolBox 密钥（keybox）需联网，见下方待办"
    fi
    echo ""
    echo "--------------------------------------------------"
    echo "还需你手动完成:"
    echo "--------------------------------------------------"
    echo ""
    echo "【1】KernelSU 管理器 → 超级用户，给这三个应用 root 权限："
    echo "        - HMA-OSS"
    echo "        - FuseHide"
    echo "        - Shell"
    echo ""
    echo "【2】KernelSU 管理器 → 设置，打开这两项："
    echo "        - 隐藏 SELinux 修改记录"
    echo "        - 默认卸载模块"
    echo ""
    echo "【3】LSPosed 管理器 → 设置，打开："
    echo "        - 禁用详细日志"
    echo "        - 输出日志到守护进程"
    echo "        - 状态通知"
    echo "     ⚠「Xposed API 调用保护」保持【关闭】"
    echo ""
    echo "【4】FuseHide 配置（可选）："
    echo "       它已作为 Zygisk 模块自动刷入（不需要在 LSPosed 里启用）。"
    echo "       桌面上的 FuseHide 应用是配置界面，打开可设置要隐藏哪些路径。"
    echo "       若应用没装上：adb/终端执行 pm install FuseHide_*.apk 补装即可。"
    echo ""
    _hma_runtime="$(yj_state_get hma_done 0)"
    if [ "$_hma_runtime" != "1" ]; then
      _hma_dir="$(yj_state_get hma_data_dir)"
      [ -n "$_hma_dir" ] || _hma_dir="$(yj_hma_target_dir 2>/dev/null)"
      if [ -n "$_hma_dir" ] && grep -q '"workMode":1' "$_hma_dir/status.json" 2>/dev/null; then
        _hma_runtime=1
      fi
    fi
    if [ "$_hma_runtime" != "1" ]; then
      echo "【5】HMA-OSS 若模板仍为空："
      echo "       本版把配置直接写进了服务端数据目录："
      echo "         /data/misc/hide_my_applist_<名字>/config.json"
      echo "       （/data/system 下的同名目录是遗留位置，服务端会把它迁进 misc）"
      echo "       重启一次服务就会读到。若仍为空，请按顺序检查："
      echo "         1. 该目录下 config.json 是否在，且 configVersion 必须是 93"
      echo "         2. 同目录 status.json 里 workMode 是几（1=已加载，4=崩溃）"
      echo "         3. App 内「导入配置」选 Download/HMA-OSS_config_*.json"
      echo ""
    else
      echo "【5】HMA-OSS 无需操作：配置已在服务端数据目录并已被服务加载。"
      echo "      位置：$(yj_state_get hma_data_dir 见 /data/misc/hide_my_applist_*)"
      echo ""
    fi
    echo "【6】Zygisk Next WebUI 内核对这三项（本模块已自动写入）："
    echo "        - 排除列表策略 = 仅还原挂载"
    echo "        - 使用匿名内存"
    echo "        - 使用 Zygisk Next 链接器"
    echo ""
    if [ "$_has_tee" = "1" ]; then
      if [ -s "$TEESIM_DIR/keybox.xml" ]; then
        echo "【7】TEESimulator：keybox 已就位，无需操作。"
        echo "       作用域与安全日期已自动写好（全选 + system_property）。"
      else
        echo "【7】TEESimulator 自备 keybox（必需）："
        echo "       把 keybox.xml 放到 /data/adb/teesim/ 下"
        echo "       作用域与安全日期已自动写好（全选 + system_property），无需手点"
      fi
      if [ "$(yj_state_get teesim_done)" != "1" ] && [ ! -s "$TEESIM_DIR/config.json" ]; then
        echo "       ⚠ 作用域自动写入失败：请在 TEESimulator WebUI 内点「全选」"
      fi
      echo ""
    fi
    if [ "$_has_duck" = "1" ]; then
      echo "【8】Duck ToolBox 获取密钥："
      echo "       打开 Duck ToolBox WebUI → 选择 keybox 来源 / 拉取"
      echo "       获取过程需要能正常访问 GitHub（网络环境不支持时拉不到）"
      echo ""
    fi
    if [ "$_has_pif" = "1" ]; then
      echo "【9】Play Integrity Fix 设备指纹："
      echo "       触发 PIF 的 action，或等它定时任务自动拉取（Autopif）"
      echo "       三个 Spoof 开关已自动写好，只差拉取指纹"
      echo "       拉取过程同样需要能正常访问 GitHub"
      echo ""
    fi
    if [ "$_has_susfs" = "1" ]; then
      echo "【10】SUSFS LKM："
      echo "       加载状态看 Download/SUSFS_日志.txt"
      echo "       若提示页大小不符，说明本机 16K 内核与模块 4K 编译不兼容，属正常跳过"
      echo ""
    fi
    echo "【11】全部做完后重启一次设备，环境搭建完成。"
    echo ""
    echo "--------------------------------------------------"
    echo " 提示：清单里所有「需要联网」的步骤，都是因为要访问 GitHub。"
    echo "       网络环境打不开 GitHub 时会失败，换个能正常联网的环境再试即可。"
    echo "--------------------------------------------------"
    echo ""
    echo "=================================================="
    echo " 本模块免费发布，禁止倒卖　｜　酷安@KNJ蛙"
    echo " 付费购买 = 被骗，请申请退款并举报"
    echo " 刷机有风险，请先备份数据；作者不承担使用后果"
    echo "=================================================="
  }

  mkdir -p "$YJ_HOME" 2>/dev/null
  _body >"$_home" 2>/dev/null
  [ -s "$_home" ] || { yj_warn "人工清单写入失败（模块目录不可写）"; return 1; }

  _pub=""
  for _d in "$DOWNLOAD_DIR" "$MEDIA_DOWNLOAD_DIR" "${YJ_PREFIX}/data/local/tmp"; do
    mkdir -p "$_d" 2>/dev/null || continue
    _f="$_d/一键隐藏_人工清单.txt"
    cat "$_home" >"$_f" 2>/dev/null || continue
    [ -s "$_f" ] || continue
    chmod 0644 "$_f" 2>/dev/null
    chown 1023:1023 "$_f" 2>/dev/null
    yj_restorecon "$_f"
    [ -z "$_pub" ] && _pub="$_f"
  done

  yj_state_set checklist_home "$_home"
  if [ -n "$_pub" ]; then
    yj_state_set checklist_path "$_pub"
    case "$_pub" in
      */sdcard/Download/*)   yj_state_set checklist_hint "Download/一键隐藏_人工清单.txt" ;;
      */media/0/Download/*)  yj_state_set checklist_hint "Download/一键隐藏_人工清单.txt" ;;
      *)                     yj_state_set checklist_hint "$_pub" ;;
    esac
  else
    yj_state_set checklist_path "$_home"
    yj_state_set checklist_hint "$_home"
  fi
  return 0
}
