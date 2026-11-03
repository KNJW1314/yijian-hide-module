#!/system/bin/sh

YJ_PREFIX="${YJ_PREFIX:-}"
YJ_HOME="${YJ_PREFIX}/data/adb/yijian_hide"
YJ_STATE_D="$YJ_HOME/state.d"
YJ_LOG="$YJ_HOME/run.log"
YJ_ERR="$YJ_HOME/error.txt"
YJ_PAYLOAD="$MODDIR/payload"
YJ_MANUAL="${YJ_PREFIX}/sdcard/Download/一键隐藏_人工清单.txt"

DOWNLOAD_DIR="${YJ_PREFIX}/sdcard/Download"
MEDIA_DOWNLOAD_DIR="${YJ_PREFIX}/data/media/0/Download"

MODULES_DIR="${YJ_PREFIX}/data/adb/modules"
MODULES_UPDATE_DIR="${YJ_PREFIX}/data/adb/modules_update"

PATHMASK_DIR="${YJ_PREFIX}/data/adb/pathmask"
ZYGISKSU_DIR="${YJ_PREFIX}/data/adb/zygisksu"
DUCK_DIR="${YJ_PREFIX}/data/adb/duck-toolbox"
NOMOUNT_DIR="${YJ_PREFIX}/data/adb/nomount"
TEESIM_DIR="${YJ_PREFIX}/data/adb/teesim"
SUSFS_DIR="${YJ_PREFIX}/data/adb/susfs_lkm"
PIF_PROP="${YJ_PREFIX}/data/adb/pif.prop"
LOCAL_TMP="${YJ_PREFIX}/data/local/tmp"

HMA_PKG="org.frknkrc44.hma_oss"

HMA_MISC_ROOT="${YJ_PREFIX}/data/misc"
HMA_SYS_ROOT="${YJ_PREFIX}/data/system"
HMA_DATA_PREFIX="hide_my_applist_"

HMA_DATA_DIR=""
HMA_CFG=""


yj_init() {
  mkdir -p "$YJ_HOME" "$YJ_STATE_D" 2>/dev/null
  yj_upgrade_guard
}

