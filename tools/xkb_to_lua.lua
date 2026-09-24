#!/usr/bin/env luajit

--[[
Export an XKB layout as a KOReader Lua layout table.

Compiles the selected XKB rules, model, layout, and variant with
libxkbcommon, then exports text available with no modifier, Shift, AltGr, or
Shift+AltGr. It does not export layout groups or XKB actions. Dead keys are
preserved for runtime composition.

Examples:
    tools/xkb_to_lua.lua us
    tools/xkb_to_lua.lua de > /tmp/de.lua
    tools/xkb_to_lua.lua --common
    tools/xkb_to_lua.lua --all
    tools/xkb_to_lua.lua --all-variants
]]--

local DEFAULT_SYMBOLS_DIR = "/usr/share/X11/xkb/symbols"
local DEFAULT_OUTPUT_DIR = "plugins/externalkeyboard.koplugin/keyboard_layouts"
local SHIFT = 1
local ALTGR = 2
local LEVEL_MASKS = { 0, SHIFT, ALTGR, SHIFT + ALTGR }
local ffi = require("ffi")

ffi.cdef[[
int isatty(int fd);
typedef uint32_t xkb_keysym_t;
typedef uint32_t xkb_keycode_t;
typedef uint32_t xkb_level_index_t;
typedef uint32_t xkb_layout_index_t;
typedef uint32_t xkb_mod_index_t;
typedef uint32_t xkb_mod_mask_t;
struct xkb_context;
struct xkb_keymap;
struct xkb_rule_names {
    const char *rules;
    const char *model;
    const char *layout;
    const char *variant;
    const char *options;
};
struct xkb_context *xkb_context_new(int flags);
void xkb_context_unref(struct xkb_context *context);
int xkb_context_include_path_append(struct xkb_context *context, const char *path);
struct xkb_keymap *xkb_keymap_new_from_names(struct xkb_context *context, const struct xkb_rule_names *names, int flags);
void xkb_keymap_unref(struct xkb_keymap *keymap);
xkb_keycode_t xkb_keymap_key_by_name(struct xkb_keymap *keymap, const char *name);
const char *xkb_keymap_layout_get_name(struct xkb_keymap *keymap, xkb_layout_index_t idx);
xkb_level_index_t xkb_keymap_num_levels_for_key(struct xkb_keymap *keymap, xkb_keycode_t key, uint32_t layout);
size_t xkb_keymap_key_get_mods_for_level(struct xkb_keymap *keymap, xkb_keycode_t key, uint32_t layout, xkb_level_index_t level, xkb_mod_mask_t *masks_out, size_t masks_size);
int xkb_keymap_key_get_syms_by_level(struct xkb_keymap *keymap, xkb_keycode_t key, uint32_t layout, xkb_level_index_t level, const xkb_keysym_t **syms_out);
xkb_mod_index_t xkb_keymap_mod_get_index(struct xkb_keymap *keymap, const char *name);
int xkb_keysym_get_name(xkb_keysym_t keysym, char *buffer, size_t size);
xkb_keysym_t xkb_keysym_from_name(const char *name, int flags);
int xkb_keysym_to_utf8(xkb_keysym_t keysym, char *buffer, size_t size);
]]

local xkbcommon = ffi.load("xkbcommon")

-- XKB physical names used by a standard evdev full-size keyboard, mapped to
-- the names produced by externalkeyboard.koplugin/event_map_keyboard.lua.
local KEY_NAMES = {
    TLDE = "`",
    AE11 = "-", AE12 = "=",
    AD11 = "[", AD12 = "]",
    AC10 = ";", AC11 = "'", BKSL = "\\",
    AB08 = ",", AB09 = ".", AB10 = "/", LSGT = "<", SPCE = " ",
}

local LEGACY_KEYSYM_CHARACTERS = {
    Hebrew_nun = "\215\160",
    hebrew_nun = "\215\160",
}

for number, key in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }) do
    KEY_NAMES[("AE%02d"):format(number)] = key
end
for number, key in ipairs({ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }) do
    KEY_NAMES[("AD%02d"):format(number)] = key
