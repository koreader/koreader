local CenterContainer = require("ui/widget/container/centercontainer")
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
            text = v,
            callback = function()
                self:setFont(v)
            end,
            hold_callback = function()
                self:makeDefault(v)
            end,
            checked_func = function()
                return v == self.font_face
            end
        })
        face_list[k] = {text = v}
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
            or self.ui.document.default_font
    self.ui.document:setFontFace(self.font_face)

    self.header_font_face = config:readSetting("header_font_face")
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
            or G_reader_settings:readSetting("copt_font_hinting") or 2 -- default in cre.cpp
    self.ui.document:setFontHinting(self.font_hinting)

    self.line_space_percent = config:readSetting("line_space_percent")
            or G_reader_settings:readSetting("copt_line_spacing")
            or DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM
    self.ui.document:setInterlineSpacePercent(self.line_space_percent)

    self.gamma_index = config:readSetting("gamma_index")
            or G_reader_settings:readSetting("copt_font_gamma")
            or DCREREADER_CONFIG_DEFAULT_FONT_GAMMA
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
    local delta = direction == "decrease" and -1 or 1
    if font_delta then
        self.font_size = self.font_size + font_delta * delta
    else
        self.font_size = self.font_size + delta
    end
    self.ui:handleEvent(Event:new("SetFontSize", self.font_size))
    return true
end

function ReaderFont:onSetFontSize(new_size)
    if new_size > 72 then new_size = 72 end
    if new_size < 12 then new_size = 12 end

    self.font_size = new_size
    self.ui.document:setFontSize(Screen:scaleBySize(new_size))
    self.ui:handleEvent(Event:new("UpdatePos"))
    UIManager:show(Notification:new{
        text = T( _("Font size set to %1."), self.font_size),
        timeout = 1,
    })

    return true
end

function ReaderFont:onSetLineSpace(space)
    self.line_space_percent = math.min(200, math.max(80, space))
    UIManager:show(Notification:new{
        text = T( _("Line spacing set to %1%."), self.line_space_percent),
        timeout = 1,
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

function ReaderFont:onSetFontGamma(gamma)
    self.gamma_index = gamma
    UIManager:show(Notification:new{
        text = T( _("Font gamma set to %1."), self.gamma_index),
        timeout = 1
    })
    self.ui.document:setGammaIndex(self.gamma_index)
    self.ui:handleEvent(Event:new("RedrawCurrentView"))
    return true
end

function ReaderFont:onSaveSettings()
    self.ui.doc_settings:saveSetting("font_face", self.font_face)
    self.ui.doc_settings:saveSetting("header_font_face", self.header_font_face)
    self.ui.doc_settings:saveSetting("font_size", self.font_size)
    self.ui.doc_settings:saveSetting("font_embolden", self.font_embolden)
    self.ui.doc_settings:saveSetting("font_hinting", self.font_hinting)
    self.ui.doc_settings:saveSetting("line_space_percent", self.line_space_percent)
    self.ui.doc_settings:saveSetting("gamma_index", self.gamma_index)
end

function ReaderFont:setFont(face)
    if face and self.font_face ~= face then
        self.font_face = face
        UIManager:show(Notification:new{
            text = T( _("Redrawing with font %1."), face),
            timeout = 1,
        })

        self.ui.document:setFontFace(face)
        -- signal readerrolling to update pos in new height
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderFont:makeDefault(face)
    if face then
        UIManager:show(MultiConfirmBox:new{
            text = T( _("Set %1 as fallback font? Characters not found in the active font are shown in the fallback font instead."), face),
            choice1_text = _("Default"),
            choice1_callback = function()
                G_reader_settings:saveSetting("cre_font", face)
            end,
            choice2_text = _("Fallback"),
            choice2_callback = function()
                G_reader_settings:saveSetting("fallback_font", face)
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

return ReaderFont
