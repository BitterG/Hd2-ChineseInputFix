-- HD2-Addon: mods/chinese_input_fix/fix_ime
-- Chinese Input Fix (In-Game Overlay Mode v3.11 - Universal IME & Perfect Proportions) for Helldivers 2
-- 1. Single-line proportion perfection: 48px height, -30 font height, tight vertical centering.
-- 2. Full Third-party IME Support (Sogou, Wechat IME, Baidu, QQ, Microsoft Pinyin, etc.):
--    - Uses ES_AUTOHSCROLL (clean single-line edit)
--    - Explicit ImmAssociateContext + ImmSetOpenStatus activation
--    - Processes thread-wide messages (hwnd=0 in PeekMessage) so IME floating UI receives input
-- 3. Ultra-sheer dark glass with Acrylic blur
-- 4. Silent Enter/Esc handling (Zero Windows Ding)
-- 5. Unified send/close pipeline

if rawget(_G, "__HD2_CHINESE_INPUT_OVERLAY_MOD") then
    return { installed = true, version = "3.11.0" }
end

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or not ffi or ffi.os ~= "Windows" or not ffi.abi("64bit") then
    return { installed = false, reason = "Windows x64 LuaJIT required" }
end

local M = {
    version = "3.11.0",
    started = false,
    ready = false,
    retired = false,
    errors = 0,
    was_chat_open = false,
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
-- Logging
-- -------------------------------------------------------------------------------------
local function log_message(msg)
    local dir = os.getenv("LOCALAPPDATA")
    local path = dir and (dir .. "/CowboyBingus/Helldivers2/Logs/ChineseInputFix.log") or "ChineseInputFix.log"
    pcall(function()
        local f = io.open(path, "a")
        if f then
            f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
            f:close()
        end
    end)
end

local function write_status(line)
    local dir = os.getenv("LOCALAPPDATA")
    local path = dir and (dir .. "/CowboyBingus/Helldivers2/Logs/ChineseInputFix_STATUS.txt") or "ChineseInputFix_STATUS.txt"
    pcall(function()
        local f = io.open(path, "w")
        if f then
            f:write(line .. "\n")
            f:close()
        end
    end)
end

-- -------------------------------------------------------------------------------------
-- Floating Input Box (Single-Line Proportions + Universal IME Support)
-- -------------------------------------------------------------------------------------
local box = {
    hwnd = nil,
    created = false,
    visible = false,
    font = nil,
    brush = nil,
    himc = nil,
}

local function is_ime_composing()
    if not box.hwnd or not native.imm32 then return false end
    local himc = native.imm32.hd2_ImmGetContext(box.hwnd)
    if himc == nil then return false end
    local len = native.imm32.hd2_ImmGetCompositionStringW(himc, 0x0008, nil, 0)
    native.imm32.hd2_ImmReleaseContext(box.hwnd, himc)
    return len > 0
end

local function get_box_text()
    if not box.hwnd then return "" end
    local len = native.user32.hd2_GetWindowTextLengthW(box.hwnd)
    if len <= 0 then return "" end
    local buf = ffi.new("wchar_t[?]", len + 1)
    native.user32.hd2_GetWindowTextW(box.hwnd, buf, len + 1)
    return to_utf8(buf, len)
end

local function clear_box_text()
    if box.hwnd then
        native.user32.hd2_SetWindowTextW(box.hwnd, to_wide(""))
    end
end

local function create_input_box()
    if box.created and box.hwnd ~= nil then return true end

    local u = native.user32
    local class_edit = to_wide("EDIT")
    local title = to_wide("")

    -- Proportions: Strict single-line aesthetic
    -- Width: 960px, Height: 48px, Font: -28px (Fills box proportionally with no empty vertical waste)
    local screen_w = u.hd2_GetSystemMetrics(0)
    local screen_h = u.hd2_GetSystemMetrics(1)
    local box_w = 960
    local box_h = 48
    local box_x = math.floor((screen_w - box_w) / 2)
    local box_y = screen_h - 160 - box_h

    -- Pure single-line control: ES_AUTOHSCROLL | ES_LEFT
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

    if box.hwnd == nil then
        log_message("Failed to create styled input box")
        return false
    end

    -- Universal IME Binding: Explicitly attach and activate an IME Context on this edit HWND
    -- This guarantees Sogou, Wechat IME, Baidu, QQ etc. recognize the focus target as an active IME window!
    if native.imm32 then
        pcall(function()
            local imm = native.imm32
            box.himc = imm.hd2_ImmCreateContext()
            if box.himc ~= nil then
                imm.hd2_ImmAssociateContext(box.hwnd, box.himc)
                imm.hd2_ImmSetOpenStatus(box.himc, 1) -- Keep IME open for typing
            end
        end)
    end

    -- Sleek sheer glass: alpha 125
    u.hd2_SetLayeredWindowAttributes(box.hwnd, 0, 125, 2) -- LWA_ALPHA = 2

    -- Subtle dark acrylic blur
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

    -- Dark brush & Proportionate font (-28 height, bold 500)
    if native.gdi32 then
        local bg_color = bit.bor(0x14, bit.lshift(0x14, 8), bit.lshift(0x1E, 16))
        box.brush = native.gdi32.hd2_CreateSolidBrush(bg_color)

        local font_name = to_wide("Microsoft YaHei UI")
        box.font = native.gdi32.hd2_CreateFontW(
            -28, 0, 0, 0, 500,
            0, 0, 0, 1, 0, 0, 5,
            0, font_name
        )
        if box.font ~= nil then
            local WM_SETFONT = 0x0030
            u.hd2_SendMessageW(box.hwnd, WM_SETFONT, tonumber(ffi.cast("uintptr_t", box.font)), 1)
        end
    end

    -- Comfortable margins: 16px horizontal padding
    local EC_LEFTMARGIN = 0x0001
    local EC_RIGHTMARGIN = 0x0002
    local margins = bit.bor(16, bit.lshift(16, 16))
    u.hd2_SendMessageW(box.hwnd, 0x00D3, bit.bor(EC_LEFTMARGIN, EC_RIGHTMARGIN), margins)

    box.created = true
    u.hd2_ShowWindow(box.hwnd, 0) -- SW_HIDE
    log_message(string.format("Created single-line input box hwnd: 0x%x (48px height, font -28)",
        tonumber(ffi.cast("uintptr_t", box.hwnd))))
    return true
end

local function show_input_box()
    if not box.created and not create_input_box() then return end
    clear_box_text()
    native.user32.hd2_ShowWindow(box.hwnd, 5) -- SW_SHOW
    native.user32.hd2_BringWindowToTop(box.hwnd)
    native.user32.hd2_SetForegroundWindow(box.hwnd)
    native.user32.hd2_SetFocus(box.hwnd)
    if native.imm32 and box.himc then
        native.imm32.hd2_ImmSetOpenStatus(box.himc, 1)
    end
    box.visible = true
end

local function hide_input_box()
    if box.hwnd and box.visible then
        native.user32.hd2_ShowWindow(box.hwnd, 0) -- SW_HIDE
        box.visible = false
    end
end

-- Foreground window check for Alt-Tab auto-hide
local function is_game_or_box_foreground()
    local fg = native.user32.hd2_GetForegroundWindow()
    if fg == nil then return false end
    if fg == box.hwnd then return true end

    local pid = ffi.new("uint32_t[1]")
    native.user32.hd2_GetWindowThreadProcessId(fg, pid)
    return pid[0] == native.k32.hd2_GetCurrentProcessId()
end

-- -------------------------------------------------------------------------------------
-- Chat State & Ingestion
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
    if not widget or not is_chat_open(widget) then return end

    local field = widget + V.chat_field
    local text_widget = field + V.field_widget

    -- Clean native set_text call
    fn.set_text(text_widget, text or "")
    log_message(string.format("Injected chat text: '%s'", text or ""))

    -- Verified game submit keybd_event
    local KEYEVENTF_KEYUP = 0x0002
    native.user32.hd2_keybd_event(0x0D, 0x1C, 0, 0)
    native.user32.hd2_keybd_event(0x0D, 0x1C, KEYEVENTF_KEYUP, 0)
end

-- Thread-wide message pump (hwnd = nil) so candidate windows of Sogou/WeChat IME receive messages
local function pump_box_messages()
    if not box.visible or not box.hwnd then return end
    local msg = ffi.new("MSG[1]")
    local u = native.user32
    local g = native.gdi32
    local count = 0

    -- Passing nil to PeekMessageW processes messages for both edit box AND IME candidate popup windows!
    while u.hd2_PeekMessageW(msg, nil, 0, 0, 1) ~= 0 do -- PM_REMOVE = 1
        local m = msg[0].message
        local w = msg[0].wParam

        -- Drop Enter (13) and Escape (27) to eliminate Windows 'Ding' sound on single-line edit
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
-- Frame Update Controller
-- -------------------------------------------------------------------------------------
local function tick(dt)
    local widget = chat_widget()
    local chat_open = is_chat_open(widget)
    local now = os.clock()

    -- 1. Auto-hide quietly if player Alt-Tabs away
    if box.visible and not is_game_or_box_foreground() then
        hide_input_box()
        M.was_chat_open = false
        return
    end

    -- 2. Check if user just opened chat in-game (instant show)
    if chat_open and not M.was_chat_open and now >= M.cooldown_until then
        if is_game_or_box_foreground() then
            M.was_chat_open = true
            show_input_box()
        end
    elseif not chat_open and M.was_chat_open then
        M.was_chat_open = false
        hide_input_box()
    end

    if not box.visible then return end

    -- Thread-wide zero-delay message pump for all IME candidates
    pump_box_messages()

    local u = native.user32
    local enter_down = u.hd2_GetAsyncKeyState(0x0D) < 0
    local esc_down = u.hd2_GetAsyncKeyState(0x1B) < 0

    local enter_hit = enter_down and not M.last_enter
    local esc_hit = esc_down and not M.last_esc
    M.last_enter = enter_down
    M.last_esc = esc_down

    local composing = is_ime_composing()

    -- Only send or cancel when IME candidate window is NOT in composition
    if not composing then
        if enter_hit then
            local text = get_box_text()
            hide_input_box()
            M.cooldown_until = now + 0.35
            send_text_to_chat(text)
        elseif esc_hit then
            hide_input_box()
            M.cooldown_until = now + 0.25
            send_text_to_chat("")
        end
    end
end

-- -------------------------------------------------------------------------------------
-- Mod Entry & Hook
-- -------------------------------------------------------------------------------------
local function start()
    M.started = true
    local ok_nat, why_nat = init_native()
    if not ok_nat then
        write_status("NOT AVAILABLE - " .. why_nat)
        M.retired = true
        return
    end

    local ok_res, why_res = resolve_sigs()
    if not ok_res then
        write_status("NOT AVAILABLE - " .. why_res)
        M.retired = true
        return
    end

    create_input_box()
    M.ready = true
    log_message("ChineseInputFix v3.11.0 (Universal IME & Single Line) loaded successfully")
    write_status("OK - ChineseInputFix active (Universal IME & Single Line)")
end

local original_update = rawget(_G, "update")
update = function(dt, ...)
    if not M.retired then
        if not M.started then
            start()
        elseif M.ready then
            local ok_step, err = pcall(tick, dt)
            if not ok_step then
                M.errors = M.errors + 1
                if M.errors >= 10 then
                    M.retired = true
                    write_status("STOPPED - repeated errors: " .. tostring(err))
                end
            end
        end
    end

    if type(original_update) == "function" then
        return original_update(dt, ...)
    end
end

return {
    installed = true,
    version = M.version,
}
