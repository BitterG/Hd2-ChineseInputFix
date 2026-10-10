# 绝地潜兵 2 · 中文输入与数字乱序修复 Mod (Chinese Input Fix)

---

## 超级特性

1. **纯加载器原生运行，零外部依赖**：
   - 依赖 **Bingus Shared Loader**；
   - 运行时完全基于 Windows 系统原生 API（`user32`、`gdi32`、`imm32`），无需安装 VC++ Redistributable、.NET、Python 等任何额外运行库。
2. **全输入法通用兼容**：
   - 全面支持 **微软拼音、搜狗输入法、微信输入法、百度输入法、QQ 拼音** 等主流 Windows IME；
   - 采用线程级无阻塞消息循环，浮动候选词窗口流畅响应，杜绝漏键与打字卡顿。
4. **彻底杜绝拼音泄漏与数字颠倒**：
   - 击键与组字直接由悬浮输入条独立承接，未上屏的拼音字母（`wwow`、`ss` 等）绝不泄漏穿透至游戏主窗口；
   - 彻底解决数字与汉字交替输入时时序混乱颠倒的引擎顽疾。
5. **智能联动与全局静音**：
   - **完全静音**：拦截 Windows 默认单行框的警告“叮（Ding）”声，呼出与发送全程安静丝滑；
   - **按 Enter 发送**：打字完毕回车，文字瞬间注入游戏聊天框并自动提交发送；
   - **空内容回车 / Esc**：输入框无内容时按回车或按下 Esc，悬浮输入条与游戏原版聊天框**双向联动同步关闭**；
   - **切屏防残留**：玩家按 `Alt-Tab` 或鼠标点击其他窗口时，悬浮输入条瞬间自动静默收起。

---

## 超级要求

- **[Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader)** (v15 或更高版本 / 游戏通常已装好)
- **Windows 10 / Windows 11 (64-bit)**
- **无需任何其他运行库或环境依赖**

---

## 超级安装方法

### 方法 1：使用 HD2 Mod Manager / Arsenal（强烈推荐）
1. 打开 HD2 Mod Manager。
2. 将 `ChineseInputFix-v1.0.0.zip` 拖入管理器中导入。
3. 勾选启用 `ChineseInputFix` 并点击 Deploy 即可。

### 方法 2：手动解压安装
1. 将 `Addon` 文件夹中的三个文件：
   - `9ba626afa44a3aa3.patch_X`
   - `9ba626afa44a3aa3.patch_X.gpu_resources`
   - `9ba626afa44a3aa3.patch_X.stream`
2. 复制到游戏安装目录下的 `data/` 文件夹中。
   - *提示：如果您的 `data/` 文件夹中已有 `9ba626afa44a3aa3.patch_0`，请将本 Mod 的文件编号顺延递增（例如改为 `patch_1`、`patch_2` 等），避免覆盖已有 Mod。*

---

## 🔍 运行状态与日志

Mod 运行状态全透明，可在系统日志目录中查看：
- **简要状态文件**：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ChineseInputFix_STATUS.txt`
  - 成功激活显示：`OK - ChineseInputFix active (Universal IME & Single Line)`
- **详细运行日志**：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ChineseInputFix.log`
  - 记录每次文字成功注入的详细时间戳与内容。
