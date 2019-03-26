local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Input = Device.input
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderFont = InputContainer:new{
    font_face = nil,
    font_size = nil,
    line_space_percent = nil,
    font_menu_title = _("Font"),
    face_table = nil,
    -- default gamma from crengine's lvfntman.cpp
    gamma_index = nil,
    steps = {0,1,1,1,1,1,2,2,2,3,3,3,4,4,5},
    gestureScale = Screen:getWidth() * FRONTLIGHT_SENSITIVITY_DECREASE,
}

function ReaderFont:init()
    if Device:hasKeyboard() then
        -- add shortcut for keyboard
        self.key_events = {
            ShowFontMenu = { {"F"}, doc = "show font menu" },
            IncreaseSize = {
                { "Shift", Input.group.PgFwd },
                doc = "increase font size",
                event = "ChangeSize", args = "increase" },
            DecreaseSize = {
                { "Shift", Input.group.PgBack },
                doc = "decrease font size",
                event = "ChangeSize", args = "decrease" },
            IncreaseLineSpace = {
                { "Alt", Input.group.PgFwd },
                doc = "increase line space",
                event = "ChangeLineSpace", args = "increase" },
            DecreaseLineSpace = {
                { "Alt", Input.group.PgBack },
                doc = "decrease line space",
                event = "ChangeLineSpace", args = "decrease" },
        }
    end
    -- build face_table for menu
    self.face_table = {}
    local face_list = cre.getFontFaces()
    for k,v in ipairs(face_list) do
        table.insert(self.face_table, {
            text_func = function()
                -- defaults are hardcoded in credocument.lua
                local default_font = G_reader_settings:readSetting("cre_font") or self.ui.document.default_font
                local fallback_font = G_reader_settings:readSetting("fallback_font") or self.ui.document.fallback_font
                local text = v
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   �"
                end
                return text
            end,
            callback = function()
                self:setFont(v)
            end,
            hold_callback = function(touchmenu_instance)
                self:makeDefault(v, touchmenu_instance)
            end,
            checked_func = function()
                return v == self.font_face
            end
        })
        face_list[k] = {text = v}
    end
    if self:hasFontsTestSample() then
        self.face_table[#self.face_table].separator = true
        table.insert(self.face_table, {
            text = _("Generate fonts test HTML document"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Would you like to generate an HTML document showing some sample text rendered with each available font?");
                    ok_callback = function()
                        self:buildFontsTestDocument()
                    end
                })
            end
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReaderFont:onReaderReady()
    self:setupTouchZones()
end

function ReaderFont:setupTouchZones()
    if Device:isTouchDevice() then
        self.ui:registerTouchZones({
            {
                id = "id_spread",
                ges = "spread",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges) return self:onAdjustSpread(ges) end
            },
            {
                id = "id_pinch",
                ges = "pinch",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges) return self:onAdjustPinch(ges) end
            },
        })
    end
end

function ReaderFont:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderFont:onReadSettings(config)
    self.font_face = config:readSetting("font_face")
            or G_reader_settings:readSetting("cre_font")
            or self.ui.document.default_font
    self.ui.document:setFontFace(self.font_face)

    self.header_font_face = config:readSetting("header_font_face")
            or G_reader_settings:readSetting("header_font")
            or self.ui.document.header_font
    self.ui.document:setHeaderFont(self.header_font_face)

    self.font_size = config:readSetting("font_size")
            or G_reader_settings:readSetting("copt_font_size")
            or DCREREADER_CONFIG_DEFAULT_FONT_SIZE or 22
    self.ui.document:setFontSize(Screen:scaleBySize(self.font_size))

    self.font_embolden = config:readSetting("font_embolden")
            or G_reader_settings:readSetting("copt_font_weight") or 0
    self.ui.document:toggleFontBolder(self.font_embolden)

    self.font_hinting = config:readSetting("font_hinting")
            or G_reader_settings:readSetting("copt_font_hinting") or 2 -- auto (default in cre.cpp)
    self.ui.document:setFontHinting(self.font_hinting)

    self.font_kerning = config:readSetting("font_kerning")
            or G_reader_settings:readSetting("copt_font_kerning") or 1 -- freetype (default in cre.cpp)
    self.ui.document:setFontKerning(self.font_kerning)

    self.space_condensing = config:readSetting("space_condensing")
        or G_reader_settings:readSetting("copt_space_condensing") or 75
    self.ui.document:setSpaceCondensing(self.space_condensing)

    self.line_space_percent = config:readSetting("line_space_percent")
            or G_reader_settings:readSetting("copt_line_spacing")
            or DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM
    self.ui.document:setInterlineSpacePercent(self.line_space_percent)

    self.gamma_index = config:readSetting("gamma_index")
            or G_reader_settings:readSetting("copt_font_gamma")
            or DCREREADER_CONFIG_DEFAULT_FONT_GAMMA or 15 -- gamma = 1.0
    self.ui.document:setGammaIndex(self.gamma_index)

    -- Dirty hack: we have to add following call in order to set
    -- m_is_rendered(member of LVDocView) to true. Otherwise position inside
    -- document will be reset to 0 on first view render.
    -- So far, I don't know why this call will alter the value of m_is_rendered.
    table.insert(self.ui.postInitCallback, function()
        self.ui:handleEvent(Event:new("UpdatePos"))
    end)