yj_now() { date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-'; }

yj_log() {
  mkdir -p "$YJ_HOME" 2>/dev/null
  printf '[%s] %s\n' "$(yj_now)" "$*" >>"$YJ_LOG" 2>/dev/null
}

yj_say() {
  printf '%s\n' "$*" 2>/dev/null || echo "$*"
  yj_log "$*"
}

yj_warn() { yj_say "⚠️  $*"; }

yj_err() {
  yj_say "❌  $*"
  mkdir -p "$YJ_HOME" 2>/dev/null
  printf '%s  %s\n' "$(yj_now)" "$*" >>"$YJ_ERR" 2>/dev/null
}

yj_show_log() {
  [ -f "$YJ_LOG" ] && tail -n 60 "$YJ_LOG" 2>/dev/null
  [ -f "$YJ_ERR" ] && { echo "--- 错误 ---"; tail -n 20 "$YJ_ERR" 2>/dev/null; }
  return 0
}

yj_self_version() {
  _v=""
  if [ -f "$MODDIR/module.prop" ]; then
    _v="$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)"
  fi
  printf '%s' "$_v"
}

yj_upgrade_guard() {
  _last="$YJ_HOME/installed_version"
  _cur="$(yj_self_version)"
  if [ -z "$_cur" ]; then
    return 0
  fi
  if [ -f "$_last" ] && [ "$(cat "$_last" 2>/dev/null)" = "$_cur" ]; then
    return 0
  fi
  if [ -f "$_last" ]; then
    yj_say "ℹ 检测到模块版本变化（$(cat "$_last" 2>/dev/null) → $_cur），重置阶段进度"
    for _k in phase1_done all_done boot_id_stage1 hma_done pif_done last_step \
              hma_de_done hma_verify_pending hma_rewrite_budget pathmask_done \
              teesim_done zygisknext_done susfs_ok; do
      rm -f "$YJ_STATE_D/$_k" 2>/dev/null
    done
    rm -f "$YJ_MANUAL" 2>/dev/null
  fi
  printf '%s' "$_cur" >"$_last" 2>/dev/null
  return 0
}

yj_state_get() {
  _k="$1"; _def="${2:-}"
  if [ -f "$YJ_STATE_D/$_k" ]; then
    cat "$YJ_STATE_D/$_k" 2>/dev/null
  else
    printf '%s' "$_def"
  fi
}

yj_state_set() {
  _k="$1"; _v="$2"
  if [ -z "$_v" ]; then
    rm -f "$YJ_STATE_D/$_k" 2>/dev/null
    return 0
  fi
  mkdir -p "$YJ_STATE_D" 2>/dev/null
  printf '%s' "$_v" >"$YJ_STATE_D/$_k" 2>/dev/null
  if [ "$(cat "$YJ_STATE_D/$_k" 2>/dev/null)" != "$_v" ]; then
    mkdir -p "$YJ_STATE_D" 2>/dev/null
    printf '%s' "$_v" >"$YJ_STATE_D/$_k" 2>/dev/null
  fi
  [ "$(cat "$YJ_STATE_D/$_k" 2>/dev/null)" = "$_v" ] || return 1
  return 0
}

YJ_NOTICE="免费发布，禁止倒卖｜酷安@KNJ蛙"

yj_update_desc() {
  _d="$1"
  _p="$MODDIR/module.prop"
  [ -f "$_p" ] || return 0
  if grep -q '^description=' "$_p" 2>/dev/null; then
    sed -i "s|^description=.*|description=$_d ｜ $YJ_NOTICE|" "$_p" 2>/dev/null || true
  fi
  return 0
}

yj_detect_root() {
  if [ "$KSU" = "true" ] || [ -x "${YJ_PREFIX}/data/adb/ksud" ]; then
    printf 'ksu'
  elif [ "$APATCH" = "true" ] || [ -x "${YJ_PREFIX}/data/adb/apd" ]; then
    printf 'apatch'
  elif [ -n "$MAGISK_VER_CODE" ] || [ -d "${YJ_PREFIX}/data/adb/magisk" ]; then
    printf 'magisk'
  else
    printf 'unknown'
  fi
}

yj_kernel_ver() {
  uname -r 2>/dev/null | sed -n 's/^\([0-9]*\.[0-9]*\).*/\1/p' | head -n1
}

yj_kernel_branch() {
  uname -r 2>/dev/null | grep -oE 'android[0-9]+' | head -n1
}

yj_kernel() {
  _b="$(yj_kernel_branch)"
  _v="$(yj_kernel_ver)"
  [ -n "$_v" ] || return 1
  if [ -n "$_b" ]; then
    printf '%s-%s' "$_b" "$_v"
  else
    printf '%s' "$_v"
  fi
  return 0
}

yj_is_legacy_kernel() {
  _v="$(yj_kernel_ver)"
  case "$_v" in
    4.*) return 0 ;;
    5.4) return 0 ;;
  esac
  return 1
}

yj_boot_id() {
  _f="${YJ_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
  if [ -f "$_f" ]; then
    _bid="$(head -n1 "$_f" 2>/dev/null)"
    [ -n "$_bid" ] && { printf '%s' "$_bid"; return 0; }
  fi
  _up="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
  case "$_up" in
    ''|*[!0-9]*) printf 'nobootid'; return 0 ;;
  esac
  printf 'up%s' "$((_up / 60))"
}

yj_rebooted_since_stage1() {
  _rec="$(yj_state_get boot_id_stage1)"
  [ -n "$_rec" ] || return 1
  _cur="$(yj_boot_id)"
  [ -n "$_cur" ] || return 1
  [ "$_rec" != "$_cur" ]
}