end
for number, key in ipairs({ "A", "S", "D", "F", "G", "H", "J", "K", "L" }) do
    KEY_NAMES[("AC%02d"):format(number)] = key
end
for number, key in ipairs({ "Z", "X", "C", "V", "B", "N", "M" }) do
    KEY_NAMES[("AB%02d"):format(number)] = key
end

local function lua_string(value)
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function read_file(path)
    local file, error_message = io.open(path, "r")
    assert(file, error_message)
    local content = file:read("*a")
    file:close()
    return content:gsub("//[^\n]*", "")
end

local function parse_keysym(name)
    if #name == 1 then return name end
    if name:match("^dead_[%w_]+$") then return { dead = name } end
    if LEGACY_KEYSYM_CHARACTERS[name] then return LEGACY_KEYSYM_CHARACTERS[name] end
    local keysym = xkbcommon.xkb_keysym_from_name(name, 0)
    if keysym == 0 then return nil end
    local buffer = ffi.new("char[7]")
    local length = xkbcommon.xkb_keysym_to_utf8(keysym, buffer, 7)
    return length > 0 and ffi.string(buffer, length - 1) or nil
end

local function parse_keysym_value(keysym)
    if keysym == 0 then return false end
    local name = ffi.new("char[128]")
    if xkbcommon.xkb_keysym_get_name(keysym, name, 128) <= 0 then return nil end
    local keysym_name = ffi.string(name)
    if keysym_name == "VoidSymbol" then return false end
    return parse_keysym(keysym_name)
end

local function modifier_mask(keymap, name)
    local index = xkbcommon.xkb_keymap_mod_get_index(keymap, name)
    return index < 32 and 2 ^ tonumber(index) or 0
end

local function load_layout(symbols_dir, layout, variant)
    local context = xkbcommon.xkb_context_new(0)
    assert(context ~= nil, "could not create XKB context")
    local xkb_root = symbols_dir:gsub("/symbols/?$", "")
    assert(xkbcommon.xkb_context_include_path_append(context, xkb_root) ~= 0, "could not add XKB include path " .. xkb_root)
    local names = ffi.new("struct xkb_rule_names")
    names.rules = "evdev"
    names.model = "pc105"
    names.layout = layout
    names.variant = variant
    local keymap = xkbcommon.xkb_keymap_new_from_names(context, names, 0)
    xkbcommon.xkb_context_unref(context)
    assert(keymap ~= nil, ("could not compile %s(%s)"):format(layout, variant))

    local shift = modifier_mask(keymap, "Shift")
    local altgr = modifier_mask(keymap, "Mod5")
    local level_masks = {
        [0] = 0,
        [shift] = SHIFT,
        [altgr] = ALTGR,
        [shift + altgr] = SHIFT + ALTGR,
    }
    local entries = {}
    for xkb_key, key in pairs(KEY_NAMES) do
        local keycode = xkbcommon.xkb_keymap_key_by_name(keymap, xkb_key)
        if keycode ~= 0 then
            local levels = {}
            for level = 0, tonumber(xkbcommon.xkb_keymap_num_levels_for_key(keymap, keycode, 0)) - 1 do
                local masks = ffi.new("xkb_mod_mask_t[16]")
                local count = tonumber(xkbcommon.xkb_keymap_key_get_mods_for_level(keymap, keycode, 0, level, masks, 16))
                for index = 0, count - 1 do
                    local output_level = level_masks[tonumber(masks[index])]
                    if output_level then
                        local syms = ffi.new("const xkb_keysym_t *[1]")
                        if xkbcommon.xkb_keymap_key_get_syms_by_level(keymap, keycode, 0, level, syms) == 1 then
                            local value = parse_keysym_value(syms[0][0])
                            if value then
                                levels[output_level] = value
                            elseif value ~= false then
                                io.stderr:write(("warning: %s(%s) <%s>: unsupported keysym\n"):format(layout, variant, xkb_key))
                            end
                        end
                    end
                end
            end
            if next(levels) then entries[key] = levels end
        end
    end
    local name = ffi.string(xkbcommon.xkb_keymap_layout_get_name(keymap, 0))
    xkbcommon.xkb_keymap_unref(keymap)
    return entries, name
