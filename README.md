# 一键隐藏模块

**作者：酷安@KNJ蛙**　|　**版本：1.9**

把一整篇 Root 隐藏环境搭建教程做成一次刷入的自动化模块：
刷入时按顺序一次性装完全部模块，重启后自动写完所有能自动写的配置，
剩下必须联网（访问 GitHub）或必须手点的项目，整理成清单交给你。

---

## 1.9 新增：WebUI 与四个扩展功能

模块现在带 WebUI 页面（`webroot/index.html`），在 KernelSU / Magisk 的
WebUI 入口里打开即可。四个功能都只做「本地操作」，不联网（除了 keybox 那个下载页）。

### 功能一：keybox 部署

keybox 的下载页 `https://keybox.kowx712.cc/?id=32` 是 T.A.K.R.
（Tricky Addon Keybox Repository）的 SPA，下载走的是
`POST /api/keyboxes/{id}/download` 并要求 `Cf-Turnstile-Token`。
人机验证脚本绕不过，所以流程是**你手动下载、模块自动部署**：

1. 点「打开 keybox 下载页」→ 浏览器里选 32 号 → 下载
2. 点「检测并部署」→ 模块扫描下载目录，找到合格文件后自动装好
3. 熄屏前不用改名、不用手动复制

不点按钮也行：`service.sh` 开机后会起一个后台 watcher，
每 10 秒扫一次，30 分钟内发现合格 keybox 会自己部署。
不想让它扫：`touch /data/adb/yijian_hide/keybox_watch_off`。

校验逻辑不是「有文件就用」——必须先过四道：
文件大小 200B~200KB、开头是 `<`、不含 `<!doctype html`/`<html`、
同时含 `Keybox`/`keys` 与 `privateKey`/`certificate` 标记。
下载成 HTML 首页是常见假阳性（那个 SPA 首页正好 1598 字节），会被拒掉。

部署前旧 keybox 会备份成 `backup/keybox/keybox-<时间戳>.xml`。

### 功能二：MT2 目录迁移

MT 管理器的自定义 MT2 目录，真实配置位置是：

```
/data/user/0/bin.mt.plus/shared_prefs/bin.mt.plus_preferences.xml
键名：mt2_path
```

> 这个键名之前静态分析找不到 —— MT 用 StringFog 加密了 dex 里的字符串常量，
> `resources.arsc` 里能看到「自定义 MT2 目录」这个设置项，但键名是密文。
> 最终是用户提供的实测脚本确认的，不是猜的。

顺序是**先建新、再搬走旧、最后删空目录**：

1. 建 `/sdcard/Download/MT管理器`（含 `keys/` 与 `keystore/` 子目录）
2. 把旧 `MT2` 目录里的东西搬过来
   - 同名目录 → 递归合并（不能整体跳过，否则 `keys/` 里的密钥全丢）
   - 同名文件 → 改名 `.old` 保留，绝不覆盖
3. 旧目录搬空后删掉；没搬空就保留并警告
4. 写 `mt2_path` → `/sdcard/Download/MT管理器`

写配置做过三件事：先备份、替换已有节点（没有就插到 `</map>` 前）、
写完回读确认恰好一处目标值且 XML 首尾完整。

**改完要强制停止 MT 管理器再重开** —— MT 运行中会用内存里的旧值覆写回去。

### 功能三：清空 logd 尺寸属性

把四个属性置空，让日志缓冲区回到系统默认：

```sh
setprop persist.logd.size ""
setprop persist.logd.size.crash ""
setprop persist.logd.size.system ""
setprop persist.logd.size.main ""
```

### 功能四：关闭 USB 调试

```sh
settings put global adb_enabled 0
settings put secure usb_debugging_enabled 0
settings put global wireless_adb_enabled 0
setprop sys.usb.adb.disabled ""
setprop persist.security.adbinput ""
setprop persist.service.adb.enable ""
setprop persist.security.adbinstall ""
```

> ⚠️ 关掉之后电脑就 adb 连不上了，只能靠手机端操作。WebUI 里点这个按钮会二次确认。

---

## 1.9 新增：系统设置与检测（`lib/sys_ext.sh`）

六个功能，WebUI 里点按钮，或命令行等价调用。

### 功能五：查询电池寿命

读三个节点，缺一个就明确报错，绝不拼假数据：

