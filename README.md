# Chinese Input Fix — in-game Chinese chat input + coloured chat (Helldivers 2)

A pure **Bingus Shared Loader** mod (no external `.exe`, no background process):
press `Enter` to chat and a dark frosted-glass input bar appears, so any Chinese IME
works. It can also colour and resize your chat text.

---

## Repository layout

```text
ChineseInputFix-v3.15.1/
├── Source/mods/chinese_input_fix/fix_ime.lua   # all logic (Win32 FFI / acrylic UI / IME / injection / menu)
├── Addon/                                       # build output (deployable)
├── tests/offline_test.lua                       # 51 offline checks, no game needed
├── tests/native_probe.lua                       # Win32 signature probe (creates a real EDIT window)
├── build_mod.py                                 # one-shot packager (Source -> zip -> Addon/)
├── manifest.json
└── ChineseInputFix-v3.15.1.zip
```

Build: `python build_mod.py` — Tests: `lua51host.exe tests/offline_test.lua`
Optional (needs an interactive desktop): `lua51host.exe tests/native_probe.lua`

---

## Features

1. **In-game input bar** — dark acrylic, single line, 960x48, Microsoft YaHei UI.
   - Works with Microsoft Pinyin, Sogou, WeChat, Baidu, QQ and any other Windows IME.
   - No pinyin leakage into the game chat, no digit/letter reordering.
   - Zero typing latency (thread-wide message pump) and completely silent
     (`Enter`/`Esc` `WM_CHAR` is filtered out, so Windows does not beep).
2. **Alt-Tab keeps your text (fixed in this version)** — the bar hides quietly when the
   game loses focus and never floats over other windows, but whatever you had typed is
   restored the moment you come back.
3. **Coloured / resized chat text (new)** — outgoing text is prefixed with the game's markup:

   | Tag | Meaning |
   | --- | --- |
   | `<c=AARRGGBB>` | `AA` alpha, `RRGGBB` colour |
   | `<s=xx>` | font size |

   Red at size 24 turns `你好` into `<c=FFFF3B30><s=24>你好`.
   If a particular build needs a closing tag to stop the colour bleeding into later
   messages, set `suffix` in the ini (for example `</c>`).
4. **Optional in-game settings page** — with **CowboyBingus Mod Options Menu v1 (api 1)**
   a **CHINESE INPUT FIX** category appears on the **MODS** tab: colour presets
   (red/orange/yellow/green/cyan/blue/purple/white/black/**custom**), custom A/R/G/B
   sliders (0–255), a *size* toggle and a font-size slider (10–99). Press `APPLY` (Tab);
   the menu persists the values.
   Without the menu the mod reads
   `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ChineseInputFix.ini`:

   ```ini
   color = FFFF3B30   # AARRGGBB, empty = no colour
   size = 0           # <s=xx>, 10-99 valid, 0 = no size tag
   suffix =           # optional closing tag appended to the message
   focus = 1          # 1 = steal focus (default), 0 = show only (fallback if focus hangs)
   ```

---

## Requirements

- **Bingus Shared Loader** v15+ (API 1) — nothing else is needed;
- Windows 10 / 11 64-bit;
- Mod Options Menu v1 is optional (colour/size settings page only).

Everything uses libraries Windows ships (`user32`, `gdi32`, `imm32`, `kernel32`).

---

## Install

- **HD2 Mod Manager**: drop `ChineseInputFix-v3.15.1.zip` in, enable, Deploy.
- **Manual**: copy the three files from `Addon/` into the game's `data/` folder. If
  `9ba626afa44a3aa3.patch_0` already exists, renumber to `patch_1`, `patch_2`, …

---

## Diagnostics

| File | Content |
| --- | --- |
| `...\Logs\ChineseInputFix_STATUS.txt` | state + current colour/size + whether the menu registered |
| `...\Logs\ChineseInputFix.log` | every injected string (with markup), menu registration results, errors |

Example status: `OK - 3.15.1 | 颜色 FFFF3B30 / 字号 24 (菜单已接入)`