end

-- XKB layouts shipped with KOReader by default
local COMMON_XKB_LAYOUTS = {
    -- Western European
    { "us", "us", "basic" },
    { "us-intl", "us", "intl" },
    { "us-altgr-intl", "us", "altgr-intl" },
    { "gb", "gb", "basic" },
    { "be", "be", "basic" },
    { "br", "br", "abnt2" },
    { "de", "de", "basic" },
    { "es", "es", "basic" },
    { "fr", "fr", "basic" },
    { "it", "it", "basic" },
    { "nl", "nl", "basic" },
    -- Central / Eastern European
    { "pl", "pl", "basic" },
    { "cz", "cz", "basic" },
    { "hu", "hu", "basic" },
    { "ro", "ro", "basic" },
    -- Other scripts
    { "kz", "kz", "basic" },
    { "ru", "ru", "winkeys" },
    { "uk", "ua", "unicode" },
    { "ar", "ara", "basic" },
    { "el", "gr", "basic" },
    { "he", "il", "basic" },
}

-- Language conversion
local KOREADER_XKB_LAYOUTS = {
    ar = { "ara", "basic" },
    bg_BG = { "bg", "bds" },
    bn = { "bd", "basic" },
    cs = { "cz", "basic" },
    da = { "dk", "basic" },
    el = { "gr", "basic" },
    en = { "us", "basic" },
    fa = { "ir", "pes" },
    he = { "il", "basic" },
    ja = { "jp", "106" },
    ka = { "ge", "basic" },
    ko_KR = { "kr", "kr106" },
    ml = { "in", "mal" },
    nb_NO = { "no", "basic" },
    pt_BR = { "br", "abnt2" },
    ru = { "ru", "winkeys" },
    sr = { "rs", "basic" },
    sv = { "se", "basic" },
    uk = { "ua", "unicode" },
    vi = { "vn", "basic" },
    zh = { "cn", "basic" },
    zh_CN = { "cn", "basic" },
}

-- KOReader interface languages that have no virtual keyboard layout, plus
-- commonly used national layouts for the same language.
local KOREADER_EXTRA_XKB_LAYOUTS = {
    { "ca", "es", "cat" },
    { "en_GB", "gb", "basic" },
    { "eo", "epo", "basic" },
    { "eu", "es", "basic" },
    { "fi", "fi", "kotoistus" },
    { "ga", "ie", "basic" },
    { "gl", "es", "basic" },
    { "hr", "hr", "basic" },
    { "id", "id", "basic" },
    { "it_IT", "it", "basic" },
    { "lt_LT", "lt", "basic" },
    { "lv", "lv", "basic" },
    { "nl_NL", "nl", "basic" },
    { "nl_NL-be", "be", "basic" },
    { "pt_PT", "pt", "basic" },
    { "ro_MD", "md", "basic" },
    { "sl", "si", "basic" },
    { "zh_TW", "tw", "tw" },
}

local function available_koreader_layouts()
    local virtual_keyboard = read_file("frontend/ui/widget/virtualkeyboard.lua")
    local map = virtual_keyboard:match("lang_to_keyboard_layout%s*=%s*{(.-)\n    },")
    assert(map, "VirtualKeyboard.lang_to_keyboard_layout not found")
    local layouts = {}
    for language in map:gmatch("\n%s*([%w_]+)%s*=") do
        local xkb_layout = KOREADER_XKB_LAYOUTS[language]
        table.insert(layouts, {
            language = language,
            layout = xkb_layout and xkb_layout[1] or language:match("^[^_]+"),
            variant = xkb_layout and xkb_layout[2] or "basic",
        })
    end
    for _, layout_info in ipairs(KOREADER_EXTRA_XKB_LAYOUTS) do
        table.insert(layouts, {
            language = layout_info[1],
            layout = layout_info[2],
            variant = layout_info[3],
        })
    end
    table.sort(layouts, function(left, right) return left.language < right.language end)
    return layouts