| 节点 | 含义 | 单位 |
|---|---|---|
| `/sys/class/power_supply/battery/charge_full_design` | 出厂设计容量 | 微安时（÷1000 = mAh） |
| `/sys/class/power_supply/battery/charge_full` | 当前满电容量 | 同上 |
| `/sys/class/power_supply/battery/cycle_count` | 循环次数 | 次 |

百分比按 `当前 × 100 ÷ 设计` 算，先乘后除避免精度丢失。
低于 80% 会额外提示「电池衰减较明显」。

本机实测：5069 mAh 设计 / 3979 mAh 当前 / 10 次循环 / 78%。

```sh
sh action.sh battery-life       # 详细输出
sh action.sh battery-status     # 单行：78:3979/5069
```

### 功能六：打开隐藏 Google 设置

GMS 内置但桌面没暴露的入口：

```sh
am start --user 0 -n com.google.android.gms/com.google.android.gms.app.settings.GoogleSettingsIALink
```

执行前先确认组件存在，不存在就明确报错，不假装成功。

```sh
sh action.sh google-settings
```

### 功能七：电池优化策略（二选一 + 开机自动）

**off = 全部不优化**：全机所有包加进 `deviceidle whitelist`，
三方应用再设 `active` bucket + 放开 `RUN_IN_BACKGROUND` / `RUN_ANY_IN_BACKGROUND`。

**on = 全部优化**：全机所有包移出白名单。

> ⚠️ 影响几百个包，耗时几十秒。执行前自动快照
> `dumpsys deviceidle whitelist` 到 `/data/adb/yijian_hide/backup/deviceidle-<时间>.txt`。

开机自动执行：写进 `/data/adb/yijian_hide/sys.conf` 的 `battery_auto`，
由 `service.sh` 里的 `yj_sys_autorun` 落实。

```sh
sh action.sh battery-opt off        # 全部不优化
sh action.sh battery-opt on         # 全部优化
sh action.sh battery-auto off       # 开机自动不优化
sh action.sh battery-auto none      # 关闭自动
```

### 功能八：色彩饱和度（可自定义 + 开机自动）

> **重要**：网上流传的 `service call SurfaceFlinger 1022 f 200` 在老版本可用，
> **Android 14 上已失效**。实测这台机器上 1022 传 100/150/200/300 全部返回
> `Parcel(NULL)`，且 `dumpsys SurfaceFlinger` 全文 197107 字节里
> `saturation` 出现 **0 次** —— 事务码已被移除。

真正的开关是系统属性：

| 属性 | 默认 | 含义 |
|---|---|---|
| `persist.sys.sf.color_saturation` | `1.0` | 色彩饱和度（本功能改这个） |
| `persist.sys.sf.color_mode` | `0` | 色彩模式（0=NATIVE） |

安全范围 **0.5 ~ 3.0**，超出直接拒绝，防止写坏显示。

`persist.*` 属性重启后保留；SurfaceFlinger 启动时读取，
所以**改完要重启才生效**。

```sh
sh action.sh saturation 1.2         # 设为 1.2
sh action.sh saturation 1.0         # 恢复默认
sh action.sh saturation-status      # 查当前值
sh action.sh saturation-auto 1.3    # 开机自动应用
sh action.sh saturation-auto none   # 关闭自动
```

### 功能九：扫盘漏洞检测

原理：Android 11 起限制 `/sdcard/Android/data` 与 `obb` 的访问。
若系统有漏洞，在路径后拼零宽连接符（U+200D）能绕过限制。

> **重要**：原脚本第一句写着「请不要通过 root 权限执行」，这是对的。
> WebUI 通过 `ksu.exec` 执行时是 `uid=0(root)`，root 能读一切，
> 用它检测必然得出「全部可读 = 有漏洞」的假结论。

实测对照（本机 Android 14）：

```
root  读 /sdcard/Android/data      → 50 项（全读，无意义）
shell 读 /sdcard/Android/data      → Permission denied（安全）
shell 读 /sdcard/Android/data+ZWJ  → Permission denied（安全）
```

所以检测前**主动降权到 `shell`(uid=2000)**：

```sh
su shell -c '<命令>'      # ✓ 能降权，uid 变 2000
su --context u:r:shell:s0 -c '<命令>'   # ✗ 只换 SELinux 域，uid 仍是 0
```

判定：**含 `Permission denied` 或输出为空 = 安全**；只有真读出包名才算漏洞。
降权失败直接报错，绝不在 root 身份下假报「安全」。

四个位置全查：`data`/`obb` × 零宽/正常。

