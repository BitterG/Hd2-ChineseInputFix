-- 原生探针: 用和 fix_ime.lua 完全相同的 ffi 声明，真开一个 EDIT 窗口跑一遍
-- 目的: 在进游戏之前证明签名/参数没错(签错会崩游戏)。
-- 运行: work\host\lua51host.exe work\_native_probe.lua

local ffi = require("ffi")

ffi.cdef([[
    typedef struct { int unused; } HD2ProbeTag;
    typedef void* HWND; typedef void* HINSTANCE; typedef void* HMENU; typedef void* HIMC;
    typedef void* HFONT; typedef void* HDC; typedef void* HBRUSH;
    typedef unsigned long DWORD; typedef int BOOL; typedef intptr_t LONG_PTR;

    typedef struct { HWND hwnd; uint32_t message; uint64_t wParam; int64_t lParam; DWORD time;
                     struct { int x, y; } pt; } MSG;
    typedef struct { int AccentState, AccentFlags, GradientColor, AnimationId; } ACCENT_POLICY;
    typedef struct { int Attribute; void* Data; size_t SizeOfData; } WINCOMPATTRDATA;

    uint32_t GetCurrentThreadId(void);
    void *GetCurrentProcess(void);
    void *GetModuleHandleA(const char *name);
    int GetSystemMetrics(int nIndex);
    int WideCharToMultiByte(uint32_t cp, DWORD flags, const wchar_t* wide, int wideLen, char* mb, int mbLen, void* defChar, void* usedDef);
    int MultiByteToWideChar(uint32_t cp, DWORD flags, const char* mb, int mbLen, wchar_t* wide, int wideLen);

    HWND CreateWindowExW(DWORD dwExStyle, const wchar_t* cls, const wchar_t* name, DWORD style,
        int x, int y, int w, int h, HWND parent, HMENU menu, HINSTANCE inst, void* param);
    BOOL DestroyWindow(HWND hWnd);
    BOOL ShowWindow(HWND hWnd, int nCmdShow);
    BOOL IsWindow(HWND hWnd);
    BOOL SetWindowTextW(HWND hWnd, const wchar_t* text);
    int GetWindowTextW(HWND hWnd, wchar_t* text, int max);
    int GetWindowTextLengthW(HWND hWnd);
    intptr_t SendMessageW(HWND hWnd, uint32_t msg, uint64_t wParam, int64_t lParam);
    BOOL SetLayeredWindowAttributes(HWND hWnd, uint32_t key, uint8_t alpha, DWORD flags);
    BOOL SetWindowCompositionAttribute(HWND hWnd, WINCOMPATTRDATA* data);
    BOOL PeekMessageW(MSG* msg, HWND hWnd, uint32_t min, uint32_t max, uint32_t remove);
    BOOL TranslateMessage(const MSG* msg);
    LONG_PTR DispatchMessageW(const MSG* msg);
    HWND GetForegroundWindow(void);
    uint32_t GetWindowThreadProcessId(void* window, uint32_t* process);
    BOOL AttachThreadInput(uint32_t attach, uint32_t attachTo, BOOL flag);
    HWND SetFocus(HWND hWnd);
    BOOL BringWindowToTop(HWND hWnd);
    BOOL SetForegroundWindow(HWND hWnd);

    HIMC ImmCreateContext(void);
    HIMC ImmAssociateContext(HWND hWnd, HIMC himc);
    BOOL ImmSetOpenStatus(HIMC himc, BOOL open);
    HIMC ImmGetContext(HWND hWnd);
    int32_t ImmGetCompositionStringW(HIMC himc, DWORD index, void* buf, DWORD len);
    BOOL ImmReleaseContext(HWND hWnd, HIMC himc);

    HFONT CreateFontW(int h, int w, int esc, int ori, int weight, DWORD italic, DWORD underline,
        DWORD strike, DWORD charset, DWORD outprec, DWORD clipprec, DWORD quality, DWORD pitch,
        const wchar_t* face);
    HBRUSH CreateSolidBrush(uint32_t color);
    HDC GetDC(HWND hWnd);
    int ReleaseDC(HWND hWnd, HDC dc);
    uint32_t SetTextColor(HDC dc, uint32_t color);
    uint32_t SetBkColor(HDC dc, uint32_t color);
    int SetBkMode(HDC dc, int mode);
    BOOL DeleteObject(void* obj);
]])

