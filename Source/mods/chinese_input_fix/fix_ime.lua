-- HD2-Addon: mods/chinese_input_fix/fix_ime
-- Chinese Input Fix v3.15.1 — 全能中文输入 + 彩色/字号聊天气泡
--
-- v3.13 修复: 打开输入框时游戏卡死(移除了会死锁的 AttachThreadInput); 分类名改为 ASCII 优先;
-- v3.14: 版本号与包名统一; 字号范围 10-99(另加开关);
-- v3.15: 修复「偶发输入框字体变小」—— HFONT 句柄被 tonumber 截断, 现在按 64 位原样传并回读校验;
-- v3.15.1: 菜单文案去掉全角引号与中间点(游戏字体缺字, 会显示成问号)
--   1. 切屏(Alt-Tab)返回后保留已输入内容(不再被 clear 掉)
--   2. 彩色/字号标记: <c=AARRGGBB> 与 <s=xx>, 由 CowboyBingus Mod Options Menu 配置
--      (预置 红/橙/黄/绿/青/蓝/紫/白/黑 + 自定义 RGBA 滑块)
--   3. 无菜单时回落到 ChineseInputFix.ini
--
-- 既有能力(已实机验证):
--   - 游戏内浮动输入条(黑色毛玻璃 + 微软雅黑), 全输入法通用(微软/搜狗/微信/百度/QQ)
--   - 零延迟线程级消息泵, 拦截 Enter/Esc 的 WM_CHAR 以消除 Windows "叮" 声
--   - 空内容 / 非空内容走同一条 set_text + Enter 提交路径
--   - Alt-Tab / 失焦 时静默隐藏, 不残留到其他窗口
--   - 严格单行比例(960x48, 字号 -28)

if rawget(_G, "__HD2_CHINESE_INPUT_OVERLAY_MOD") then
    return { installed = true, version = "3.15.1" }
end

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or not ffi or ffi.os ~= "Windows" or not ffi.abi("64bit") then
    return { installed = false, reason = "Windows x64 LuaJIT required" }
end

local MOD_VERSION = "3.15.1"
local LOG_NAME = "ChineseInputFix"

local M = {
    version = MOD_VERSION,
    started = false,
    ready = false,
    retired = false,
    errors = 0,
    frames = 0,
    suspended = false,     -- 失焦挂起(保留输入内容)
    last_status = nil,
    cooldown_until = 0,
    last_enter = false,
    last_esc = false,
}
rawset(_G, "__HD2_CHINESE_INPUT_OVERLAY_MOD", M)