```sh
sh action.sh scan-storage
sh action.sh scan-status
```

### 命令行速查（新增六个）

```sh
sh action.sh battery-life           # 电池寿命详情
sh action.sh battery-status         # 电池单行状态
sh action.sh google-settings        # 打开隐藏 Google 设置
sh action.sh battery-opt off|on     # 电池优化策略
sh action.sh battery-auto none|off|on   # 开机自动电池策略
sh action.sh saturation <值>         # 色彩饱和度
sh action.sh saturation-status      # 当前饱和度
sh action.sh saturation-auto <值>|none  # 开机自动饱和度
sh action.sh scan-storage           # 扫盘漏洞检测
sh action.sh scan-status            # 上次检测结果
```

### 状态字段（`webui_status.sh` 新增 5 项）

`OK=1` 之后追加，向后兼容旧前端：

```
BATTERY=78%(3979mAh)
SATURATION=1.0
BATT_AUTO=none
SAT_AUTO=none
SCAN=safe
```

---

### 命令行也能用

WebUI 只是外壳，下面这些命令等价：

```sh
sh action.sh keybox-open      # 打开下载页
sh action.sh keybox-deploy    # 检测并部署
sh action.sh mt2-migrate      # 迁移 MT2 目录
sh action.sh mt2-path "/xxx"  # 只改配置不动目录
sh action.sh logd-clear       # 清 logd 尺寸
sh action.sh usb-clear        # 关 USB 调试
```

---

---

## 1.9 更新：三个子模块升级

| 模块 | 旧 | 新 |
|---|---|---|
| HMA-OSS Zygisk | future-1e8cb28a | future-1eda3ef1 |
| LSPosed | v2.2.1 (7936) | v2.2.1 (7939) |
| SUSFS LKM | v2.5.0-r18.4 | v2.5.0-r18.8 |

其余 18 个 payload 与全部脚本逐字节比对无变化。旧版包已从 payload 里移除 ——
脚本是用通配符找包的（`SUSFS-LKM_*.zip` / `LSPosed-*.zip` / `HMA-OSS-ZYGISK-*.zip`），
同一个目录留两个候选会让匹配结果不确定。

另：子模块 **hma-uidfake 已替换为 fgetpriority v0.0.2（rawNkprobes）** ——
安装位置（Audit-Detect-Pass 之后、FuseHide 之前）、校验方式（按 KMI 看 `.ko`、看 lsmod）
与其它逻辑都不变，只是换了包和模块 id。它自带 service.sh 在开机时 insmod，不需要本模块额外配置。
**注意**：本模块不负责卸载被换掉的旧模块，刷入新包后请在管理器里手动删掉 `hma-uidfake`。

- **SUSFS r18.8** 成包 SHA256 `43571968DAA03C50BB6FB4571B66FAAE13C4BDA2185699592E7BAA2402274D1F`，
  与本工作区单独打包的成品逐位一致。
- **LSPosed 7939** 的 `module.prop` 依旧被 Deflate64 压缩、`toybox unzip` 读不出，
  仍走「读不到就覆盖安装」。
- **HMA-OSS Zygisk** 的 `configVersion` 仍是 93，10-25 那份预设继续有效。

## 1.9 更新：四个子模块升级

本轮 payload 是上游四个组件同时发新版，模块本体逻辑没动。

| 模块 | 旧 | 新 |
|---|---|---|
| HMA-OSS Zygisk | future-6d6f4684 | future-1e8cb28a |
| LSPosed | v2.2.1 (7933) | v2.2.1 (7936) |
| Duck ToolBox | 0.2.0-Stable (116-canary) | 0.2.1-Stable (137-canary) |
| FuseHide | v191 | v196 |

其余 17 个 payload 文件逐字节比对无变化（含 8 个内核分支的 PathMask 2.8.3、
HMA 预设配置 10-25、NoMount v2.2.0、TEESimulator、SUSFS LKM、PIF、
Zygisk Next、ZN-Audit-Patch、Audit-Detect-Pass、fgetpriority）。

### HMA 预设仍可直接用

升级 HMA-OSS 最容易翻车的是 `configVersion` 变了 —— 预设里写 93，
而新构建要求别的值，整份配置会被拒收（作用域和日期一起失效）。

已逐文件核对 `6d6f4684` → `1e8cb28a` 的源码：