end

local function available_common_layouts()
    local layouts = {}
    for _, layout_info in ipairs(COMMON_XKB_LAYOUTS) do
        table.insert(layouts, {
            language = layout_info[1],
            layout = layout_info[2],
            variant = layout_info[3],
        })
    end
    return layouts
end

local function available_koreader_layout_variants(symbols_dir)
    local layouts = available_koreader_layouts()
    local variants = {}
    local rules = read_file(symbols_dir .. "/../rules/evdev.lst")
    local in_variant_section = false
    for line in rules:gmatch("[^\n]+") do
        if line == "! variant" then
            in_variant_section = true
        elseif line:match("^!") then
            if in_variant_section then break end
        elseif in_variant_section then
            local variant, xkb_layout = line:match("^%s*([%w_-]+)%s+([%w_-]+):")
            if variant and xkb_layout then
                for _, layout_info in ipairs(layouts) do
                    if layout_info.layout == xkb_layout and layout_info.variant ~= variant then
                        table.insert(variants, {
                            language = layout_info.language .. "-" .. variant,
                            layout = xkb_layout,
                            variant = variant,
                        })
                    end
                end
            end
        end
    end
    for _, layout_info in ipairs(layouts) do table.insert(variants, layout_info) end
    table.sort(variants, function(left, right) return left.language < right.language end)
    return variants
end

local function available_xkb_layouts(symbols_dir, include_variants)
    local layouts = {}
    local rules = read_file(symbols_dir .. "/../rules/evdev.lst")
    local section
    for line in rules:gmatch("[^\n]+") do
        if line == "! layout" then
            section = "layout"
        elseif line == "! variant" then
            section = include_variants and "variant" or nil
        elseif line:match("^!") then
            section = nil
        elseif section == "layout" then
            local layout = line:match("^%s*([%w_-]+)%s+")
            if layout then
                table.insert(layouts, {
                    language = layout,
                    layout = layout,
                    variant = "basic",
                })
            end
        elseif section == "variant" then
            local variant, layout = line:match("^%s*([%w_-]+)%s+([%w_-]+):")
            if variant and layout then
                table.insert(layouts, {
                    language = layout .. "-" .. variant,
                    layout = layout,
                    variant = variant,
                })
            end
        end
    end
    return layouts
end

local function usage()
    io.stderr:write("Usage: tools/xkb_to_lua.lua <layout> [--variant NAME] [--layout-name NAME] [--symbols-dir PATH] [--output PATH]\n")
    io.stderr:write("       tools/xkb_to_lua.lua --common [--symbols-dir PATH] [--output-dir PATH]  # curated common layouts\n")
    io.stderr:write("       tools/xkb_to_lua.lua --all [--xkb] [--symbols-dir PATH] [--output-dir PATH]  # KOReader or all XKB layouts\n")
    io.stderr:write("       tools/xkb_to_lua.lua --all-variants [--xkb] [--symbols-dir PATH] [--output-dir PATH]  # KOReader or all XKB layouts and variants\n")
end

local function parse_arguments()
    local arguments = { variant = "basic", symbols_dir = DEFAULT_SYMBOLS_DIR }
    local index = 1
    while index <= #arg do
        local value = arg[index]
        if value == "--help" then
            usage()
            os.exit(0)
        elseif value == "--all" then
            arguments.all = true
        elseif value == "--common" then
            arguments.common = true
        elseif value == "--all-variants" then
            arguments.all_variants = true
        elseif value == "--xkb" then
            arguments.xkb = true
        elseif value == "--variant" or value == "--layout-name" or value == "--symbols-dir" or value == "--output" or value == "--output-dir" then
            index = index + 1
            assert(arg[index], value .. " requires a value")
            arguments[value:sub(3):gsub("%-", "_")] = arg[index]
        elseif not arguments.layout then
            arguments.layout = value
        else
            error("unexpected argument " .. value)
        end
        index = index + 1
    end
    assert(not (arguments.xkb and not (arguments.all or arguments.all_variants)), "--xkb requires --all or --all-variants")
    assert(arguments.layout or arguments.common or arguments.all or arguments.all_variants, "layout, --common, --all, or --all-variants is required")
    assert(not (arguments.layout and (arguments.common or arguments.all or arguments.all_variants)), "batch export cannot be combined with a layout")
    assert(not ((arguments.common and arguments.all) or (arguments.common and arguments.all_variants) or (arguments.all and arguments.all_variants)), "only one batch export option may be used")
    assert(not ((arguments.common or arguments.all or arguments.all_variants) and (arguments.variant ~= "basic" or arguments.layout_name or arguments.output)), "batch export only supports --symbols-dir and --output-dir")
    return arguments
