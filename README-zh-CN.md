# 绝地潜兵 2 · 中文输入框 + 彩色聊天 (Chinese Input Fix)

> 纯加载器 Mod（Bingus Shared Loader）：游戏内弹出**黑色毛玻璃输入条**，完美支持中文输入法；
> 还能给聊天文字**上色**、**调字号**。没有外部 exe，没有后台进程。

---

## 📁 仓库结构

```text
ChineseInputFix-v3.15.1/
├── Source/mods/chinese_input_fix/fix_ime.lua   # 全部逻辑（Win32 FFI / 毛玻璃 / 输入法 / 注入 / 菜单）
├── Addon/                                       # 构建产物（游戏可直接部署）
│   ├── 9ba626afa44a3aa3.patch_0
│   ├── 9ba626afa44a3aa3.patch_0.stream
│   └── 9ba626afa44a3aa3.patch_0.gpu_resources
├── tests/offline_test.lua                       # 离线测试（51 项，不需要进游戏）
├── tests/native_probe.lua                       # Win32 签名探针（真开一个 EDIT 窗口验证 FFI 声明）
├── build_mod.py                                 # 一键打包（Source → zip → Addon/）
├── manifest.json                                # 模组管理器元数据
├── ChineseInputFix-v3.15.1.zip                   # 管理器导入包
├── README-zh-CN.md / README.md
└── .gitignore
```

打包：`python build_mod.py`（版本号取自源码 `MOD_VERSION`，zip 名与 STATUS 文件自动同步）

离线测试：`lua51host.exe tests/offline_test.lua`（任意带 ffi 的 LuaJIT 均可）

Win32 签名探针（可选，需要一个可交互桌面）：`lua51host.exe tests/native_probe.lua`

---

## ✨ 功能

### 1. 游戏内中文输入条
- 按 `Enter` 打开聊天时，屏幕中下方自动弹出输入条，焦点直接落在上面；
- **全输入法通用**：微软拼音、搜狗、微信输入法、百度、QQ 拼音都能正常组字上屏；
- **杜绝拼音泄漏与数字乱序**：未上屏的拼音不会漏进游戏聊天框，数字与汉字也不会再颠倒；
- **零延迟**：线程级消息泵，打字跟手；
- **完全静音**：拦截 `Enter`/`Esc` 的 `WM_CHAR`，没有 Windows 的“叮”声；
- **黑色毛玻璃**：Fluent Acrylic 半透效果，不挡视线。

### 2. 切屏不再丢字（本版修复）
`Alt-Tab` / 点到别的窗口时，输入条会**静默隐藏**（不会残留在别的窗口上），
但**已输入的内容会被保留**：切回游戏后自动恢复原样，继续打字即可。

### 3. 彩色 / 字号聊天文字（本版新增）
发送时按当前设置给文字加上游戏标记：

| 标记 | 含义 |
| --- | --- |
| `<c=AARRGGBB>` | `AA` 是透明度，`RRGGBB` 是颜色 |
| `<s=xx>` | 字号 |

例如选「红色」+ 打开字号并调到 24，输入 `你好`，实际发出的是 `<c=FFFF3B30><s=24>你好`。

> 标记是**加在消息开头**的；如果某个游戏构建需要闭合标记才不会让颜色延续到后续消息，
> 可以在 ini 里设置 `suffix`（例如 `</c>`）追加到消息末尾。

### 4. 游戏内设置页（可选）
安装 **CowboyBingus Mod Options Menu v1（api 1）** 后，游戏 **MODS** 标签里会多出一个分类（默认英文名 **CHINESE INPUT FIX**，选项标签是中文）：