- `common/src/main/java/icu/nullptr/hidemyapplist/common/JsonConfig.kt` 两版完全一致
- `build.gradle.kts` 里 `val configVerCode = 93` 两版相同
- `JsonConfig` 读的是 `BuildConfig.CONFIG_VERSION`，由上面这个值编译注入

所以 10-25 那份预设仍然有效，不需要重新导出。

### LSPosed 依旧走"读不到就覆盖"

v2.2.1 (7936) 的 `module.prop` 仍然是被 Deflate64 压缩的，
`toybox unzip` 读不出来 —— 这正是 `yj_should_install` 第 4 层的预期路径：
任一侧版本读不到就一律覆盖安装，交给 LSPosed 自己的安装器判断。
`lspctl` 和 `module.prop` 仍在压缩包根目录，`yj_cfg_lsposed` 的路径查找不需要改。

### Duck ToolBox 0.2.1 是大版本

上游这次改的是 WebUI 与后端契约（Linux 环境、导入校验、并发日志），
模块里只做"刷入 + 就位检查"，不碰它内部结构，所以代码不用跟进。

---

## 1.8 修复：NoMount 被静默跳过

v2.2.0 起官方把包名从 `nomount-…` 改成了 `NoMount-…`（首字母大写），
而模块里用的匹配模式是 `nomount*.zip`。Linux 的文件通配符**区分大小写**，
于是匹配不到 → `yj_nomount_supported` 返回失败 → 计划里给出
"NoMount 无 xxx 内核模块"的理由 → **直接跳过不装**。

改成大小写都接受：

```sh
yj_payload_file '[Nn]o[Mm]ount*.zip'
```

两个引用点都要改：`yj_nomount_supported()` 里判断内核模块，
以及 `yj_build_plan()` 里输出刷入计划的那一行。

> 这个 bug 的隐蔽之处：日志看起来像"内核不适配"，而不是"找不到安装包"，
> 所以光看输出很难发现是文件名大小写的问题。

## 1.8 同步：NoMount v2.2.0（协议 v22）

上游是一次大版本，`nm_rule_hdr` 16→24 字节、`nm_del_hdr` 10→18 字节。
**v22 的 CLI 与 v21 驱动无法通信**，安装器发现驱动低于 v22 会直接中止。

- 内核模块结构没变：仍是 `lkm/nomount-<kmi>.ko`，`yj_nomount_supported()` 的
  `lkm/nomount-${_k}\.ko` 精确匹配依然成立
- 新增 x86_64 变体 `lkm/nomount-<kmi>-x86_64.ko`，因为 `\.ko` 前要求
  KMI 完整匹配，不会被误取
- 驱动要重启才生效：LKM 模式下新驱动是"下次开机"才加载

上游这次还修了三个真问题：APatch 上规则静默丢失（`metamount.sh` 跑在 LKM
加载之前）、`rmmod` 时 panic（虚拟路径上有打开文件）、`.replace` 带内容导致
bootloop（改成 `--opaque` 语义）。

## 1.8 更新：HMA 预设使用 10-25 版

新的 `HMA-OSS_config_2026-10-25_04.53.15.json` 带来两处实质变化：

- `applyPresets` 新增 **`custom_rom`**
- `extraAppList` 新增 **`bin.mt.plus`**（MT 管理器）

旧的两份预设（10-17 与 10-25）**不能同时放在 payload 里**：
`yj_payload_file` 用的是 shell glob，多个匹配时按字典序取第一个，
`2026-10-17` 排在 `2026-10-25` 前面，结果会用上旧的那份。
所以打包时只保留 10-25 一份。

## 1.7 新增：开机对齐三项安全补丁日期

`post-fs-data.sh` 每次开机执行三行：

```sh
resetprop ro.build.version.security_patch 2026-10-05   # 系统级
resetprop ro.bootimage.build.date 2026-10-05           # boot.img 中的 patch level
resetprop ro.vendor.build.security_patch 2026-10-05    # vendor 层
```

- 改的是**运行时属性**，不写 /system、不改任何分区
- 属性不持久化，所以每次开机重设
- 放在 `source lib` 之前、`phase1_done` 判断之前 ——
  即使模块还没刷完、或者 lib 加载失败，属性也已经设好

## 1.7 改进：覆盖安装判定

1.6 之前只要模块目录存在就跳过，导致 payload 里升级过的子模块装不上。
1.7 的判定顺序（每一层都偏向"宁可多装一次，不要漏升级"）：