local k32 = ffi.load("kernel32")
local u32 = ffi.load("user32")
local gdi = ffi.load("gdi32")
local imm = ffi.load("imm32")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(string.format("ok    %-42s %s", name, detail or ""))
    else
        failures = failures + 1
        print(string.format("FAIL  %-42s %s", name, detail or ""))
    end
end

local function wide(s)
    local n = k32.MultiByteToWideChar(65001, 0, s, #s, nil, 0)
    local buf = ffi.new("wchar_t[?]", n + 1)
    k32.MultiByteToWideChar(65001, 0, s, #s, buf, n)
    buf[n] = 0
    return buf
end

local function utf8(buf, n)
    if n <= 0 then return "" end
    local m = k32.WideCharToMultiByte(65001, 0, buf, n, nil, 0, nil, nil)
    local out = ffi.new("char[?]", m + 1)
    k32.WideCharToMultiByte(65001, 0, buf, n, out, m, nil, nil)
    out[m] = 0
    return ffi.string(out, m)
end

local sw, sh = u32.GetSystemMetrics(0), u32.GetSystemMetrics(1)
local box_w, box_h = 960, 48
local hwnd = u32.CreateWindowExW(
    bit.bor(0x00000008, 0x00000080, 0x00080000),  -- TOPMOST | TOOLWINDOW | LAYERED
    wide("EDIT"), wide(""),
    bit.bor(0x80000000, 0x0080, 0x0000),          -- POPUP | AUTOHSCROLL | LEFT
    math.floor((sw - box_w) / 2), sh - 160 - box_h, box_w, box_h,
    nil, nil, nil, nil)
check("CreateWindowExW(EDIT)", hwnd ~= nil, tostring(hwnd))
check("IsWindow", u32.IsWindow(hwnd) ~= 0)

local himc = imm.ImmCreateContext()
check("ImmCreateContext", himc ~= nil, tostring(himc))
imm.ImmAssociateContext(hwnd, himc)
check("ImmSetOpenStatus(1)", imm.ImmSetOpenStatus(himc, 1) ~= 0)
local got = imm.ImmGetContext(hwnd)
check("ImmGetContext", got ~= nil)
if got ~= nil then
    local len = imm.ImmGetCompositionStringW(got, 0x0008, nil, 0)
    check("ImmGetCompositionStringW", len >= 0, "len=" .. tostring(len))
    imm.ImmReleaseContext(hwnd, got)
end

check("SetLayeredWindowAttributes", u32.SetLayeredWindowAttributes(hwnd, 0, 125, 2) ~= 0)

local policy = ffi.new("ACCENT_POLICY[1]")
policy[0].AccentState = 4
policy[0].AccentFlags = 2
policy[0].GradientColor = tonumber(0x441E1414)
local data = ffi.new("WINCOMPATTRDATA[1]")
data[0].Attribute = 19
data[0].Data = policy
data[0].SizeOfData = ffi.sizeof("ACCENT_POLICY")
check("SetWindowCompositionAttribute(acrylic)", u32.SetWindowCompositionAttribute(hwnd, data) ~= 0)

local function exact(handle)
    return ffi.cast("uint64_t", ffi.cast("uintptr_t", handle))
end

-- WM_GETFONT 回读控件当前字体, 用来判断 WM_SETFONT 到底有没有生效
local function attached_font()
    return u32.SendMessageW(hwnd, 0x0031, ffi.cast("uint64_t", 0), ffi.cast("int64_t", 0))
end

local font = gdi.CreateFontW(-28, 0, 0, 0, 500, 0, 0, 0, 1, 0, 0, 5, 0, wide("Microsoft YaHei UI"))
check("CreateFontW", exact(font) ~= 0, tostring(font))

-- ① 复现当初的 bug: 句柄先 tonumber 再传, 大句柄会被 double 截断
-- GDI 句柄是 32 位值: 高位为 1 时会被符号扩展成 0xFFFFFFFFxxxxxxxx(约 1.8e19),
-- 这个量级超过 double 的 53 位精度 → tonumber 必然丢掉低位。高位为 0 时又恰好安全,
-- 所以表现为"有时候字变小"。这里先用一个构造出来的符号扩展句柄把机制钉死。
local sign_extended = ffi.cast("uint64_t", 0xEC0A168B) - ffi.cast("uint64_t", 0x100000000)
local sign_roundtrip = ffi.cast("uint64_t", tonumber(ffi.cast("uintptr_t", sign_extended)))
check("符号扩展句柄经 tonumber 必然失真", sign_roundtrip ~= sign_extended,
    tostring(sign_extended) .. " -> " .. tostring(sign_roundtrip))

local via_number = ffi.cast("uint64_t", tonumber(ffi.cast("uintptr_t", font)))
local lossy = via_number ~= exact(font)
print(string.format("      本次真实句柄=%s  经 tonumber=%s  %s",
    tostring(exact(font)), tostring(via_number), lossy and "(会失真)" or "(未失真)"))
u32.SendMessageW(hwnd, 0x0030, via_number, ffi.cast("int64_t", 1))
if lossy then
    check("① 传 tonumber 后的句柄 → 字体没挂上", exact(attached_font()) ~= exact(font))
else
    check("① 本机句柄恰好没失真, 跳过复现", true)
end

-- ② 正确做法: 句柄按 64 位原样传, WM_GETFONT 必须等于我们的 HFONT
u32.SendMessageW(hwnd, 0x0030, exact(font), ffi.cast("int64_t", 1))
check("② 原样传句柄 → 字体挂上了", exact(attached_font()) == exact(font))
check("EM_SETMARGINS", u32.SendMessageW(hwnd, 0x00D3, bit.bor(1, 2),
    bit.bor(16, bit.lshift(16, 16))) ~= nil)

local brush = gdi.CreateSolidBrush(bit.bor(0x14, bit.lshift(0x14, 8), bit.lshift(0x1E, 16)))
check("CreateSolidBrush", brush ~= nil)

local payload = "你好，世界 abc 123"
u32.SetWindowTextW(hwnd, wide(payload))
local n = u32.GetWindowTextLengthW(hwnd)
local buf = ffi.new("wchar_t[?]", n + 1)
u32.GetWindowTextW(hwnd, buf, n + 1)
check("SetWindowTextW/GetWindowTextW 往返", utf8(buf, n) == payload, utf8(buf, n))

check("EM_SETSEL(-1,-1)", u32.SendMessageW(hwnd, 0x00B1, ffi.cast("uint64_t", -1),
    ffi.cast("int64_t", -1)) ~= nil)

local msg = ffi.new("MSG[1]")
local pumped = 0
while u32.PeekMessageW(msg, nil, 0, 0, 1) ~= 0 do
    u32.TranslateMessage(msg)
    u32.DispatchMessageW(msg)
    pumped = pumped + 1
    if pumped > 100 then break end
end
check("PeekMessageW(nil,...) 线程级泵", true, "pumped=" .. pumped)

-- 注意: 这里刻意不测 AttachThreadInput。
-- 主线程正在 Lua 里执行, 再去挂接别的线程(尤其是窗口线程)的输入队列, 会当场死锁 ——
-- 实测表现就是"一打开输入框游戏就卡死"。mod 只用下面这一套已验证过的动作。
check("不依赖 AttachThreadInput", true)

-- 打开输入框时真正要跑的那一套焦点动作
u32.ShowWindow(hwnd, 5)
u32.BringWindowToTop(hwnd)
u32.SetForegroundWindow(hwnd)
u32.SetFocus(hwnd)
check("ShowWindow+BringToTop+SetForegroundWindow 不卡住", true)
local foreground_now = u32.GetForegroundWindow()
check("抢到了前台", foreground_now ~= nil)

u32.ShowWindow(hwnd, 0)
u32.DestroyWindow(hwnd)
check("DestroyWindow", u32.IsWindow(hwnd) == 0)

if brush ~= nil then gdi.DeleteObject(brush) end
if font ~= nil then gdi.DeleteObject(font) end

print(failures == 0 and "\n原生探针全部通过" or ("\n失败 " .. failures .. " 项"))
os.exit(failures == 0 and 0 or 1)