-- -------------------------------------------------------------------------------------
-- Windows Native Declarations
-- -------------------------------------------------------------------------------------
local native = {}
local function init_native()
    if not pcall(ffi.typeof, "HD2InputNativeV311") then
        ffi.cdef([[
            typedef struct { int unused; } HD2InputNativeV311;
            typedef uint32_t (*HD2SetTextFn)(uint64_t widget, const char *text);

            typedef void* HWND;
            typedef void* HINSTANCE;
            typedef void* HMENU;
            typedef void* HIMC;
            typedef void* HFONT;
            typedef void* HDC;
            typedef void* HBRUSH;
            typedef unsigned long DWORD;
            typedef int BOOL;
            typedef intptr_t LONG_PTR;

            typedef struct {
                HWND hwnd;
                uint32_t message;
                uint64_t wParam;
                int64_t lParam;
                DWORD time;
                struct { int x, y; } pt;
            } MSG;

            typedef struct {
                int left, top, right, bottom;
            } RECT;

            typedef struct {
                int AccentState;
                int AccentFlags;
                int GradientColor;
                int AnimationId;
            } ACCENT_POLICY;

            typedef struct {
                int Attribute;
                void* Data;
                size_t SizeOfData;
            } WINCOMPATTRDATA;

            void *hd2_GetCurrentProcess(void) __asm__("GetCurrentProcess");
            void *hd2_GetModuleHandleA(const char *name) __asm__("GetModuleHandleA");
            int hd2_ReadProcessMemory(void *process, const void *address, void *buffer, size_t size,
                                      size_t *done) __asm__("ReadProcessMemory");
            uint32_t hd2_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
            void *hd2_GetForegroundWindow(void) __asm__("GetForegroundWindow");
            uint32_t hd2_GetWindowThreadProcessId(void *window, uint32_t *process)
                __asm__("GetWindowThreadProcessId");

            HWND hd2_CreateWindowExW(
                DWORD dwExStyle, const wchar_t* lpClassName, const wchar_t* lpWindowName,
                DWORD dwStyle, int X, int Y, int nWidth, int nHeight,
                HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, void* lpParam
            ) __asm__("CreateWindowExW");
            BOOL hd2_DestroyWindow(HWND hWnd) __asm__("DestroyWindow");
            BOOL hd2_ShowWindow(HWND hWnd, int nCmdShow) __asm__("ShowWindow");
            BOOL hd2_IsWindow(HWND hWnd) __asm__("IsWindow");
            BOOL hd2_SetWindowPos(HWND hWnd, HWND hWndInsertAfter, int X, int Y, int cx, int cy, uint32_t uFlags)
                __asm__("SetWindowPos");
            BOOL hd2_SetForegroundWindow(HWND hWnd) __asm__("SetForegroundWindow");
            BOOL hd2_BringWindowToTop(HWND hWnd) __asm__("BringWindowToTop");
            HWND hd2_SetFocus(HWND hWnd) __asm__("SetFocus");
            HWND hd2_GetFocus(void) __asm__("GetFocus");
            BOOL hd2_PeekMessageW(MSG* lpMsg, HWND hWnd, uint32_t wMsgFilterMin, uint32_t wMsgFilterMax, uint32_t wRemoveMsg)
                __asm__("PeekMessageW");
            BOOL hd2_TranslateMessage(const MSG* lpMsg) __asm__("TranslateMessage");
            LONG_PTR hd2_DispatchMessageW(const MSG* lpMsg) __asm__("DispatchMessageW");
            int hd2_GetWindowTextW(HWND hWnd, wchar_t* lpString, int nMaxCount) __asm__("GetWindowTextW");
            int hd2_GetWindowTextLengthW(HWND hWnd) __asm__("GetWindowTextLengthW");
            BOOL hd2_SetWindowTextW(HWND hWnd, const wchar_t* lpString) __asm__("SetWindowTextW");
            int16_t hd2_GetAsyncKeyState(int vKey) __asm__("GetAsyncKeyState");
            int hd2_GetSystemMetrics(int nIndex) __asm__("GetSystemMetrics");
            BOOL hd2_SetLayeredWindowAttributes(HWND hwnd, uint32_t crKey, uint8_t bAlpha, DWORD dwFlags)
                __asm__("SetLayeredWindowAttributes");
            intptr_t hd2_SendMessageW(HWND hWnd, uint32_t Msg, uint64_t wParam, int64_t lParam)
                __asm__("SendMessageW");
            BOOL hd2_SetWindowCompositionAttribute(HWND hWnd, WINCOMPATTRDATA* data)
                __asm__("SetWindowCompositionAttribute");

            HIMC hd2_ImmGetContext(HWND hWnd) __asm__("ImmGetContext");
            int32_t hd2_ImmGetCompositionStringW(HIMC hIMC, DWORD dwIndex, void* lpBuf, DWORD dwBufLen)
                __asm__("ImmGetCompositionStringW");
            BOOL hd2_ImmReleaseContext(HWND hWnd, HIMC hIMC) __asm__("ImmReleaseContext");
            HIMC hd2_ImmAssociateContext(HWND hWnd, HIMC hIMC) __asm__("ImmAssociateContext");
            HIMC hd2_ImmCreateContext(void) __asm__("ImmCreateContext");
            BOOL hd2_ImmSetOpenStatus(HIMC hIMC, BOOL fOpen) __asm__("ImmSetOpenStatus");

            int hd2_WideCharToMultiByte(uint32_t cp, DWORD flags, const wchar_t* wide, int wideLen, char* mb, int mbLen, void* defChar, void* usedDef)
                __asm__("WideCharToMultiByte");
            int hd2_MultiByteToWideChar(uint32_t cp, DWORD flags, const char* mb, int mbLen, wchar_t* wide, int wideLen)
                __asm__("MultiByteToWideChar");
            void hd2_keybd_event(uint8_t bVk, uint8_t bScan, DWORD dwFlags, uintptr_t dwExtraInfo)
                __asm__("keybd_event");

            HFONT hd2_CreateFontW(
                int cHeight, int cWidth, int cEscapement, int cOrientation, int cWeight,
                DWORD bItalic, DWORD bUnderline, DWORD bStrikeOut, DWORD iCharSet,
                DWORD iOutPrecision, DWORD iClipPrecision, DWORD iQuality,
                DWORD iPitchAndFamily, const wchar_t* pszFaceName
            ) __asm__("CreateFontW");
            HBRUSH hd2_CreateSolidBrush(uint32_t crColor) __asm__("CreateSolidBrush");
            int hd2_SetBkMode(HDC hdc, int mode) __asm__("SetBkMode");
            uint32_t hd2_SetTextColor(HDC hdc, uint32_t color) __asm__("SetTextColor");
            uint32_t hd2_SetBkColor(HDC hdc, uint32_t color) __asm__("SetBkColor");
            BOOL hd2_DeleteObject(void* hObject) __asm__("DeleteObject");
        ]])
    end

    local ok_k, k32 = pcall(ffi.load, "kernel32")
    if not ok_k or not k32 then return false, "kernel32 unavailable" end
    native.k32 = k32
    native.process = k32.hd2_GetCurrentProcess()

    local ok_u, user32 = pcall(ffi.load, "user32")
    if not ok_u or not user32 then return false, "user32 unavailable" end
    native.user32 = user32

    local ok_g, gdi32 = pcall(ffi.load, "gdi32")
    native.gdi32 = ok_g and gdi32 or nil

    local ok_imm, imm32 = pcall(ffi.load, "imm32")
    native.imm32 = ok_imm and imm32 or nil

    local game = k32.hd2_GetModuleHandleA("game.dll")
    if game == nil then return false, "game.dll not loaded" end
    native.base = tonumber(ffi.cast("uint64_t", game))

    return true
end

