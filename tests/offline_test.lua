-- 离线测试: 用任意 LuaJIT(带 ffi) 直接跑, 不需要进游戏。
--   lua51host.exe ChineseInputFix-v3.15.1\tests\offline_test.lua
-- 覆盖: 颜色/字号纯函数、ini 解析、模组菜单注册与取值、失焦保留状态机。
-- 退出码非 0 表示有用例失败。

local function script_dir()
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        local path = source:sub(2)
        local dir = path:match("^(.*)[/\\][^/\\]*$")
        if dir then return dir end
    end
    if arg and arg[0] then
        local dir = arg[0]:match("^(.*)[/\\][^/\\]*$")
        if dir then return dir end
    end
    return "."
end

local here = script_dir()
local SRC = here .. "/../Source/mods/chinese_input_fix/fix_ime.lua"

-- 每次 reload 都清掉模块自锁, 这样才能测多种菜单加载顺序
local function reload()
    rawset(_G, "__HD2_CHINESE_INPUT_OVERLAY_MOD", nil)
    local ok, mod = pcall(dofile, SRC)
    if not ok or type(mod) ~= "table" then
        print("FAIL 无法加载源码: " .. tostring(mod))
        os.exit(1)
    end
    if not mod._test then
        print("FAIL 源码没有暴露 _test 表")
        os.exit(1)
    end
    return mod._test, mod
end

local t, mod = reload()
local failures, total = 0, 0

local function check(name, got, want)
    total = total + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %-46s got=%s want=%s", name, tostring(got), tostring(want)))
    end
end

local function group(title)
    io.write("\n== " .. title .. " ==\n")
end