end

function ReaderFont:onShowFontMenu()
    -- build menu widget
    local main_menu = Menu:new{
        title = self.font_menu_title,
        item_table = self.face_table,
        width = Screen:getWidth() - 100,
        height = Screen:getHeight() / 2,
        single_line = true,
        perpage_custom = 8,
    }
    -- build container
    local menu_container = CenterContainer:new{
        main_menu,
        dimen = Screen:getSize(),
    }
    main_menu.close_callback = function ()
        UIManager:close(menu_container)
    end
    -- show menu

    main_menu.show_parent = menu_container

    UIManager:show(menu_container)

    return true
end

--[[
    UpdatePos event is used to tell ReaderRolling to update pos.
--]]
function ReaderFont:onChangeSize(direction, font_delta)
    local delta = direction == "decrease" and -0.5 or 0.5
    if font_delta then
        self.font_size = self.font_size + font_delta * delta
    else
        self.font_size = self.font_size + delta
    end
    self.ui:handleEvent(Event:new("SetFontSize", self.font_size))
    return true
end

function ReaderFont:onSetFontSize(new_size)
    if new_size > 255 then new_size = 255 end
    if new_size < 12 then new_size = 12 end

    self.font_size = new_size
    self.ui.document:setFontSize(Screen:scaleBySize(new_size))
    self.ui:handleEvent(Event:new("UpdatePos"))
    UIManager:show(Notification:new{
        text = T( _("Font size set to %1."), self.font_size),
        timeout = 2,
    })

    return true
end