-- -------------------------------------------------------------------------------------
-- String Converters
-- -------------------------------------------------------------------------------------
local function to_wide(str)
    if not str or #str == 0 then
        local buf = ffi.new("wchar_t[1]")
        buf[0] = 0
        return buf
    end
    local len = native.k32.hd2_MultiByteToWideChar(65001, 0, str, #str, nil, 0)
    local buf = ffi.new("wchar_t[?]", len + 1)
    native.k32.hd2_MultiByteToWideChar(65001, 0, str, #str, buf, len)
    buf[len] = 0
    return buf
end

local function to_utf8(wide_buf, len)
    if not wide_buf or len <= 0 then return "" end
    local mbLen = native.k32.hd2_WideCharToMultiByte(65001, 0, wide_buf, len, nil, 0, nil, nil)
    local buf = ffi.new("char[?]", mbLen + 1)
    native.k32.hd2_WideCharToMultiByte(65001, 0, wide_buf, len, buf, mbLen, nil, nil)
    buf[mbLen] = 0
    return ffi.string(buf, mbLen)
end

-- -------------------------------------------------------------------------------------
-- Safe Memory Reading & Signatures
-- -------------------------------------------------------------------------------------
local function read(address, size)
    local buf, got = ffi.new("uint8_t[?]", size), ffi.new("size_t[1]")
    if native.k32.hd2_ReadProcessMemory(native.process, ffi.cast("const void *", address), buf, size, got) == 0
       or tonumber(got[0]) ~= size then
        return nil
    end
    return ffi.string(buf, size)
end

local function u32(blob, offset)
    offset = offset or 0
    if not blob or #blob < offset + 4 then return nil end
    local v = ffi.new("uint32_t[1]")
    ffi.copy(v, blob:sub(offset + 1, offset + 4), 4)
    return tonumber(v[0])
end

local function pointer(blob)
    if not blob or #blob ~= 8 then return nil end
    local v = ffi.new("uint64_t[1]")
    ffi.copy(v, blob, 8)
    local a = tonumber(v[0])
    if a < 0x10000 or a >= 0x800000000000 then return nil end
    return a
end

local SIGS = {
    {name = "chat_notice", rva = 0x12f2f81, text = "48 8B 3D ?? ?? ?? ?? 49 8B F0 48 8B DA 80 BF ?? ?? ?? ?? 00 0F 84 ?? ?? ?? ?? 4C 8B 1D ?? ?? ?? ?? 33 C0 49 39 1B 74 ?? FF C0 49 81 C3 C0 00 00 00 83 F8 08 72 ?? E9 ?? ?? ?? ?? 0F 1F 40 00 0F 29 74 24 70 48 8D 54 24 50 0F 28 35 ?? ?? ?? ?? 4C 8B C3 E8 ?? ?? ?? ?? 4D 8D 4B 08 48 89 74 24 28 48 8D 8F 80 70 4F 00 66 0F 7F 74 24 40 4C 8D 44 24 40 BA 7F 03 12 1C 0F 10 00 48 8D 44 24 30 48 89 44 24 20 0F 29 44 24 30 E8 ?? ?? ?? ?? F3 0F 10 15 ?? ?? ?? ?? 48 8D 8F ?? ?? ?? ?? 48 8B D0 E8 ?? ?? ?? ??",
     fields = {hud = {"rip", {3}, {7}}, chat_hud = {"u32", {154}}}},
    {name = "chat_input", rva = 0x18608d0, text = "48 83 EC 28 80 B9 ?? ?? ?? ?? 00 4C 8B C9 74 ?? 84 D2 74 ?? E8 ?? ?? ?? ?? 84 C0 74 ?? 33 D2 49 8B C9",
     fields = {chat_open = {"u32", {6}}}},
    {name = "chat_field", rva = 0x1860200, text = "48 8B D3 48 8D 8F ?? ?? ?? ?? E8 ?? ?? ?? ?? 0F B6 87 0F 1E 00 00 40 88 AF 0F 1E 00 00",
     fields = {chat_field = {"u32", {6}}}},
    {name = "field_text", rva = 0x18f2ef8, text = "44 8B 93 ?? ?? ?? ?? 48 8D 4C 24 40 41 FF CA E8 ?? ?? ?? ?? 48 8D 4C 24 40 8B D0 41 3B C2 72 ?? 41 8B D2 E8 ?? ?? ?? ?? 8B C8 48 8D 54 24 40 C6 44 0C 40 00 48 8D 8B ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 80 BB 76 0A 00 00 00",
     fields = {field_max = {"u32", {3}}, field_widget = {"u32", {55}}}},
    {name = "set_text", rva = 0x143dd60, text = "48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 20 48 85 D2 48 8D 3D ?? ?? ?? ?? 48 8B D9 48 0F 45 FA BA 48 06 00 00 48 8B CF E8 ?? ?? ?? ?? 48 3D ?? ?? ?? ?? 73 ?? 41 B8 ?? ?? ?? ?? 48 8D 8B ?? ?? ?? ?? 48 8B D7 E8 ?? ?? ?? ??",
     fields = {text_limit = {"u32", {47, 55}}, widget_text = {"u32", {62}}}},
}

local V = {}
local fn = {}

local function parse_sig(sig)
    local bytes = {}
    for part in sig.text:gmatch("%S+") do
        bytes[#bytes + 1] = part ~= "??" and tonumber(part, 16) or false
    end
    sig.bytes = bytes
end

local function matches(blob, pos, sig)
    local bytes = sig.bytes
    if pos < 1 or pos + #bytes - 1 > #blob then return false end
    for i = 1, #bytes do
        local b = bytes[i]
        if b and blob:byte(pos + i - 1) ~= b then return false end
    end
    return true
end

local function resolve_sigs()
    local base = native.base
    for _, sig in ipairs(SIGS) do
        parse_sig(sig)
        local blob = read(base + sig.rva, #sig.bytes)
        if not (blob and matches(blob, 1, sig)) then
            return false, "signature mismatch: " .. sig.name
        end
        for field, spec in pairs(sig.fields) do
            local off = spec[2][1]
            if spec[1] == "u32" then
                V[field] = u32(blob, off)
            elseif spec[1] == "rip" then
                local next_inst = spec[3][1]
                local disp = u32(blob, off)
                if disp >= 2147483648 then disp = disp - 4294967296 end
                V[field] = sig.rva + next_inst + disp
            end
        end
    end

    if not V.hud or not V.chat_hud or not V.chat_open or not V.chat_field or not V.field_widget or not V.widget_text then
        return false, "failed to resolve offsets"
    end

    fn.set_text = ffi.cast("HD2SetTextFn", base + 0x143dd60)
    return true
end

-- -------------------------------------------------------------------------------------
-- Paths / Logging / Config
-- -------------------------------------------------------------------------------------
local function data_dir()
    local dir = os.getenv("LOCALAPPDATA")
    if not dir then return "." end
    return dir .. "/CowboyBingus/Helldivers2/Logs"
end

local function log_message(msg)
    local path = data_dir() .. "/" .. LOG_NAME .. ".log"
    pcall(function()
        local f = io.open(path, "a")
        if f then
            f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
            f:close()
        end
    end)
end

local function write_status(line)
    if line == M.last_status then return end
    M.last_status = line
    local path = data_dir() .. "/" .. LOG_NAME .. "_STATUS.txt"
    pcall(function()
        local f = io.open(path, "w")
        if f then
            f:write(line .. "\n")
            f:close()
        end
    end)
end

local CONFIG_PATH = data_dir() .. "/" .. LOG_NAME .. ".ini"

-- 打开输入框/注册菜单的每一步都留痕(各给有限次数, 稳态不写盘)。
-- 真卡死时, 日志最后一行就是卡住的那一步。
local trace_budget = 40
local menu_trace_budget = 12

local function trace(msg)
    if trace_budget <= 0 then return end
    trace_budget = trace_budget - 1
    log_message("[trace] " .. msg)
end

local function trace_menu(msg)
    if menu_trace_budget <= 0 then return end
    menu_trace_budget = menu_trace_budget - 1
    log_message("[trace] " .. msg)
end

-- 解析 ini 文本(纯函数, 供离线测试)
local function parse_ini_text(text)
    local result = {}
    if type(text) ~= "string" then return result end
    for line in text:gmatch("[^\r\n]+") do
        local body = line:gsub("^%s+", ""):gsub("%s+$", "")
        if body ~= "" and body:sub(1, 1) ~= "#" and body:sub(1, 1) ~= ";" then
            local key, value = body:match("^([%w_%-]+)%s*=%s*(.-)$")
            if key then
                result[key:lower()] = (value or ""):gsub("%s+$", "")
            end
        end
    end
    return result
end

local function load_config()
    local raw
    pcall(function()
        local f = io.open(CONFIG_PATH, "r")
        if f then
            raw = f:read("*a")
            f:close()
        end
    end)
    if raw == nil then
        -- 首次运行写一份带注释的模板, 方便玩家手改
        pcall(function()
            local f = io.open(CONFIG_PATH, "w")
            if f then
                f:write("# ChineseInputFix 配置（仅在没有安装「模组菜单」时生效）\n")
                f:write("# 颜色: AARRGGBB, 例如 FFFF3B30 = 不透明红; 留空 = 不上色\n")
                f:write("color =\n")
                f:write("# 字号: 游戏 <s=xx> 的数值(有效范围 10-99), 0 = 不加字号标记\n")
                f:write("size = 0\n")
                f:write("# 可选: 追加在消息末尾的收尾标记(某些构建需要闭合颜色/字号标记才会复原)\n")
                f:write("suffix =\n")
                f:write("# 抢焦点的强度: 1 = 标准(默认), 0 = 只显示不抢焦点(遇到卡死时的应急值)\n")
                f:write("focus = 1\n")
                f:close()
            end
        end)
        return {}
    end
    return parse_ini_text(raw)
end

-- -------------------------------------------------------------------------------------
-- 颜色 / 字号 (纯函数, 可离线测试)
-- -------------------------------------------------------------------------------------
local COLOR_PRESETS = {
    {label = "红色", argb = "FFFF3B30"},
    {label = "橙色", argb = "FFFF9500"},
    {label = "黄色", argb = "FFFFD60A"},
    {label = "绿色", argb = "FF30D158"},
    {label = "青色", argb = "FF32D4E8"},
    {label = "蓝色", argb = "FF0A84FF"},
    {label = "紫色", argb = "FFBF5AF2"},
    {label = "白色", argb = "FFFFFFFF"},
    {label = "黑色", argb = "FF000000"},
}

local COLOR_CHOICES = {}
COLOR_CHOICES[1] = "关闭"
for i, preset in ipairs(COLOR_PRESETS) do
    COLOR_CHOICES[i + 1] = preset.label
end
local CUSTOM_CHOICE = #COLOR_CHOICES + 1
COLOR_CHOICES[CUSTOM_CHOICE] = "自定义"

local function clamp_int(value, lo, hi)
    local n = tonumber(value)
    if not n then return lo end
    n = math.floor(n + 0.5)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function valid_argb(hex)
    return type(hex) == "string" and #hex == 8 and hex:match("^%x%x%x%x%x%x%x%x$") ~= nil
end

-- color_index: COLOR_CHOICES 的下标; custom_a/r/g/b: 0..255; size_raw: <s=xx>;
-- fallback_hex: 无菜单时的 ini 颜色
local function compute_style(color_index, custom_a, custom_r, custom_g, custom_b, size_raw, fallback_hex)
    local argb, size = nil, nil

    local idx = tonumber(color_index)
    if idx and idx >= 1 and idx <= #COLOR_CHOICES then
        if idx == 1 then
            argb = nil
        elseif idx == CUSTOM_CHOICE then
            argb = string.format("%02X%02X%02X%02X",
                clamp_int(custom_a, 0, 255), clamp_int(custom_r, 0, 255),
                clamp_int(custom_g, 0, 255), clamp_int(custom_b, 0, 255))
        else
            argb = COLOR_PRESETS[idx - 1].argb
        end
    elseif valid_argb(fallback_hex) then
        argb = string.upper(fallback_hex)
    end

    local n = tonumber(size_raw)
    if n and n > 0 then
        -- 游戏标记是 <s=xx>: 两位数字, 且实测有效下限 10 / 上限 99
        size = clamp_int(n, 10, 99)
    end

    return argb, size
end

-- 生成最终注入聊天框的字符串
local function build_markup(argb, size, text, suffix)
    if text == nil then text = "" end
    if text == "" then return "" end
    local prefix = ""
    if argb and argb ~= "" then
        prefix = prefix .. "<c=" .. string.upper(argb) .. ">"
    end
    if size and tonumber(size) and tonumber(size) > 0 then
        prefix = prefix .. "<s=" .. tostring(math.floor(tonumber(size))) .. ">"
    end
    if type(suffix) == "string" and suffix ~= "" then
        return prefix .. text .. suffix
    end
    return prefix .. text
end

-- -------------------------------------------------------------------------------------
-- 模组菜单接入 (CowboyBingus Mod Options Menu, api 1)
--   约定: ModOptionsMenu.register_option(id, spec) / get(id) / on_change(id, fn)
--   菜单可能在我们的 mod 之后加载, 所以按帧轮询全局变量, 找到后只注册一次。
-- -------------------------------------------------------------------------------------
-- 分类名优先用 ASCII: 菜单现有的分类全是英文, 先用同类名字注册最稳; 中文只作兜底。
-- 选项标签本身仍然是中文。
local MENU_MOD_NAMES = { "CHINESE INPUT FIX", "中文输入框" }
local OPTION_PREFIX = "chinese_input_fix"

local menu = {
    state = "waiting",   -- waiting | ready | unavailable
    entity = nil,
    mod_name = nil,
    registered = {},     -- key -> true
    values = {},         -- key -> 菜单当前值
    next_frame = 0,
    warned = false,
    attempts = 0,
}

-- 说明: 菜单/游戏字体里没有「」这类全角引号, 会显示成问号, 所以这里只用常见字符。
local function option_specs()
    return {
        {key = "color", id = OPTION_PREFIX .. ".color", type = "choice",
         label = "文字颜色", choices = COLOR_CHOICES, default = 1,
         description = "聊天文字颜色, 写进消息里的格式是 <c=AARRGGBB>; 选自定义时用下面 4 个滑块"},
        {key = "alpha", id = OPTION_PREFIX .. ".alpha", type = "slider",
         label = "自定义 透明度A", min = 0, max = 255, step = 1, default = 255,
         description = "自定义颜色的透明度(AA), 255 = 完全不透明"},
        {key = "red", id = OPTION_PREFIX .. ".red", type = "slider",
         label = "自定义 红R", min = 0, max = 255, step = 1, default = 255,
         description = "自定义颜色的红色分量"},
        {key = "green", id = OPTION_PREFIX .. ".green", type = "slider",
         label = "自定义 绿G", min = 0, max = 255, step = 1, default = 255,
         description = "自定义颜色的绿色分量"},
        {key = "blue", id = OPTION_PREFIX .. ".blue", type = "slider",
         label = "自定义 蓝B", min = 0, max = 255, step = 1, default = 255,
         description = "自定义颜色的蓝色分量"},
        {key = "size_on", id = OPTION_PREFIX .. ".size_on", type = "toggle",
         label = "启用字号", default = false,
         description = "打开后才会在消息里加字号标记; 关闭时用游戏默认字号"},
        {key = "size", id = OPTION_PREFIX .. ".size", type = "slider",
         label = "字号", min = 10, max = 99, step = 1, default = 10,
         description = "游戏 <s=xx> 的字号, 有效范围 10-99"},
    }
end

local function menu_register(page, mod_name)
    local any = false
    for _, spec in ipairs(option_specs()) do
        local body = {
            type = spec.type,
            label = spec.label,
            mod = mod_name,
            description = spec.description,
            default = spec.default,
            gap = spec.gap,
            choices = spec.choices,
            min = spec.min,
            max = spec.max,
            step = spec.step,
        }
        local ok, registered, why = pcall(function()
            trace_menu("menu.register " .. spec.id)
            return page.register_option(spec.id, body)
        end)
        if ok and registered then
            any = true
            trace_menu("menu.registered " .. spec.id)
            menu.registered[spec.key] = true
            local got, value = pcall(function() return page.get(spec.id) end)
            if got and value ~= nil then
                menu.values[spec.key] = value
            end
            pcall(function()
                page.on_change(spec.id, function(new_value)
                    menu.values[spec.key] = new_value
                end)
            end)
        else
            log_message(string.format("模组菜单拒绝了选项 %s: %s", spec.id, tostring(why or registered)))
        end
    end
    return any
end

-- 每帧调用; 内部自带节流, 未注册成功前按帧数轮询
local MAX_REGISTER_ATTEMPTS = 12

local function menu_poll(frame)
    if menu.state == "ready" then return end
    if frame < menu.next_frame then return end
    -- 头 1.5 秒不碰菜单: 让游戏先把 MODS 标签搭好, 避免抢在它初始化中间注册
    if menu.entity == nil and menu.attempts == 0 and frame < 90 then
        menu.next_frame = frame + 30
        return
    end
    -- 还没见过菜单时每 30 帧找一次; 见过但没注册成功就放慢重试
    local step = 30
    if menu.state ~= "waiting" then
        step = 300
    elseif menu.attempts > 0 then
        step = 120
    end
    menu.next_frame = frame + step

    local page = rawget(_G, "ModOptionsMenu")
    if page == nil then
        if menu.state == "waiting" and not menu.warned and frame > 1800 then
            menu.warned = true
            log_message("未检测到「模组菜单」(ModOptionsMenu), 使用 ChineseInputFix.ini 或默认设置")
        end
        return
    end

    if type(page) ~= "table" or page.api ~= 1 or type(page.register_option) ~= "function" then
        if not menu.warned then
            menu.warned = true
            log_message("「模组菜单」api 不兼容(需要 api 1), 使用 ini 或默认设置")
        end
        menu.state = "unavailable"
        return
    end

    if menu.entity ~= page then
        menu.entity = page
        menu.attempts = 0
        menu.registered = {}
    end

    -- 菜单可能刚出现还没准备好: 失败就过一会儿再试, 但不无限重试
    menu.attempts = menu.attempts + 1
    for _, mod_name in ipairs(MENU_MOD_NAMES) do
        if menu_register(page, mod_name) then
            menu.state = "ready"
            menu.mod_name = mod_name
            log_message("已注册到「模组菜单」: " .. mod_name)
            return
        end
    end
    if menu.attempts >= MAX_REGISTER_ATTEMPTS then
        menu.state = "unavailable"
        log_message("模组菜单注册失败(已重试 " .. tostring(menu.attempts) .. " 次), 使用 ini 或默认设置")
    end
end

local function menu_value(key)
    if not menu.registered[key] then return nil end
    return menu.values[key]
end

-- -------------------------------------------------------------------------------------
-- 当前样式
-- -------------------------------------------------------------------------------------
local config = {}

-- 字号的取值来源: 菜单开关 > 菜单滑块 > ini。开关关掉就是"不加标记", 连 ini 也不看
-- (否则玩家在菜单里关掉字号, ini 里的旧值又把它顶开了)。
local function size_input()
    if menu.registered.size_on then
        if menu.values.size_on == true then
            return menu.values.size
        end
        return nil
    end
    if menu.registered.size then
        return menu.values.size      -- 菜单只注册了滑块: 沿用 >0 即启用的旧语义
    end
    return config.size               -- 完全没有菜单: 读 ini
end

local function resolve_style()
    local color_index = menu_value("color")
    local custom_a = menu_value("alpha")
    local custom_r = menu_value("red")
    local custom_g = menu_value("green")
    local custom_b = menu_value("blue")
    local size_raw = size_input()

    if color_index == nil then
        -- 没有菜单: ini 里的 color 直接当十六进制用
        return compute_style(nil, nil, nil, nil, nil, size_raw, config.color)
    end
    return compute_style(color_index, custom_a, custom_r, custom_g, custom_b,
        size_raw, config.color)
end

local function decorate(text)
    local argb, size = resolve_style()
    return build_markup(argb, size, text, config.suffix)
end

local function style_summary()
    local argb, size = resolve_style()
    local label = argb and ("颜色 " .. argb) or "颜色 关闭"
    if size then label = label .. " / 字号 " .. tostring(size) else label = label .. " / 字号 关闭" end
    if menu.state == "ready" then
        label = label .. " (菜单已接入)"
    else
        label = label .. " (无菜单)"
    end
    return label
end

-- -------------------------------------------------------------------------------------
-- 浮动输入框 (单行比例 + 全输入法支持)
-- -------------------------------------------------------------------------------------
local box = {
    hwnd = nil,
    created = false,
    visible = false,
    font = nil,
    brush = nil,
    himc = nil,
    saved_text = "",   -- 失焦时暂存的输入内容
}

-- 句柄一律按 64 位整数原样传递/比较。
-- 千万别 tonumber(): HFONT/HBRUSH/HIMC 是 32 位值符号扩展成 64 位的, 形如 0xFFFFFFFFxxxxxxxx,
-- 转成 double 会丢掉低位, 传出去就是个错句柄 —— 字体偶发变成"系统默认小字"就是这么来的。
local function handle_value(value)
    if value == nil then return ffi.cast("uint64_t", 0) end
    return ffi.cast("uint64_t", ffi.cast("uintptr_t", value))
end

local function is_null(value)
    if value == nil then return true end
    return handle_value(value) == ffi.cast("uint64_t", 0)
end

local function handles_equal(a, b)
    if a == nil or b == nil then return a == b end
    return handle_value(a) == handle_value(b)
end

local function is_ime_composing()
    if is_null(box.hwnd) or not native.imm32 then return false end
    local himc = native.imm32.hd2_ImmGetContext(box.hwnd)
    if is_null(himc) then return false end
    local len = native.imm32.hd2_ImmGetCompositionStringW(himc, 0x0008, nil, 0)
    native.imm32.hd2_ImmReleaseContext(box.hwnd, himc)
    return len > 0
end

local function get_box_text()
    if is_null(box.hwnd) then return "" end
    local len = native.user32.hd2_GetWindowTextLengthW(box.hwnd)
    if len <= 0 then return "" end
    local buf = ffi.new("wchar_t[?]", len + 1)
    native.user32.hd2_GetWindowTextW(box.hwnd, buf, len + 1)
    return to_utf8(buf, len)
end

local function set_box_text(text)
    if is_null(box.hwnd) then return end
    local body = text or ""
    native.user32.hd2_SetWindowTextW(box.hwnd, to_wide(body))
    if body ~= "" then
        -- 恢复内容后把插入点放到末尾: EM_SETSEL(-1, -1) 取消选择并把 caret 移到结尾
        native.user32.hd2_SendMessageW(box.hwnd, 0x00B1, ffi.cast("uint64_t", -1),
            ffi.cast("int64_t", -1))
    end
end

local function clear_box_text()
    set_box_text("")
end

-- 句柄一律按 64 位整数原样传递/比较。
-- 千万别 tonumber(): HFONT/HBRUSH/HIMC 是 32 位值符号扩展成 64 位的, 形如 0xFFFFFFFFxxxxxxxx,
-- 转成 double 会丢掉低位, 传出去就是个错句柄 —— 字体偶发变成"系统默认小字"就是这么来的。
-- (helper 定义在 box 声明之后, 这里只留说明)

local function same_window(a, b)
    if a == nil or b == nil then return false end
    return handles_equal(a, b)
end

-- -------------------------------------------------------------------------------------
-- 输入框字体: 建立后必须回读确认真的挂上了
--   症状: 偶发"输入框里的字变得很小" —— 就是 WM_SETFONT 收到一个被截断的 HFONT,
--   控件 SelectObject 失败后回落到系统默认字体(约 9pt)。
-- -------------------------------------------------------------------------------------
local WM_SETFONT = 0x0030
local WM_GETFONT = 0x0031
local BOX_FONT_HEIGHT = -28          -- 负值 = 字符高度 28 像素

local function box_font_attached()
    if is_null(box.hwnd) or is_null(box.font) then return false end
    local current = native.user32.hd2_SendMessageW(box.hwnd, WM_GETFONT,
        ffi.cast("uint64_t", 0), ffi.cast("int64_t", 0))
    return handles_equal(current, box.font)
end

local function apply_box_font()
    if is_null(box.hwnd) or not native.gdi32 then return false end

    if is_null(box.font) then
        box.font = native.gdi32.hd2_CreateFontW(
            BOX_FONT_HEIGHT, 0, 0, 0, 500,
            0, 0, 0, 1, 0, 0, 5,
            0, to_wide("Microsoft YaHei UI"))
        if is_null(box.font) then
            log_message("CreateFontW 失败: 输入框会显示成系统默认小字")
            return false
        end
    end

    if box_font_attached() then return true end

    -- 句柄按 64 位原样传(见 handle_value 的注释), 不能 tonumber
    native.user32.hd2_SendMessageW(box.hwnd, WM_SETFONT, handle_value(box.font),
        ffi.cast("int64_t", 1))

    if not box_font_attached() then
        log_message("WM_SETFONT 未生效(字体句柄无效): 输入框会显示成系统默认小字")
        return false
    end
    return true
end

-- 把焦点交给输入框。
-- 注意: 这里绝对不能 AttachThreadInput —— 主线程正卡在 Lua 里, 挂接另一个线程的输入队列
-- 会当场死锁(实测表现为"一开输入框游戏就卡死")。只做 v3.11 已验证过的那三件事。
-- config.focus: 0 = 只显示不抢焦点(应急), 1 = 标准, 2 = 标准 + 显式 SetFocus
local function focus_box(hwnd)
    if hwnd == nil then return end
    local u = native.user32
    if u.hd2_IsWindow(hwnd) == 0 then return end
    local mode = tonumber(config.focus) or 1
    if mode <= 0 then return end
    u.hd2_BringWindowToTop(hwnd)
    u.hd2_SetForegroundWindow(hwnd)
    if mode >= 2 then
        u.hd2_SetFocus(hwnd)
    end
end

local function create_input_box()
    if box.created and not is_null(box.hwnd) then return true end

    local u = native.user32
    local class_edit = to_wide("EDIT")
    local title = to_wide("")

    -- 严格单行比例: 宽 960 / 高 48 / 字号 -28
    local screen_w = u.hd2_GetSystemMetrics(0)
    local screen_h = u.hd2_GetSystemMetrics(1)
    local box_w = 960
    local box_h = 48
    local box_x = math.floor((screen_w - box_w) / 2)
    local box_y = screen_h - 160 - box_h

    local WS_POPUP = 0x80000000
    local ES_AUTOHSCROLL = 0x0080
    local ES_LEFT = 0x0000
    local WS_EX_TOPMOST = 0x00000008
    local WS_EX_TOOLWINDOW = 0x00000080
    local WS_EX_LAYERED = 0x00080000

    box.hwnd = u.hd2_CreateWindowExW(
        bit.bor(WS_EX_TOPMOST, WS_EX_TOOLWINDOW, WS_EX_LAYERED),
        class_edit,
        title,
        bit.bor(WS_POPUP, ES_AUTOHSCROLL, ES_LEFT),
        box_x, box_y, box_w, box_h,
        nil, nil, nil, nil
    )

    if is_null(box.hwnd) then
        log_message("创建浮动输入框失败")
        return false
    end

    -- 显式绑定一个 IME 上下文, 让搜狗/微信/百度/QQ 输入法都认这个控件
    if native.imm32 then
        pcall(function()
            local imm = native.imm32
            box.himc = imm.hd2_ImmCreateContext()
            if not is_null(box.himc) then
                imm.hd2_ImmAssociateContext(box.hwnd, box.himc)
                imm.hd2_ImmSetOpenStatus(box.himc, 1)
            end
        end)
    end

    -- 轻薄黑色毛玻璃: alpha 125
    u.hd2_SetLayeredWindowAttributes(box.hwnd, 0, 125, 2) -- LWA_ALPHA = 2

    pcall(function()
        local policy = ffi.new("ACCENT_POLICY[1]")
        policy[0].AccentState = 4 -- ACCENT_ENABLE_ACRYLICBLURBEHIND
        policy[0].AccentFlags = 2
        policy[0].GradientColor = tonumber(0x441E1414)
        policy[0].AnimationId = 0

        local data = ffi.new("WINCOMPATTRDATA[1]")
        data[0].Attribute = 19 -- WCA_ACCENT_POLICY
        data[0].Data = policy
        data[0].SizeOfData = ffi.sizeof("ACCENT_POLICY")
        u.hd2_SetWindowCompositionAttribute(box.hwnd, data)
    end)

    if native.gdi32 then
        local bg_color = bit.bor(0x14, bit.lshift(0x14, 8), bit.lshift(0x1E, 16))
        box.brush = native.gdi32.hd2_CreateSolidBrush(bg_color)
    end

    apply_box_font()

    local EC_LEFTMARGIN = 0x0001
    local EC_RIGHTMARGIN = 0x0002
    local margins = bit.bor(16, bit.lshift(16, 16))
    u.hd2_SendMessageW(box.hwnd, 0x00D3, bit.bor(EC_LEFTMARGIN, EC_RIGHTMARGIN), margins)

    box.created = true
    u.hd2_ShowWindow(box.hwnd, 0) -- SW_HIDE
    log_message("已创建浮动输入框 " .. tostring(box.hwnd)
        .. " (960x48, 字体高度 " .. tostring(BOX_FONT_HEIGHT) .. ")")
    return true
end

-- 打开输入框的每一步都留痕(前若干次), 万一还卡死, 日志最后一行就是卡住的位置
-- restore_text = true 时把失焦前暂存的内容填回去
local function show_input_box(restore_text)
    trace("show.begin restore=" .. tostring(restore_text) .. " saved=" .. tostring(#box.saved_text))
    if not box.created and not create_input_box() then return end
    local u = native.user32
    if restore_text and box.saved_text ~= "" then
        set_box_text(box.saved_text)
    else
        clear_box_text()
    end
    trace("show.text-ok")
    box.saved_text = ""
    -- 每次弹出都回读一次字体: 万一被系统/DPI 变化重置, 这里会重新挂回去
    apply_box_font()
    u.hd2_ShowWindow(box.hwnd, 5) -- SW_SHOW
    trace("show.showwindow-ok")
    focus_box(box.hwnd)
    trace("show.focus-ok")
    if native.imm32 and box.himc then
        native.imm32.hd2_ImmSetOpenStatus(box.himc, 1)
        trace("show.ime-ok")
    end
    box.visible = true
    trace("show.done")
end

local function hide_input_box()
    if box.hwnd and box.visible then
        trace("hide.begin")
        native.user32.hd2_ShowWindow(box.hwnd, 0) -- SW_HIDE
        box.visible = false
        trace("hide.done")
    end
end

-- 失焦隐藏: 先记住内容, 不销毁、不清空
local function suspend_input_box()
    if box.hwnd and box.visible then
        box.saved_text = get_box_text()
        trace("suspend.saved=" .. tostring(#box.saved_text))
        native.user32.hd2_ShowWindow(box.hwnd, 0) -- SW_HIDE
        box.visible = false
        M.suspended = true
        trace("suspend.done")
    end
end

local function is_game_or_box_foreground()
    local fg = native.user32.hd2_GetForegroundWindow()
    if is_null(fg) then return false end
    if same_window(fg, box.hwnd) then return true end

    local pid = ffi.new("uint32_t[1]")
    native.user32.hd2_GetWindowThreadProcessId(fg, pid)
    return pid[0] == native.k32.hd2_GetCurrentProcessId()
end

-- -------------------------------------------------------------------------------------
-- 聊天状态与提交
-- -------------------------------------------------------------------------------------
local function chat_widget()
    local hud = pointer(read(native.base + V.hud, 8))
    return hud and (hud + V.chat_hud) or nil
end

local function is_chat_open(widget)
    local open = widget and read(widget + V.chat_open, 1)
    return open ~= nil and open:byte() ~= 0
end

local function send_text_to_chat(text)
    local widget = chat_widget()
    if not widget or not is_chat_open(widget) then
        log_message("聊天框已关闭, 放弃注入")
        return
    end

    local field = widget + V.chat_field
    local text_widget = field + V.field_widget

    fn.set_text(text_widget, text or "")
    log_message(string.format("注入聊天文本: '%s'", text or ""))

    local KEYEVENTF_KEYUP = 0x0002
    native.user32.hd2_keybd_event(0x0D, 0x1C, 0, 0)
    native.user32.hd2_keybd_event(0x0D, 0x1C, KEYEVENTF_KEYUP, 0)
end

-- 线程级消息泵: hwnd 传 nil, 第三方输入法的候选窗也能收到消息
local function pump_box_messages()
    if not box.visible or not box.hwnd then return end
    local msg = ffi.new("MSG[1]")
    local u = native.user32
    local g = native.gdi32
    local count = 0

    while u.hd2_PeekMessageW(msg, nil, 0, 0, 1) ~= 0 do -- PM_REMOVE = 1
        local m = msg[0].message
        local w = msg[0].wParam

        -- 丢弃 Enter(13)/Esc(27) 的 WM_CHAR, 消除单行框的 Windows "叮" 声
        local drop = false
        if msg[0].hwnd == box.hwnd and m == 0x0102 and (w == 13 or w == 10 or w == 27) then
            drop = true
        end

        if not drop then
            if (m == 0x0133 or m == 0x0138) and msg[0].hwnd == box.hwnd then
                if g and box.brush then
                    local dc = ffi.cast("HDC", w)
                    g.hd2_SetTextColor(dc, 0x00FFFFFF)
                    g.hd2_SetBkColor(dc, 0x001E1414)
                end
            end

            u.hd2_TranslateMessage(msg)
            u.hd2_DispatchMessageW(msg)
        end

        count = count + 1
        if count > 64 then break end
    end
end

-- -------------------------------------------------------------------------------------
-- 每帧更新
-- -------------------------------------------------------------------------------------
-- 纯状态机: 根据当前观测决定这一帧要做什么(便于离线测试)
--   suspend         失焦 → 记下内容后隐藏(关键: 不清空)
--   show_restore    重新获得焦点且聊天仍开着 → 显示并恢复内容
--   show_fresh      刚打开聊天 → 显示空输入条
--   hide_discard    聊天被关掉 → 隐藏并丢弃内容
--   clear_suspended 聊天已关但还留着挂起内容 → 清掉
--   none            什么都不做
local function decide(visible, focused, chat_open, suspended, cooled)
    if visible and not focused then return "suspend" end
    if chat_open and not visible and focused and cooled then
        if suspended then return "show_restore" end
        return "show_fresh"
    end
    if visible and not chat_open then return "hide_discard" end
    if not visible and not chat_open and suspended then return "clear_suspended" end
    return "none"
end

local function tick(dt)
    M.frames = M.frames + 1

    -- 菜单只轮询全局变量, 开销可忽略
    menu_poll(M.frames)

    -- 样式变化时刷新一次 STATUS(稳态不写盘)
    if M.frames % 120 == 0 then
        write_status(string.format("OK - %s | %s", MOD_VERSION, style_summary()))
    end

    local widget = chat_widget()
    local chat_open = is_chat_open(widget)
    local now = os.clock()
    local focused = is_game_or_box_foreground()

    local action = decide(box.visible, focused, chat_open, M.suspended, now >= M.cooldown_until)

    if action == "suspend" then
        log_message("失去焦点, 已暂存输入内容并隐藏输入条")
        suspend_input_box()
        return
    elseif action == "show_restore" then
        M.suspended = false
        log_message("重新获得焦点, 已恢复未发送的输入内容")
        show_input_box(true)
    elseif action == "show_fresh" then
        show_input_box(false)
    elseif action == "hide_discard" then
        hide_input_box()
        box.saved_text = ""
        M.suspended = false
    elseif action == "clear_suspended" then
        box.saved_text = ""
        M.suspended = false
    end

    if not box.visible then return end

    pump_box_messages()

    local u = native.user32
    local enter_down = u.hd2_GetAsyncKeyState(0x0D) < 0
    local esc_down = u.hd2_GetAsyncKeyState(0x1B) < 0

    local enter_hit = enter_down and not M.last_enter
    local esc_hit = esc_down and not M.last_esc
    M.last_enter = enter_down
    M.last_esc = esc_down

    local composing = is_ime_composing()

    -- 输入法正在选字时, Enter 只用于上屏, 不触发发送
    if composing then return end

    if enter_hit then
        local text = get_box_text()
        local payload = decorate(text)
        hide_input_box()
        clear_box_text()
        box.saved_text = ""
        M.suspended = false
        M.cooldown_until = now + 0.35
        send_text_to_chat(payload)
    elseif esc_hit then
        hide_input_box()
        clear_box_text()
        box.saved_text = ""
        M.suspended = false
        M.cooldown_until = now + 0.25
        send_text_to_chat("")
    end
end

-- -------------------------------------------------------------------------------------
-- Mod Entry
-- -------------------------------------------------------------------------------------
local function start()
    M.started = true

    local ok_nat, why_nat = init_native()
    if not ok_nat then
        write_status("NOT AVAILABLE - " .. why_nat)
        log_message("初始化失败: " .. tostring(why_nat))
        M.retired = true
        return
    end

    local ok_res, why_res = resolve_sigs()
    if not ok_res then
        write_status("NOT AVAILABLE - " .. why_res)
        log_message("特征码校验失败: " .. tostring(why_res))
        M.retired = true
        return
    end

    config = load_config()
    create_input_box()

    M.ready = true
    log_message(string.format("ChineseInputFix v%s 已加载", MOD_VERSION))
    write_status(string.format("OK - %s | %s", MOD_VERSION, style_summary()))
end

local original_update = rawget(_G, "update")
local my_update
my_update = function(dt, ...)
    if not M.retired then
        if not M.started then
            local ok, err = pcall(start)
            if not ok then
                M.retired = true
                write_status("STOPPED - 启动异常: " .. tostring(err))
                log_message("启动异常: " .. tostring(err))
            end
        elseif M.ready then
            local ok, err = pcall(tick, dt)
            if not ok then
                M.errors = M.errors + 1
                if M.errors <= 3 then
                    log_message("tick 异常: " .. tostring(err))
                end
                if M.errors >= 10 then
                    M.retired = true
                    write_status("STOPPED - 重复异常: " .. tostring(err))
                end
            end
        end
    end

    if type(original_update) == "function" then
        return original_update(dt, ...)
    end
end
update = my_update

-- 安全退钩: 仅当自己仍是顶层包装者时才还原, 避免截断后续 mod 的 update 链
M.retire_hook = function()
    M.retired = true
    if update == my_update then
        update = original_update
    end
end

return {
    installed = true,
    version = MOD_VERSION,
    -- 供离线测试的纯函数与状态
    _test = {
        build_markup = build_markup,
        compute_style = compute_style,
        parse_ini_text = parse_ini_text,
        color_choices = COLOR_CHOICES,
        color_presets = COLOR_PRESETS,
        custom_choice = CUSTOM_CHOICE,
        decorate = decorate,
        resolve_style = resolve_style,
        decide = decide,
        poll_menu = menu_poll,
        menu = menu,
        option_specs = option_specs,
        set_config = function(values) config = values or {} end,
        set_frames = function(n) M.frames = n end,
    },
}