```
1. 没装                        → 装
2. versionCode 两边都是数字
     payload 更大               → 装
     payload 更小               → 跳过（不降级）
     相等                       → 看第 3 步
3. version 字符串都比得到
     不同                       → 装
     相同                       → 跳过
4. 任一侧读不到                 → 装
```

**为什么 versionCode 相等还要看 version**：
HMA-OSS 的 `versionCode` 固定 7304656，只有 `version` 里的 commit 在变
（`b9554518` → `fa6125da`）。只看 versionCode 会把升级当成"已最新"。

**为什么读不到就装**：
LSPosed 的 `module.prop` 用了 Android 专有的压缩方式，`toybox unzip` 读不出来。
这种情况一律覆盖，让它自己去判断。

## 历史修复：sed 吃满 CPU（1.5，真机 91% 降不下来）

### 现象

真机上出现一个 `sed` 进程，CPU 占用 91% 一直不降。命令行是：

```
sed -n 's/.*"configVersion"...' /data/misc/hide_my_applist_*/config.json
```

### 原因

HMA 的 `config.json` 是 **190KB 以上的单行 JSON**，而且服务端可能正在并发写它。
`sed -n 's/.*pattern.*/p'` 对这种超长行做贪婪回溯，文件还在增长时就要反复重试，
于是一个核被占满。

顺带也解释了为什么"配置已经导入成功，但模块还在反复读它" ——
每次 `yj_hma_verify` 都会读一遍。

### 修法

换成 `yj_json_int`：

```sh
dd if=文件 bs=1024 count=8 | tr -d '[:space:]'   # 只读 8KB，不回溯源
```

然后全部用 shell 参数展开定位键名、手工取数字。

- **有界**：只读开头 8KB（`configVersion` / `workMode` 都在文件前部）
- **不回溯**：`tr` 是字符级过滤，不像 `sed` 做正则匹配
- **耗时与文件大小无关**：190KB 和 1KB 一样快

实测（Git Bash，真机会更快）：真实 190KB 预设取 `configVersion` 约 140ms，
且不吃 CPU。原来 sed 方案在文件持续增长时会挂住。

> 补充：也试过纯 shell 逐字符循环去空白，8192 次循环要 8 秒，比 sed 还糟，
> 所以最终用 `dd + tr`。

---

## 历史修复：开机身份误判（1.5）

兜底方案（无 `boot_id` 时用 `/proc/uptime`）原来取的是**秒**，
同一开机内隔几秒就会被判成"重启过"，导致阶段机跳过等待直接跑阶段2。
现在改成向下取整到**分钟**，并加空值保护 —— 宁可漏判也不能误判。

---
## 历史修复：阶段2 卡在 HMA 之后（1.5，真机实测确认）

### 现象

真机日志：

```
04:13:03  ──────── 检测到重启，自动执行阶段2 ────────
04:13:03    → Zygisk Next 配置          ✓ ...
04:13:04    → HMA-OSS 配置校验          ✓ 配置就位
          ← 到此为止，后面什么都没有
```

PathMask、TEESimulator、PIF、LSPosed **全部没跑**。所以你看到
「teesim 安全日期没生效、作用域也没全选」——它不是配错了，是**根本没执行到**。
`teesim/config.json` 一直是 540 字节的出厂默认值就是证据。

### 原因

1.4 在 `yj_cfg_hma` 里写了：

```sh
( sleep 30; sync; reboot ) >/dev/null 2>&1 &
```

这个后台子进程**继承了当前 stdout**。当阶段2 的输出被模块管理器
（或任何管道）捕获时，管道要等所有持有它的写端都关闭才结束；
这个子进程还活着 → 整个脚本被挂住整整 30 秒，然后直接 `reboot`。

实测复现（同样代码，只改一处）：

| 写法 | 管道耗时 |
|---|---|
| `( sleep 3; echo ) &` | **3.0s**（等满） |
| `setsid sh -c 'sleep 3; echo' </dev/null >/dev/null 2>&1 &` | **0.0s** |

### 修法

拆成两步：

1. `yj_cfg_hma` 只记 `hma_reboot_pending=1`，立即返回
2. 等 `yj_stage_final` 把**所有**配置都跑完，再用 `setsid` + 断开全部 fd
   安排重启：

```sh
setsid sh -c 'sleep 30; sync; reboot' </dev/null >/dev/null 2>&1 &
```

现在即使需要重启，PathMask / TEESimulator / PIF / LSPosed 也一定先跑完。