yj_payload_file() {
  _pat="$1"
  for _f in "$YJ_PAYLOAD"/$_pat; do
    [ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
  done
  printf ''
  return 1
}

yj_pathmask_zip() {
  _br="$(yj_kernel_branch)"
  _v="$(yj_kernel_ver)"
  if [ -n "$_br" ] && [ -n "$_v" ]; then
    _f="$(yj_payload_file "${_br}-${_v}_pathmask-ksu.zip")"
    [ -n "$_f" ] && { printf '%s' "$_f"; return 0; }
  fi
  _n=0; _one=""
  for _c in "$YJ_PAYLOAD"/*-"$_v"_pathmask-ksu.zip; do
    [ -f "$_c" ] || continue
    _n=$((_n + 1)); _one="$_c"
  done
  if [ "$_n" -eq 1 ]; then
    printf '%s' "$_one"
    return 0
  fi
  printf ''
  return 1
}

yj_fgetpriority_supported() {
  yj_is_legacy_kernel && return 1
  _k="$(yj_kernel)" || return 1
  [ -n "$_k" ] || return 1
  _zip="$(yj_payload_file 'fgetpriority*.zip')"
  [ -n "$_zip" ] || return 1
  unzip -l "$_zip" 2>/dev/null | grep -q "ko/${_k}.*_arm64_fgetpriority\.ko"
}

yj_nomount_supported() {
  yj_is_legacy_kernel && return 1
  _k="$(yj_kernel)" || return 1
  [ -n "$_k" ] || return 1
  _zip="$(yj_payload_file '[Nn]o[Mm]ount*.zip')"
  [ -n "$_zip" ] || return 1
  unzip -l "$_zip" 2>/dev/null | grep -q "lkm/nomount-${_k}\.ko"
}

yj_susfs_supported() {
  yj_is_legacy_kernel && return 1
  [ "$(uname -m 2>/dev/null)" = "aarch64" ] || return 1
  _k="$(yj_kernel)" || return 1
  [ -n "$_k" ] || return 1
  _zip="$(yj_payload_file 'SUSFS-LKM_*.zip')"
  [ -n "$_zip" ] || return 1
  unzip -l "$_zip" 2>/dev/null | grep -q "libs/susfs_guard_lkm-${_k}\.ko"
}

yj_fusehide_supported() { yj_is_legacy_kernel && return 1; return 0; }

yj_build_plan() {
  printf '%s\n' "Zygisk-Next-*.zip|zygisksu|Zygisk Next"
  printf '%s\n' "@PATHMASK@|pathmask|PathMask"
  printf '%s\n' "SUSFS-LKM_*.zip|SUSFS-LKM|SUSFS LKM"
  printf '%s\n' "LSPosed-*.zip|zygisk_lsposed|LSPosed"
  printf '%s\n' "HMA-OSS-ZYGISK-*.zip|hma_oss_zygisk|HMA-OSS"
  printf '%s\n' "ZN---Audit-Patch-*.zip|auditpatch|ZN-Audit-Patch"
  printf '%s\n' "Audit-Detect-Pass-*.zip|audit_detect_pass|Audit-Detect-Pass"
  printf '%s\n' "fgetpriority*.zip|fgetpriority|fgetpriority"
  printf '%s\n' "!FUSEHIDE!|zygisk_fusehide|FuseHide"
  printf '%s\n' "duck-toolbox-*.zip|duck-toolbox|Duck ToolBox"
  printf '%s\n' "PlayIntegrityFix_*.zip|playintegrityfix|Play Integrity Fix"
  printf '%s\n' "TEESimulator-*.zip|teesim|TEESimulator"
  printf '%s\n' "[Nn]o[Mm]ount*.zip|nomount|NoMount"
}


yj_prop_get() {
  _pf="$1"; _pk="$2"
  [ -f "$_pf" ] || { printf ''; return 1; }
  sed -n "s/^${_pk}=//p" "$_pf" 2>/dev/null | head -n1 | tr -d '\r'
}

yj_zip_version() {
  _zf="$1"; _zk="${2:-versionCode}"
  [ -f "$_zf" ] || { printf ''; return 1; }
  _zv="$(unzip -p "$_zf" module.prop 2>/dev/null \
         | sed -n "s/^${_zk}=//p" 2>/dev/null | head -n1 | tr -d '\r ')"
  printf '%s' "$_zv"
  return 0
}

yj_should_install() {
  _sid="$1"; _szip="$2"
  _mddir="$(yj_module_dir "$_sid")"

  if [ -z "$_mddir" ]; then
    printf '未安装'
    return 0
  fi

  _newcode="$(yj_zip_version "$_szip" versionCode)"
  _oldcode="$(yj_prop_get "$_mddir/module.prop" versionCode)"
  _newver="$(yj_zip_version "$_szip" version)"
  _oldver="$(yj_prop_get "$_mddir/module.prop" version)"

  _nc=""; _oc=""
  case "$_newcode" in
    ''|*[!0-9]*) ;; *) _nc="$_newcode" ;;
  esac
  case "$_oldcode" in
    ''|*[!0-9]*) ;; *) _oc="$_oldcode" ;;
  esac

  if [ -n "$_nc" ] && [ -n "$_oc" ]; then
    if [ "$_nc" -gt "$_oc" ]; then
      printf '已装 %s → payload %s，覆盖安装' "$_oc" "$_nc"
      return 0
    fi
    if [ "$_nc" -lt "$_oc" ]; then
      printf '已装 %s 比 payload %s 新，不降级' "$_oc" "$_nc"
      return 1
    fi
  fi

  if [ -n "$_newver" ] && [ -n "$_oldver" ]; then
    if [ "$_newver" != "$_oldver" ]; then
      printf '已装 %s → payload %s，覆盖安装' "$_oldver" "$_newver"
      return 0
    fi
    printf '已是最新（%s），跳过' "$_oldver"
    return 1
  fi

  printf '版本信息读不到，按覆盖安装处理'
  return 0
}

yj_plan_skip_reason() {
  _id="$1"
  case "$_id" in
    pathmask)
      _z="$(yj_pathmask_zip)" || true
      if [ -z "$_z" ]; then
        printf '无法安全匹配内核 %s' "$(yj_kernel 2>/dev/null)"
        return 0
      fi
      return 1 ;;
    SUSFS-LKM)
      if yj_is_legacy_kernel; then
        printf '4.x/5.4 内核不适配'
        return 0
      fi
      if ! yj_susfs_supported; then
        printf 'SUSFS 无 %s 内核模块（或非 aarch64）' "$(yj_kernel 2>/dev/null)"
        return 0
      fi
      return 1 ;;
    nomount)
      if yj_is_legacy_kernel; then
        printf '4.x/5.4 内核不适配'
        return 0
      fi
      if ! yj_nomount_supported; then
        printf 'NoMount 无 %s 内核模块' "$(yj_kernel 2>/dev/null)"
        return 0
      fi
      if [ "$(yj_detect_root)" = "magisk" ]; then
        printf 'NoMount 仅支持 KernelSU / APatch'
        return 0
      fi
      return 1 ;;
    fgetpriority)
      if yj_is_legacy_kernel; then
        printf '4.x/5.4 内核不适配'
        return 0
      fi
      if ! yj_fgetpriority_supported; then
        printf '无 %s 的 .ko（仅适配 A12-A17 官方 KMI）' "$(yj_kernel 2>/dev/null)"
        return 0
      fi
      return 1 ;;
  esac
  return 1
}

yj_module_installed() {
  _id="$1"
  [ -d "$MODULES_DIR/$_id" ] || [ -d "$MODULES_UPDATE_DIR/$_id" ]
}

yj_module_dir() {
  _id="$1"
  if [ -d "$MODULES_DIR/$_id" ]; then
    printf '%s' "$MODULES_DIR/$_id"
  elif [ -d "$MODULES_UPDATE_DIR/$_id" ]; then
    printf '%s' "$MODULES_UPDATE_DIR/$_id"
  else
    printf ''
    return 1
  fi
}

yj_install_module() {
  _zip="$1"
  [ -f "$_zip" ] || { yj_err "找不到模块包：$_zip"; return 1; }

  _impl="$(yj_detect_root)"
  case "$_impl" in
    ksu)
      _ksud=""
      [ -x "${YJ_PREFIX}/data/adb/ksud" ] && _ksud="${YJ_PREFIX}/data/adb/ksud"
      [ -n "$_ksud" ] || _ksud="$(command -v ksud 2>/dev/null)"
      [ -n "$_ksud" ] || { yj_err "找不到 ksud"; return 1; }
      _out="$("$_ksud" module install "$_zip" 2>&1)"; _rc=$? ;;
    apatch)
      _apd=""
      [ -x "${YJ_PREFIX}/data/adb/apd" ] && _apd="${YJ_PREFIX}/data/adb/apd"
      [ -n "$_apd" ] || _apd="$(command -v apd 2>/dev/null)"
      [ -n "$_apd" ] || { yj_err "找不到 apd"; return 1; }
      _out="$("$_apd" module install "$_zip" 2>&1)"; _rc=$? ;;
    magisk)
      _out="$(magisk --install-module "$_zip" 2>&1)"; _rc=$? ;;
    *)
      yj_err "无法识别 Root 管理器"
      return 1 ;;
  esac

  [ -n "$_out" ] && printf '%s\n' "$_out" | while IFS= read -r _l; do [ -n "$_l" ] && yj_log "    $_l"; done
  return $_rc
}

yj_install_apk() {
  _apk="$1"
  [ -f "$_apk" ] || { yj_err "找不到 APK：$_apk"; return 1; }
  _out="$(pm install -r "$_apk" 2>&1)"; _rc=$?
  [ -n "$_out" ] && yj_log "    $_out"
  if [ $_rc -ne 0 ]; then
    case "$_out" in
      *ALREADY_EXISTS*|*INSTALL_FAILED_VERSION_DOWNGRADE*|*INSTALL_FAILED_ALREADY_EXISTS*) return 0 ;;
    esac
  fi
  return $_rc
}

yj_app_uid_fast() {
  _pkg="$1"
  _pl="${YJ_PREFIX}/data/system/packages.list"
  if [ -f "$_pl" ]; then
    _u="$(awk -v p="$_pkg" '$1 == p { print $2; exit }' "$_pl" 2>/dev/null)"
    case "$_u" in
      ''|*[!0-9]*|0) ;;
      *) printf '%s' "$_u"; return 0 ;;
    esac
  fi
  if command -v stat >/dev/null 2>&1; then
    for _probe in "${YJ_PREFIX}/data/user/0/${_pkg}" "${YJ_PREFIX}/data/data/${_pkg}" \
                  "${YJ_PREFIX}/data/user_de/0/${_pkg}"; do
      [ -d "$_probe" ] || continue
      _u="$(stat -c %u "$_probe" 2>/dev/null)"
      case "$_u" in
        ''|*[!0-9]*|0) ;;
        *) printf '%s' "$_u"; return 0 ;;
      esac
    done
  fi
  printf ''
  return 1
}

yj_app_uid() {
  _pkg="$1"
  _pl="${YJ_PREFIX}/data/system/packages.list"
  if [ -f "$_pl" ]; then
    awk -v p="$_pkg" '$1 == p { print $2; exit }' "$_pl" 2>/dev/null
    return 0
  fi
  pm list packages -U 2>/dev/null | sed -n "s/^package:${_pkg} uid:\([0-9]*\).*/\1/p" | head -n1
}

yj_pkg_installed() {
  _pkg="$1"
  [ -n "$(yj_app_uid "$_pkg")" ] && return 0
  pm list packages 2>/dev/null | grep -q "^package:${_pkg}$"
}

yj_all_apps() {
  _pl="${YJ_PREFIX}/data/system/packages.list"
  if [ -f "$_pl" ]; then
    awk '$2 + 0 >= 10000 { print $1 }' "$_pl" 2>/dev/null | sort -u
    return 0
  fi
  _out="$(cmd package list packages -s 2>/dev/null; cmd package list packages -3 2>/dev/null)"
  if [ -z "$_out" ]; then
    _out="$(pm list packages -s 2>/dev/null; pm list packages -3 2>/dev/null)"
  fi
  printf '%s\n' "$_out" | sed -n 's/^package:\([A-Za-z0-9_.]*\)$/\1/p' | sort -u
}

yj_teesim_app_scope() {
  PATH="/system/bin:/system/xbin${PATH:+:$PATH}"
  export PATH

  _pl="${YJ_PREFIX}/data/system/packages.list"
  if [ -f "$_pl" ]; then
    _out="$(awk '$2 + 0 >= 10000 { print $1 }' "$_pl" 2>/dev/null | sort -u)"
    if [ -n "$_out" ]; then
      printf '%s\n' "$_out"
      return 0
    fi
  fi

  _out="$(cmd package list packages -s 2>/dev/null; cmd package list packages -3 2>/dev/null)"
  _out="$(printf '%s\n' "$_out" | sed -n 's/^package:\([A-Za-z0-9_.]*\)$/\1/p' | sort -u)"
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi

  _out="$(pm list packages -s 2>/dev/null; pm list packages -3 2>/dev/null)"
  _out="$(printf '%s\n' "$_out" | sed -n 's/^package:\([A-Za-z0-9_.]*\)$/\1/p' | sort -u)"
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
    return 0
  fi

  return 1
}

yj_teesim_cfg_apps_count() {
  _f="$1"
  [ -f "$_f" ] || return 1
  _q="$(tr -d '\n' <"$_f" 2>/dev/null \
        | cut -d']' -f1 \
        | sed -n 's/.*"apps"[[:space:]]*:[[:space:]]*\[//p' \
        | grep -o '"' | wc -l)"
  _c=$((_q / 2))
  printf '%s' "$_c"
  return 0
}

yj_json_int() {
  _jf="$1"; _jk="$2"; _jmax="${3:-8192}"
  [ -f "$_jf" ] || return 1
  [ -n "$_jk" ] || return 1

  _jblk=$(( _jmax / 1024 ))
  [ "$_jblk" -ge 1 ] || _jblk=1
  _jbuf="$(dd if="$_jf" bs=1024 count="$_jblk" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$_jbuf" ] || return 1

  case "$_jbuf" in
    *"\"$_jk\""*) ;;
    *) return 1 ;;
  esac
  _jrest="${_jbuf#*\"$_jk\"}"

  case "$_jrest" in
    *:*) _jrest="${_jrest#*:}" ;;
    *) return 1 ;;
  esac

  _jnum=""
  while : ; do
    [ -n "$_jrest" ] || break
    _jc="${_jrest%"${_jrest#?}"}"
    case "$_jc" in
      0|1|2|3|4|5|6|7|8|9) _jnum="$_jnum$_jc"; _jrest="${_jrest#?}" ;;
      *) break ;;
    esac
  done

  [ -n "$_jnum" ] || return 1
  printf '%s' "$_jnum"
  return 0
}