function ReaderFont:onSetLineSpace(space)
    self.line_space_percent = math.min(200, math.max(50, space))
    UIManager:show(Notification:new{
        text = T( _("Line spacing set to %1%."), self.line_space_percent),
        timeout = 2,
    })
    self.ui.document:setInterlineSpacePercent(self.line_space_percent)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderFont:onToggleFontBolder(toggle)
    self.font_embolden = toggle
    self.ui.document:toggleFontBolder(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderFont:onSetFontHinting(mode)
    self.font_hinting = mode
    self.ui.document:setFontHinting(mode)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderFont:onSetFontKerning(mode)
    self.font_kerning = mode
    self.ui.document:setFontKerning(mode)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderFont:onSetSpaceCondensing(space)
    self.space_condensing = space
    self.ui.document:setSpaceCondensing(space)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

function ReaderFont:onSetFontGamma(gamma)
    self.gamma_index = gamma
    self.ui.document:setGammaIndex(self.gamma_index)
    local gamma_level = self.ui.document:getGammaLevel()
    UIManager:show(Notification:new{
        text = T( _("Font gamma set to %1."), gamma_level),
        timeout = 2,
    })
    self.ui:handleEvent(Event:new("RedrawCurrentView"))
    return true
end

function ReaderFont:onSaveSettings()
    self.ui.doc_settings:saveSetting("font_face", self.font_face)
    self.ui.doc_settings:saveSetting("header_font_face", self.header_font_face)
    self.ui.doc_settings:saveSetting("font_size", self.font_size)
    self.ui.doc_settings:saveSetting("font_embolden", self.font_embolden)
    self.ui.doc_settings:saveSetting("font_hinting", self.font_hinting)
    self.ui.doc_settings:saveSetting("font_kerning", self.font_kerning)
    self.ui.doc_settings:saveSetting("space_condensing", self.space_condensing)
    self.ui.doc_settings:saveSetting("line_space_percent", self.line_space_percent)
    self.ui.doc_settings:saveSetting("gamma_index", self.gamma_index)
end

function ReaderFont:setFont(face)
    if face and self.font_face ~= face then
        self.font_face = face
        UIManager:show(Notification:new{
            text = T( _("Redrawing with font %1."), face),
            timeout = 2,
        })

        self.ui.document:setFontFace(face)
        -- signal readerrolling to update pos in new height
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderFont:makeDefault(face, touchmenu_instance)
    if face then
        UIManager:show(MultiConfirmBox:new{
            text = T( _("Would you like %1 to be used as the default font (★), or the fallback font (�)?\n\nCharacters not found in the active font are shown in the fallback font instead."), face),
            choice1_text = _("Default"),
            choice1_callback = function()
                G_reader_settings:saveSetting("cre_font", face)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            choice2_text = _("Fallback"),
            choice2_callback = function()
                if self.ui.document:setFallbackFontFace(face) then
                    G_reader_settings:saveSetting("fallback_font", face)
                    self.ui:handleEvent(Event:new("UpdatePos"))
                end
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
end

function ReaderFont:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.change_font = {
        text = self.font_menu_title,
        sub_item_table = self.face_table,
    }
end

function ReaderFont:onAdjustSpread(ges)
    local step = math.ceil(2 * #self.steps * ges.distance / self.gestureScale)
    local delta_int = self.steps[step] or self.steps[#self.steps]
    local info = Notification:new{text = _("Increasing font size…")}
    UIManager:show(info)
    UIManager:forceRePaint()
    self:onChangeSize("increase", delta_int)
    UIManager:close(info)
    return true
end

function ReaderFont:onAdjustPinch(ges)
    local step = math.ceil(2 * #self.steps * ges.distance / self.gestureScale)
    local delta_int = self.steps[step] or self.steps[#self.steps]
    local info = Notification:new{text = _("Decreasing font size…")}
    UIManager:show(info)
    UIManager:forceRePaint()
    self:onChangeSize("decrease", delta_int)
    UIManager:close(info)
    return true
end

function ReaderFont:hasFontsTestSample()
    local font_test_sample = require("datastorage"):getSettingsDir() .. "/fonts-test-sample.html"
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(font_test_sample, "mode") == "file"
end

function ReaderFont:buildFontsTestDocument()
    local font_test_sample = require("datastorage"):getSettingsDir() .. "/fonts-test-sample.html"
    local f = io.open(font_test_sample, "r")
    if not f then return nil end
    local html_sample = f:read("*all")
    f:close()
    local dir = G_reader_settings:readSetting("home_dir")
    if not dir then dir = require("apps/filemanager/filemanagerutil").getDefaultDir() end
    if not dir then dir = "." end
    local fonts_test_path = dir .. "/fonts-test-all.html"
    f = io.open(fonts_test_path, "w")
    -- Using <section><title>...</title></section> allows for a TOC to be built
    f:write(string.format([[
<?xml version="1.0" encoding="UTF-8"?>
<html>
<head>
<title>%s</title>
<style>
section > title {
  font-size: large;
  font-weight: bold;
  text-align: center;
  page-break-before: always;
  margin-bottom: 0.5em;
}
a { color: black; }
</style>
</head>
<body>
<section id="list"><title>%s</title></section>
]], _("Available fonts test document"), _("AVAILABLE FONTS")))
    local face_list = cre.getFontFaces()
    f:write("<div style='margin: 2em'>\n")
    for _, font_name in ipairs(face_list) do
        local font_id = font_name:gsub(" ", "_"):gsub("'", "_")
        f:write(string.format("  <div><a href='#%s'>%s</a></div>\n", font_id, font_name))
    end
    f:write("</div>\n\n")
    for _, font_name in ipairs(face_list) do
        local font_id = font_name:gsub(" ", "_"):gsub("'", "_")
        f:write(string.format("<section id='%s'><title>%s</title></section>\n", font_id, font_name))
        f:write(string.format("<div style='font-family: %s'>\n", font_name))
        f:write(html_sample)
        f:write("\n</div>\n\n")
    end
    f:write("</body></html>\n")
    f:close()
    UIManager:show(ConfirmBox:new{
        text = T(_("Document created as:\n%1\n\nWould you like to read it now?"), fonts_test_path),
        ok_callback = function()
            UIManager:scheduleIn(1.0, function()
                self.ui:switchDocument(fonts_test_path)
            end)
        end,
    })
end

return ReaderFont