> 回归测试：`自测/selftest.sh` 第 7b 节会**实测** `yj_cfg_hma` 的返回耗时，
> 并静态检查不允许再出现 `( ...; reboot ) &` 这种写法。
> 故意把旧代码 inject 回去测试会报红。

---

## TEESimulator：keybox 是硬性前提（真机确认）

### 现象

配置写了、守护进程也重启了，但日志一直是：

```
E dmn App: config.json invalid; keeping last-good:
           profile 'default' keybox not found: /data/adb/teesim/keybox.xml
E dmn App: no valid config to push — keys minted by TEESimulator cannot be used...
```

### 关键：这是「整份配置」被否掉

不是只有 keybox 那一项失效 —— **作用域 453 个应用、安全日期四项
`system_property`，全部一起作废**，守护进程继续用上一次的（或出厂默认）配置。

所以「安全日期没生效」和「作用域没全选」是**同一个根因**，
不是两个独立问题。

### 必须做的事

把一个真实可用的 `keybox.xml` 放到：

```
/data/adb/teesim/keybox.xml
```

权限建议 `chmod 0600`、属主 root。放好后守护进程会自动检测
（日志里会出现 `ConfigStore: change detected`），不用重启。

没有 keybox 时 TEESimulator 无法工作，这不是模块能绕过的 ——
守护进程会在 `config.json` 校验阶段就拒绝，没有任何降级开关。

---

## 历史修复：HMA 模板不显示（1.4，证据闭合）

前几版（1.1 / 1.2 / 1.3）都没修掉，因为一直在猜配置位置。这次把
HMA-OSS 的 Zygisk 服务端完整反编译，并用**三条互相独立的证据**锁定了结论。

### 配置到底在哪

**`/data/misc/hide_my_applist_<名字>/config.json`**

服务端（模块内 `classes.dex`，注入 `system_server` 的 `ConfigManager`，
混淆名 `Ljb;`）的 `<init>` 是三段式：

```
① 扫 /data/system          ← 遗留位置
   有 hide_my_applist_* →
     · 它就是当前 dataDir → renameTo("/data/misc/<name>")   ← 迁进 misc
     · dataDir 已另有值   → 递归删除这个遗留目录
② 扫 /data/misc            ← 正式位置
   · dataDir 还空 → 采用这个已有目录
   · 否则删掉其它多余的 hide_my_applist_*（去重）
③ 两边都没有 → dataDir = "/data/misc/hide_my_applist_" + 16 位随机小写串
```

然后：

```
configFile         = dataDir + "/config.json"
presetCacheFileNew = dataDir + "/preset_cache_v2.json"
filterCountFile    = dataDir + "/filter_count.json"
statusFile         = dataDir + "/status.json"
```

**加载判据**（同一函数里）：`configFile` 的 `configVersion == 93` 才算
`Config loaded`；不等只打 `Config version mismatch, need to reload`，
然后**保留空默认配置** —— 那就是你看到的「模板一片空白」。

### 三条独立证据

| 证据 | 内容 |
|---|---|
| 服务端 dex | `Ljb;.<init>` 三段式构造（上面那段），`configVersion==93` 判据 |
| 模块自带脚本 | `update_desc.sh` 和 `hmaoss.sh` 都写 `STATUS_FILE=$(printf '%s' /data/misc/hide_my_applist_*/status.json)` |
| App 清除按钮 | `su -c rm -rf /data/misc/hide_my_applist*` —— 只删 `/data/misc`，没碰 `/data/system` |

三条彼此吻合：主目录在 `/data/misc`，后缀是随机串/既有目录名，**不是 uid**。

### 我前几版错在哪

| 版本 | 写的位置 | 为什么没用 |
|---|---|---|
| 1.1 / 1.2 | `/data/user/0/org.frknkrc44.hma_oss/files/config.json` | 该路径全 dex 只出现 1 次，在 `migrateData()` 里 —— 是迁移**源**，不是主配置；而且 1.2 还把 `hide_my_applist_*` 当"残留"删了，那是删配置本体 |
| 1.3 | `/data/system/hide_my_applist_<uid>/config.json` | 优先级写反了：`/data/system` 是**遗留**位置，服务端会把它 rename 进 `/data/misc`；后缀也不是 uid |

### 1.4 的做法