yj_prop_set() {
  _k="$1"; _v="$2"
  if command -v resetprop >/dev/null 2>&1; then
    resetprop -n "$_k" "$_v" 2>/dev/null && return 0
  fi
  if command -v setprop >/dev/null 2>&1; then
    setprop "$_k" "$_v" 2>/dev/null && return 0
  fi
  return 1
}

yj_clear_cache() {
  _pkg="$1"
  rm -rf "${YJ_PREFIX}/data/data/$_pkg/cache" \
         "${YJ_PREFIX}/data/user/0/$_pkg/cache" 2>/dev/null
  rm -rf "${YJ_PREFIX}/data/data/$_pkg/code_cache" \
         "${YJ_PREFIX}/data/user/0/$_pkg/code_cache" 2>/dev/null
  return 0
}

yj_hma_locate() {
  HMA_DATA_DIR=""
  HMA_CFG=""
  for _d in "$HMA_MISC_ROOT"/${HMA_DATA_PREFIX}*; do
    [ -d "$_d" ] || continue
    if [ -f "$_d/config.json" ]; then
      HMA_DATA_DIR="$_d"; HMA_CFG="$_d/config.json"
      return 0
    fi
  done
  for _d in "$HMA_MISC_ROOT"/${HMA_DATA_PREFIX}*; do
    [ -d "$_d" ] || continue
    HMA_DATA_DIR="$_d"; HMA_CFG="$_d/config.json"
    return 0
  done
  for _d in "$HMA_SYS_ROOT"/${HMA_DATA_PREFIX}*; do
    [ -d "$_d" ] || continue
    HMA_DATA_DIR="$_d"; HMA_CFG="$_d/config.json"
    return 0
  done
  return 1
}