group("颜色/字号")
check("版本号", mod.version, "3.15.1")
check("预设色数量", #t.color_presets, 9)
check("选项数量", #t.color_choices, 11)
check("自定义是最后一项", t.color_choices[t.custom_choice], "自定义")

local argb, size = t.compute_style(2, nil, nil, nil, nil, 0)
check("红色", argb, "FFFF3B30")
check("默认不调字号", size, nil)
argb = t.compute_style(1, nil, nil, nil, nil, 0)
check("关闭颜色", argb, nil)
argb = t.compute_style(t.custom_choice, 128, 0, 255, 0, 0)
check("自定义 ARGB", argb, "8000FF00")
argb = t.compute_style(t.custom_choice, 999, -5, 300, 12.6, 0)
check("自定义钳制", argb, "FF00FF0D")
_, size = t.compute_style(nil, nil, nil, nil, nil, 42, nil)
check("字号 42", size, 42)
_, size = t.compute_style(nil, nil, nil, nil, nil, -3, nil)
check("负数字号关闭", size, nil)
_, size = t.compute_style(nil, nil, nil, nil, nil, 9999, nil)
check("字号钳制 99", size, 99)
_, size = t.compute_style(nil, nil, nil, nil, nil, 100, nil)
check("字号 100 也钳到 99", size, 99)
argb = t.compute_style(nil, nil, nil, nil, nil, 0, "ff00ff00")
check("ini 十六进制", argb, "FF00FF00")
argb = t.compute_style(nil, nil, nil, nil, nil, 0, "zzz")
check("ini 非法十六进制忽略", argb, nil)

group("标记拼接")
check("颜色+字号", t.build_markup("FFFF3B30", 20, "测试"), "<c=FFFF3B30><s=20>测试")
check("仅颜色", t.build_markup("FF0000FF", nil, "hi"), "<c=FF0000FF>hi")
check("仅字号", t.build_markup(nil, 32, "hi"), "<s=32>hi")
check("都不加", t.build_markup(nil, nil, "hi"), "hi")
check("空文本不加标记", t.build_markup("FF0000FF", 20, ""), "")
check("小写自动转大写", t.build_markup("ff00ff00", 0, "x"), "<c=FF00FF00>x")
check("后缀收尾", t.build_markup("FF00FF00", 0, "x", "</c>"), "<c=FF00FF00>x</c>")

group("ini 解析")
local cfg = t.parse_ini_text("# 注释\ncolor = FFFF0000\nsize= 18 \nsuffix = </c>\n; 也跳过\n")
check("color", cfg.color, "FFFF0000")
check("size", cfg.size, "18")
check("suffix", cfg.suffix, "</c>")
check("注释键不存在", cfg["# 注释"], nil)

group("菜单文案")
-- 游戏字体没有这些全角标点, 显示出来是问号(用户实测「自定义」变成了 ?自定义?)
local banned = {"「", "」", "·", "—", "‘", "’", "“", "”", "…"}
local function clean(text)
    if type(text) ~= "string" then return tostring(text) end
    for _, ch in ipairs(banned) do
        if text:find(ch, 1, true) then return "含禁用字符 " .. ch end
    end
    return true
end
for _, spec in ipairs(t.option_specs()) do
    check("label " .. spec.key .. " 无禁用字符", clean(spec.label), true)
    check("description " .. spec.key .. " 无禁用字符", clean(spec.description), true)
    check("description " .. spec.key .. " 不超 400 字节", #spec.description <= 400, true)
end
for _, name in ipairs(t.color_choices) do
    check("颜色选项名 " .. name .. " 无禁用字符", clean(name), true)
end

group("模组菜单")

-- 按 Mod Options Menu v1 (api 1) 的文档约定做假菜单
local function make_menu(opts)
    opts = opts or {}
    local state = {
        saved = opts.saved or {},
        callbacks = {},
        ready = opts.ready ~= false,
        specs = {},
        reject_reason = opts.reject_reason or "not ready",
    }
    local menu = {api = opts.api or 1}
    function menu.register_option(id, spec)
        if type(id) ~= "string" or type(spec) ~= "table" then return false, "bad spec" end
        if type(spec.label) ~= "string" or type(spec.mod) ~= "string" then return false, "bad spec" end
        if state.reject_mod and spec.mod == state.reject_mod then
            return false, "category rejected"
        end
        if spec.type ~= "choice" and spec.type ~= "slider" and spec.type ~= "toggle" then
            return false, "bad type"
        end
        if spec.type == "choice" then
            if type(spec.choices) ~= "table" or #spec.choices < 2 or #spec.choices > 16 then
                return false, "bad choices"
            end
        elseif spec.type == "slider" then
            if not (tonumber(spec.min) and tonumber(spec.max) and spec.min < spec.max) then
                return false, "bad range"
            end
            local step = tonumber(spec.step) or 1
            if step <= 0 or step > (spec.max - spec.min) then return false, "bad step" end
        elseif type(spec.default) ~= "boolean" then
            return false, "toggle needs a boolean default"
        end
        if not state.ready then return false, state.reject_reason end
        if state.saved[id] == nil then state.saved[id] = spec.default end
        state.specs[id] = spec
        return true
    end
    function menu.get(id) return state.saved[id] end
    function menu.on_change(id, fn)
        state.callbacks[id] = state.callbacks[id] or {}
        table.insert(state.callbacks[id], fn)
        return true
    end
    function menu.apply(id, value)
        state.saved[id] = value
        for _, fn in ipairs(state.callbacks[id] or {}) do fn(value, id) end
    end
    return menu, state
end

-- 1) 菜单还没加载
rawset(_G, "ModOptionsMenu", nil)
t, mod = reload()
t.set_frames(10)
t.poll_menu(10)
check("菜单缺失时先等待", t.menu.state, "waiting")

-- 1b) 头 1.5 秒不碰菜单(让游戏先把 MODS 标签搭好)
local early_menu, early_state = make_menu()
rawset(_G, "ModOptionsMenu", early_menu)
t.set_frames(60)
t.poll_menu(60)
check("前 90 帧不注册", t.menu.attempts, 0)
check("前 90 帧仍是等待", t.menu.state, "waiting")
t.set_frames(120)
t.poll_menu(120)
check("过了 90 帧才注册", t.menu.state, "ready")
check("注册后 attempts 递增", t.menu.attempts, 1)

-- 2) 菜单晚于 mod 加载
rawset(_G, "ModOptionsMenu", nil)
t, mod = reload()
t.set_frames(120)
t.poll_menu(120)
check("菜单缺失时先等待", t.menu.state, "waiting")
local late_menu = make_menu()
rawset(_G, "ModOptionsMenu", late_menu)
t.set_frames(200)
t.poll_menu(200)
check("菜单晚到也能接入", t.menu.state, "ready")

-- 3) 菜单刚出现还没准备好 → 重试后成功
rawset(_G, "ModOptionsMenu", nil)
t, mod = reload()
local retry_menu, retry_state = make_menu({ready = false})
rawset(_G, "ModOptionsMenu", retry_menu)
t.set_frames(120)
t.poll_menu(120)
check("首次注册失败不放弃", t.menu.state, "waiting")
check("失败时不标记已注册", t.menu.registered.color, nil)
retry_state.ready = true
t.set_frames(400)
t.poll_menu(400)
check("重试后接入成功", t.menu.state, "ready")
check("重试后颜色已注册", t.menu.registered.color, true)

-- 4) api 不兼容
rawset(_G, "ModOptionsMenu", {api = 2, register_option = function() return true end})
t, mod = reload()
t.set_frames(120)
t.poll_menu(120)
check("api 2 判为不可用", t.menu.state, "unavailable")