```sh
post-fs-data（服务启动前）
  ├─ 探测 /data/misc/hide_my_applist_*      （正式位置，优先）
  ├─ 探测 /data/system/hide_my_applist_*    （遗留，仅识别，避免重复建目录）
  └─ 都没有 → 新建 /data/misc/hide_my_applist_<16 位随机小写>
       ↓
     写 dataDir/config.json
     chown 1000:1000 · chmod 0660 · restorecon
     （服务端以 system 身份读写，标签/属主不对它会当文件不存在）

service.sh（阶段2）
  └─ 校验 configVersion == 93（服务端判据）
     不等于就重写；workMode=4 则提示崩溃并重试一次
```

**不再删除任何目录。** 也不再往 App 私有 `files/` 写（那是迁移源，写了只会让排查更乱）。

> 后缀说明：服务端**新建**时用 16 位随机小写串；如果是从 `/data/system`
> 迁过来的，则沿用原目录名。模块两种都认（按 `hide_my_applist` 前缀枚举），
> 所以真机上叫什么名字都能找到。

---

## 已知的证据缺口（没编造，供你自己复核）

- 遗留目录在真机上的实际命名形态（静态分析看不到运行时值）
- `migrateData()` 实际传入的包名是哪个（调用链未追到底，且经典 HMA 包名在守卫里被拒，这点存疑）
- 以上均为静态分析，**无运行时验证** —— 刷机后若仍异常，按下面「排查」抓现场

---

## 本版其它更新

本版子模块版本：

| 模块 | 版本 |
|---|---|
| Zygisk Next | 1.5.2 (869-e30955c) |
| PathMask | 2.8.3（A12-5.10 ～ A17-6.18，八个内核分支） |
| SUSFS LKM | v2.5.0-r18.8 |
| LSPosed | v2.2.1 (7939) |
| HMA-OSS Zygisk | future-1eda3ef1 |
| HMA 预设配置 | 2026-10-25（新增 custom_rom 预设、bin.mt.plus） |
| ZN-Audit-Patch | v1.2.0 (18-4d8d26d) |
| Audit-Detect-Pass | 1.1 |
| fgetpriority | v0.0.2 (rawNkprobes) |
| FuseHide | v196 |
| Duck ToolBox | 0.2.1-Stable (137-canary) |
| Play Integrity Fix | v4.9-inject-s |
| TEESimulator | v4.0 (76-06f9f2e) |
| NoMount | v2.2.0 (605) |

---

## 免责与使用条款

**本模块免费发布，禁止任何形式的倒卖、加价转售。**

- 本模块由 **酷安@KNJ蛙** 制作并免费分享。若你是**付费**得到的，说明你被二手贩子坑了，请立即申请退款并举报。
- 允许自由转载、搬运、二次分发，但**必须保留本文件与模块内的作者署名**，且**不得用于任何收费场景**（包括但不限于：付费群、付费教程、捆绑加价、店铺代刷、以「技术支持」名义收费）。
- 禁止声称原创、禁止改名后重新发布、禁止移除或篡改署名信息。
- 本模块只是把别人开发的各个模块按正确顺序串起来自动配置，**本体不包含任何破解或商业内容**；各子模块的版权归各自作者所有。

**使用风险自行承担。**

搭建 Root 隐藏环境本身有一定风险，错误的模块组合、不匹配的内核或操作顺序都可能
导致**卡开机、无法进入系统、数据丢失**。本模块已经尽量做了适配性判断与幂等保护
（不匹配就跳过、失败不写错值、可重复执行），但这**不能覆盖所有机型与 ROM**。

刷入前请务必：

1. **完整备份数据**（至少备份 `/data`，或使用 TWRP 全量备份）；
2. 确认你的 Root 管理器为 **KernelSU / APatch**（Magisk 部分功能受限）；
3. 确认设备为 **64 位**，且内核为 **A12–A17 官方 KMI**
   （`4.x` 与 `5.4` 内核会有多个子模块不适配，模块会自动跳过）；
4. 确认你**已经看懂**自己在做什么。

因使用本模块造成的任何直接或间接损失（设备变砖、数据丢失、账号异常、
应用无法使用等），**作者不承担任何责任**。

---

## 它会自动做什么

**阶段1（刷入时，一次性，中途不重启）**

```
Zygisk Next → PathMask → SUSFS LKM → LSPosed → HMA-OSS → ZN-Audit-Patch
→ Audit-Detect-Pass → fgetpriority → FuseHide → Duck ToolBox
→ PlayIntegrityFix → TEESimulator → NoMount
```

顺序三条硬约束（改代码时务必保留）：