yj_hma_target_dir() {
  if yj_hma_locate >/dev/null 2>&1 && [ -n "$HMA_DATA_DIR" ]; then
    printf '%s' "$HMA_DATA_DIR"
    return 0
  fi
  _rec="$(yj_state_get hma_data_dir 2>/dev/null)"
  case "$_rec" in
    */${HMA_DATA_PREFIX}*) printf '%s' "$_rec"; return 0 ;;
  esac
  printf '%s/%s%s' "$HMA_MISC_ROOT" "$HMA_DATA_PREFIX" "$(yj_rand_lower16)"
  return 0
}

yj_rand_lower16() {
  _s=""
  if [ -r /dev/urandom ]; then
    _s="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  case "$_s" in
    ????????????????????????????????)
      _o=""
      _i=0
      while [ "$_i" -lt 32 ]; do
        _c="$(printf '%s' "$_s" | cut -c$((_i + 1)))"
        case "$_c" in
          0|1) _o="${_o}a" ;; 2|3) _o="${_o}b" ;; 4|5) _o="${_o}c" ;;
          6|7) _o="${_o}d" ;; 8|9) _o="${_o}e" ;; a) _o="${_o}f" ;;
          b) _o="${_o}g" ;;   c) _o="${_o}h" ;;   d) _o="${_o}i" ;;
          e) _o="${_o}j" ;;   f) _o="${_o}k" ;;
          *) _o="${_o}x" ;;
        esac
        _i=$((_i + 2))
      done
      printf '%s' "$_o"
      return 0 ;;
  esac
  printf 'yj%s%s' "$(date +%s 2>/dev/null | tail -c 5)" "abcdefghij"
}