end

local function render_layout(entries, layout, variant, name)
    local lines = {
        ("-- Generated by tools/xkb_to_lua.lua from %s(%s).\n"):format(layout, variant),
        "-- Derived from xkeyboard-config symbols data.\n",
        "-- SPDX-License-Identifier: MIT\n",
        "local _ = require(\"gettext\")\n",
        "local C_ = _.pgettext\n",
        "return {\n",
        ("    name = C_(\"Keyboard layout\", %s),\n"):format(lua_string(name)),
    }
    local keys = {}
    for key in pairs(entries) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local levels = entries[key]
        local rendered_levels = {}
        local last_level = 0
        for index, level in ipairs(LEVEL_MASKS) do
            if levels[level] then last_level = index end
        end
        for index = 1, last_level do
            local value = levels[LEVEL_MASKS[index]]
            local rendered_value = type(value) == "table" and ("{ dead = %s }"):format(lua_string(value.dead)) or value and lua_string(value)
            table.insert(rendered_levels, rendered_value or "nil")
        end
        table.insert(lines, ("    [%s] = { %s },\n"):format(lua_string(key), table.concat(rendered_levels, ", ")))
    end
    table.insert(lines, "}\n")
    return table.concat(lines)
end

local function write_layout(path, output)
    local file, error_message = io.open(path, "w")
    assert(file, error_message)
    file:write(output)
    file:close()
end

local function add_space_entry(entries)
    entries[" "] = entries[" "] or {}
    entries[" "][0] = entries[" "][0] or " "
    entries[" "][SHIFT] = entries[" "][SHIFT] or " "
end

local arguments = parse_arguments()
if arguments.common or arguments.all or arguments.all_variants then
    local output_dir = arguments.output_dir or DEFAULT_OUTPUT_DIR
    local written = 0
    local skipped = 0
    local layouts = arguments.xkb and available_xkb_layouts(arguments.symbols_dir, arguments.all_variants)
        or arguments.all_variants and available_koreader_layout_variants(arguments.symbols_dir)
        or arguments.all and available_koreader_layouts()
        or available_common_layouts()
    for _, layout_info in ipairs(layouts) do
        local success, entries, name = pcall(load_layout, arguments.symbols_dir, layout_info.layout, layout_info.variant)
        if success and next(entries) then
            add_space_entry(entries)
            write_layout(output_dir .. "/" .. layout_info.language .. ".lua", render_layout(entries, layout_info.layout, layout_info.variant, name))
            written = written + 1
        else
            io.stderr:write(("warning: skipped %s (%s/%s): %s\n"):format(layout_info.language, layout_info.layout, layout_info.variant, success and "no supported keys" or entries))
            skipped = skipped + 1
        end
    end
    io.write(("Wrote %d layouts to %s (%d skipped)\n"):format(written, output_dir, skipped))
else
    local entries, name = load_layout(arguments.symbols_dir, arguments.layout, arguments.variant)
    add_space_entry(entries)
    local output = render_layout(entries, arguments.layout, arguments.variant, name)
    local is_terminal = ffi.C.isatty(1) ~= 0
    local output_path = arguments.output
    if not output_path and is_terminal then
        output_path = DEFAULT_OUTPUT_DIR .. "/" .. (arguments.layout_name or arguments.layout) .. ".lua"
    end
    if output_path then
        write_layout(output_path, output)
        io.write("Wrote " .. output_path .. "\n")
    else
        io.write(output)
    end
end