- **PathMask 紧跟 Zygisk Next**：内核模块，早刷早生效；配置要在首次开机前写好。
- **SUSFS LKM 靠前**：同为内核模块。
- **NoMount 必须最后**：它的 `customize.sh` 会当场 `insmod`，
  之后刷的模块会挂载失败。

**阶段0（post-fs-data，每次开机最早期）**

只做 HMA：探测数据目录 → 写 `config.json` → 修正属主/权限/SELinux 标签。
不删任何东西。**这就是 HMA 空白的根因。**

**阶段2（重启后）**

- **Zygisk Next** — 排除列表=仅还原挂载 / 匿名内存 / ZN 链接器
- **HMA-OSS** — 校验 `status.json` 的 workMode；没加载就重写 + 提示重启
- **PathMask** — 黑名单 / 遮蔽路径（Scene）/ procguard / syscall hooks
- **TEESimulator** — 作用域全选（uid ≥ 10000）+ 安全日期四项 `system_property`
- **SUSFS LKM** — 加载状态检查
- **fgetpriority / Duck ToolBox / PIF / LSPosed** — 就位检查与 Spoof 开关

**必须你手动做的**

- **KernelSU → 超级用户**：给 `HMA-OSS`、`FuseHide`、`Shell` root 权限
- **KernelSU → 设置**：打开「隐藏 SELinux 修改记录」「默认卸载模块」
- **LSPosed → 设置**：打开「禁用详细日志」「输出日志到守护进程」「状态通知」；
  「Xposed API 调用保护」保持**关闭**
- **TEESimulator 的 keybox** — 放到 `/data/adb/teesim/`
- **Duck ToolBox 密钥** — 在线拉取需能访问 GitHub
- **PlayIntegrityFix 指纹** — Autopif 需要能访问 GitHub

清单：`Download/一键隐藏_人工清单.txt`
（写不进去时副本在 `/data/adb/yijian_hide/一键隐藏_人工清单.txt`）

---

## 幂等与失败处理

- 已安装模块不重复刷；已正确的配置不重复写。
- HMA 配置只在「首次 / 预设换新 / config.json 被删或损坏」时写，不覆盖你的改动。
- 枚举失败就不写（绝不用占位）。TEESimulator 作用域是典型：
  `packages.list` / `cmd` / `pm` 三级全失败时宁可不写。
- 有项目未完成时不置完成标记，下次开机重试。
- 卸载只清自己的状态目录，不动任何子模块及其配置。

---

## 目录结构

```
module.prop            模块信息
customize.sh           安装入口（阶段1）
post-fs-data.sh        开机早期：写 HMA 配置 ★ 核心
service.sh             开机自运行（阶段2 驱动）
action.sh              操作按钮
uninstall.sh           卸载清理
lib/common.sh          公共库（含 yj_hma_locate / yj_hma_target_dir）
lib/stages.sh          阶段实现
lib/runner.sh          阶段驱动
payload/               全部子模块与预设
```

---

## 出问题时

- 状态：模块列表点【操作】
- 日志：`/data/adb/yijian_hide/run.log`、`error.txt`
- 重跑配置：`sh /data/adb/modules/yijian_hide/action.sh config`
- 只重做 HMA：`sh .../action.sh hma`
- 关闭自动重启：`sh .../action.sh noautoreboot 1`

**HMA 还是空白的排查顺序**

```sh
# 1. 数据目录在哪（正式位置是 /data/misc）
ls -d /data/misc/hide_my_applist_* /data/system/hide_my_applist_* 2>/dev/null

# 2. 配置是不是我们的预设 —— 必须是 configVersion:93，否则服务端会留空
head -c 300 /data/misc/hide_my_applist_*/config.json

# 3. 服务加载状态（1=已加载 2=禁用hook 3=加载中 4=崩溃）
cat /data/misc/hide_my_applist_*/status.json

# 4. 模块自己怎么看
sh /data/adb/modules/yijian_hide/action.sh
```

- 第 1 条什么都没有 → 阶段0 没跑，`sh .../action.sh hma` 后重启
- 第 2 条 `configVersion` 不是 93 → 预设不对，重刷模块
- 第 3 条 `workMode:4` → 服务崩溃，把 status.json 和 config.json 头部发我
- 都对但仍空白 → 用 App 内「导入配置」选 `Download/HMA-OSS_config_*.json` 走一次官方通道

---

**再次强调：本模块免费。付费买到 = 被骗了。**