| 选项 | 类型 | 说明 |
| --- | --- | --- |
| 文字颜色 | 选择 | 关闭 / 红 / 橙 / 黄 / 绿 / 青 / 蓝 / 紫 / 白 / 黑 / **自定义** |
| 自定义·透明度A | 滑块 0–255 | 自定义颜色的 AA |
| 自定义·红R / 绿G / 蓝B | 滑块 0–255 | 组成任意十六进制颜色 |
| 启用字号 | 开关 | 关掉就不加 `<s=xx>`，用游戏默认字号 |
| 字号 | 滑块 10–99 | 对应 `<s=xx>`，有效范围 **10–99**（两位数字） |

改完按 `APPLY`（Tab）生效，菜单会自动记住设置（重启游戏仍在）。

**没装菜单也能用**：这时读取配置文件
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ChineseInputFix.ini`

```ini
# AARRGGBB，留空 = 不上色
color = FFFF3B30
# <s=xx>，有效范围 10-99，0 = 不加
size = 0
# 可选：追加到消息末尾的收尾标记
suffix =
# 抢焦点强度：1 = 标准（默认）；0 = 只显示不抢焦点（应急，需自己点一下输入条才能打字）
focus = 1
```

---

## 🛠 前置要求

- **[Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader)** v15+（API 1）
- Windows 10 / 11 64 位
- 颜色/字号设置页另需 **Mod Options Menu v1**（可选，不装就改 ini）

不需要 VC++ 运行库、.NET、Python 之类的任何东西：用到全是系统自带的 `user32` / `gdi32` / `imm32` / `kernel32`。

---

## 📦 安装

### HD2 Mod Manager（推荐）
把 `ChineseInputFix-v3.15.1.zip` 拖进去 → 勾选 → Deploy。

### 手动
把 `Addon/` 里的三个文件复制到游戏 `data/` 目录。
若已存在同名 `9ba626afa44a3aa3.patch_0`，把编号改成 `patch_1`、`patch_2`… 避免覆盖其他 Mod。

---

## 🔍 排查

| 文件 | 内容 |
| --- | --- |
| `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ChineseInputFix_STATUS.txt` | 当前状态 + 当前颜色/字号 + 菜单是否接入 |
| `...\Logs\ChineseInputFix.log` | 每次注入的实际字符串（含标记）、菜单注册结果、异常 |
| `...\Logs\ModOptionsMenu.log` | 菜单自己的日志，应有 `Registered option chinese_input_fix.color (choice) under CHINESE INPUT FIX.` |

状态文件示例：`OK - 3.15.1 | 颜色 FFFF3B30 / 字号 24 (菜单已接入)`

**万一又卡死了**：`ChineseInputFix.log` 里带 `[trace]` 的行会按顺序记录「打开输入框」的每一步
（`show.begin` → `show.text-ok` → `show.showwindow-ok` → `show.focus-ok` → `show.ime-ok` → `show.done`），
最后一行就是卡住的位置；把这几行发出来就能精确定位。前 40 次记录后自动停止，不影响性能。

**看不到这个分类？**
- 先看 `ModOptionsMenu.log` 里有没有上面那行 `Registered option …`；
- 菜单最多 8 个分类 / 每个 32 项，装太多 Mod 时会被挤掉；
- 分类名优先用 ASCII（菜单里其他 Mod 也都是英文分类名），只有当菜单拒绝英文名时才退回中文「中文输入框」（日志里会写用的是哪个）。

**输入框里的字变得很小？（v3.15.1 已修）**
HFONT 是 32 位值符号扩展成的 64 位句柄（形如 `0xFFFFFFFFxxxxxxxx`），旧代码用 `tonumber()` 转换会丢掉低位，
于是 `WM_SETFONT` 收到一个错句柄，控件回落到系统默认字体（约 9pt）。因为句柄值每次启动都不同，
所以表现为"有时候字很小"。现在句柄按 64 位原样传递，并且每次弹出都会用 `WM_GETFONT` 回读校验；
真的没挂上会在日志里留下：

```
WM_SETFONT 未生效(字体句柄无效): 输入框会显示成系统默认小字
```

看到这行就把日志发出来。