-- 5) 完整契约: 读回已保存值 + APPLY 回调
rawset(_G, "ModOptionsMenu", nil)
t, mod = reload()
local live, live_state = make_menu({saved = {
    ["chinese_input_fix.color"] = 5,      -- 绿色
    ["chinese_input_fix.size_on"] = true, -- 字号开关打开
    ["chinese_input_fix.size"] = 30,
}})
rawset(_G, "ModOptionsMenu", live)
t.set_frames(300)
t.poll_menu(300)
check("注册成功", t.menu.state, "ready")
check("默认用 ASCII 分类名", t.menu.mod_name, "CHINESE INPUT FIX")
check("四个滑块都注册", tostring(t.menu.registered.alpha) .. tostring(t.menu.registered.red)
    .. tostring(t.menu.registered.green) .. tostring(t.menu.registered.blue), "truetruetruetrue")
check("字号开关已注册", t.menu.registered.size_on, true)
check("读回已保存的颜色", (t.resolve_style()), "FF30D158")
local _, saved_size = t.resolve_style()
check("读回已保存的字号", saved_size, 30)
check("端到端标记", t.decorate("你好"), "<c=FF30D158><s=30>你好")

live.apply("chinese_input_fix.color", 3)          -- 橙色
check("APPLY 切橙色", (t.resolve_style()), "FFFF9500")
live.apply("chinese_input_fix.color", t.custom_choice)
live.apply("chinese_input_fix.alpha", 255)
live.apply("chinese_input_fix.red", 18)
live.apply("chinese_input_fix.green", 52)
live.apply("chinese_input_fix.blue", 86)
check("APPLY 自定义色", (t.resolve_style()), "FF123456")
live.apply("chinese_input_fix.size", 24)
local _, applied_size = t.resolve_style()
check("APPLY 字号", applied_size, 24)
check("APPLY 后标记", t.decorate("你好"), "<c=FF123456><s=24>你好")
live.apply("chinese_input_fix.color", 1)          -- 关闭
check("关闭后不再上色", (t.resolve_style()), nil)

-- 5b) 字号开关关掉 → 不加 <s=xx>(即使滑块还有值)
live.apply("chinese_input_fix.size_on", false)
local _, off_size = t.resolve_style()
check("关闭字号后不带字号", off_size, nil)
check("关闭字号后只剩文字", t.decorate("你好"), "你好")
live.apply("chinese_input_fix.size_on", true)
local _, back_size = t.resolve_style()
check("重新打开字号恢复", back_size, 24)

-- 5c) 滑块下限 10: 低于 10 的值会被抬到 10
local _, low_size = t.compute_style(nil, nil, nil, nil, nil, 5, nil)
check("字号 5 抬到 10", low_size, 10)
local _, low2 = t.compute_style(nil, nil, nil, nil, nil, 10, nil)
check("字号 10 原样", low2, 10)
local _, high = t.compute_style(nil, nil, nil, nil, nil, 200, nil)
check("字号 200 压到 99", high, 99)

-- 6) 菜单拒绝 ASCII 分类名 → 自动退回中文名
rawset(_G, "ModOptionsMenu", nil)
t, mod = reload()
local strict_menu, strict_state = make_menu()
strict_state.reject_mod = "CHINESE INPUT FIX"
rawset(_G, "ModOptionsMenu", strict_menu)
t.set_frames(300)
t.poll_menu(300)
check("ASCII 分类名被拒后仍能接入", t.menu.state, "ready")
check("退回中文分类名", t.menu.mod_name, "中文输入框")

group("失焦保留(状态机)")
-- decide(visible, focused, chat_open, suspended, cooled)
check("切走时挂起保留", t.decide(true, false, true, false, true), "suspend")
check("切走且聊天已关也挂起", t.decide(true, false, false, false, true), "suspend")
check("切回且聊天仍开则恢复", t.decide(false, true, true, true, true), "show_restore")
check("切回且没有挂起则空白", t.decide(false, true, true, false, true), "show_fresh")
check("冷却期内不弹", t.decide(false, true, true, true, false), "none")
check("切回但聊天已关则清理", t.decide(false, true, false, true, true), "clear_suspended")
check("聊天开着被关掉则丢弃", t.decide(true, true, false, false, true), "hide_discard")
check("正常输入不动作", t.decide(true, true, true, false, true), "none")
check("空闲不动作", t.decide(false, true, false, false, true), "none")

print(string.format("\n%d/%d 项通过, %d 项失败", total - failures, total, failures))
os.exit(failures == 0 and 0 or 1)