yj_restorecon() {
  [ -n "$1" ] || return 0
  if command -v restorecon >/dev/null 2>&1; then
    restorecon "$@" >/dev/null 2>&1 && return 0
    restorecon -R "$@" >/dev/null 2>&1 && return 0
  fi
  if command -v chcon >/dev/null 2>&1; then
    _lbl="u:object_r:app_data_file:s0:c512,c768"
    for _p in "$@"; do
      [ -e "$_p" ] || continue
      chcon -R "$_lbl" "$_p" >/dev/null 2>&1 && return 0
      chcon "$_lbl" "$_p" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

yj_own_app_file() {
  _owner="$1"; _dir="$2"; _file="$3"
  [ -d "$_dir" ] && {
    [ -n "$_owner" ] && chown "$_owner:$_owner" "$_dir" 2>/dev/null
    chmod 0771 "$_dir" 2>/dev/null
    yj_restorecon "$_dir"
  }
  [ -f "$_file" ] && {
    [ -n "$_owner" ] && chown "$_owner:$_owner" "$_file" 2>/dev/null
    chmod 0660 "$_file" 2>/dev/null
    yj_restorecon "$_file"
  }
  return 0
}

yj_bootclasspath() {
  if [ -f "${YJ_PREFIX}/data/adb/lspd/config" ]; then
    sed -n 's/^bootclasspath=//p' "${YJ_PREFIX}/data/adb/lspd/config" 2>/dev/null
  fi
}

yj_lspctl() {
  for c in "${YJ_PREFIX}/data/adb/lspd/lspctl" \
           "${YJ_PREFIX}/data/adb/modules/zygisk_lsposed/lspctl" \
           "${YJ_PREFIX}/data/adb/modules/zygisk_lsposed/bin/lspctl"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

yj_sha1() {
  _f="$1"
  [ -f "$_f" ] || return 1
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$_f" 2>/dev/null | awk '{print $1}'
    return 0
  fi
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$_f" 2>/dev/null | awk '{print $1}'
    return 0
  fi
  cksum "$_f" 2>/dev/null | awk '{print $1"-"$2}'
}

yj_flavor() {
  if [ -n "$(yj_payload_file 'OhMyKeymint-*.zip')" ] || [ -n "$(yj_payload_file 'specter-*.zip')" ]; then
    printf 'omy 版（Specter + OhMyKeymint）'
  else
    printf '经典版（DuckToolBox + PIF）'
  fi
}

yj_show_status() {
  yj_say "===== 一键隐藏模块 · 状态 ====="
  case "$(yj_current_phase)" in
    0) yj_say "进度: 阶段1未完成（需刷入模块）" ;;
    1) yj_say "进度: 阶段1已完成，等待重启后自动执行阶段2" ;;
    2) yj_say "进度: 阶段1已完成，当前应执行【阶段2：参数配置】" ;;
    9) yj_say "进度: 全部完成（阶段1+阶段2）" ;;
  esac
  _impl="$(yj_detect_root)"
  case "$_impl" in ksu) _impl="KernelSU";; apatch) _impl="APatch";; magisk) _impl="Magisk";; esac
  yj_say "Root 管理器: $_impl"
  yj_say "内核: $(uname -r 2>/dev/null)"
  yj_say "KMI : $(yj_kernel 2>/dev/null)"
  if yj_is_legacy_kernel; then
    yj_say "⚠️  4.x/5.4 内核：NoMount / FuseHide / PathMask / fgetpriority / SUSFS 均不适配，已自动跳过"
  fi
  yj_say "模块版本: $(yj_self_version)"
  if yj_hma_locate >/dev/null 2>&1 && [ -s "$HMA_CFG" ]; then
    yj_say "HMA 配置: 已就位 $HMA_CFG"
  else
    yj_say "HMA 配置: 未写入（或已被清除残留配置删掉）"
  fi
  yj_say "HMA 待重启生效: $(yj_state_get hma_needs_reboot 0)（1=还需重启一次）"
}
