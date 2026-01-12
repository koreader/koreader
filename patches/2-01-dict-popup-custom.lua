local logger = require("logger")
logger.info("Applying custom dictionary popup patch")

local ReaderUI = require("apps/reader/readerui")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Translator = require("ui/translator")
local BD = require("ui/bidi")
local _ = require("gettext")

local DictPopupCustomizer = WidgetContainer:extend{
    name = "dictpopupcustomizer",
}

function DictPopupCustomizer:onDictButtonsReady(dict_popup, buttons)
    if dict_popup.is_wiki_fullpage then
        return
    end

    local prev_dict_text = "◁◁"
    local next_dict_text = "▷▷"
    if BD.mirroredUILayout() then
        prev_dict_text, next_dict_text = next_dict_text, prev_dict_text
    end

    buttons[1] = {
        {
            id = "prev_dict",
            text = prev_dict_text,
            vsync = true,
            enabled = dict_popup:isPrevDictAvaiable(),
            callback = function()
                dict_popup:onChangeToPrevDict()
            end,
            hold_callback = function()
                dict_popup:changeToFirstDict()
            end,
        },
        {
            id = "dict_counter",
            text_func = function()
                return dict_popup.displaynb or ""
            end,
            enabled = false,
        },
        {
            id = "next_dict",
            text = next_dict_text,
            vsync = true,
            enabled = dict_popup:isNextDictAvaiable(),
            callback = function()
                dict_popup:onChangeToNextDict()
            end,
            hold_callback = function()
                dict_popup:changeToLastDict()
            end,
        },
    }

    buttons[2] = {
        {
            id = "highlight",
            text = _("Highlight"),
            enabled = not dict_popup:isDocless() and dict_popup.highlight ~= nil,
            callback = function()
                dict_popup.save_highlight = not dict_popup.save_highlight
                local this = dict_popup.button_table:getButtonById("highlight")
                this:setText(dict_popup.save_highlight and _("Unhighlight") or _("Highlight"), this.width)
                this:refresh()
            end,
        },
        {
            id = "translate",
            text = _("Translate"),
            callback = function()
                Translator:showTranslation(dict_popup.lookupword, true)
            end,
        },
    }
end

local orig_ReaderUI_registerModule = ReaderUI.registerModule
function ReaderUI:registerModule(name, ui_module, always_active)
    orig_ReaderUI_registerModule(self, name, ui_module, always_active)

    if name == "highlight" then
        local customizer = DictPopupCustomizer:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
        }
        self:registerModule("dictpopupcustomizer", customizer)
        logger.info("DictPopupCustomizer module registered")
    end
end

local DictQuickLookup = require("ui/widget/dictquicklookup")

local orig_DictQuickLookup_init = DictQuickLookup.init
function DictQuickLookup:init()
    local orig_displaynb = self.displaynb
    self.displaynb = nil

    orig_DictQuickLookup_init(self)

    self.displaynb = orig_displaynb
end

local orig_DictQuickLookup_update = DictQuickLookup.update
function DictQuickLookup:update()
    local orig_displaynb = self.displaynb
    self.displaynb = nil

    orig_DictQuickLookup_update(self)

    self.displaynb = orig_displaynb

    if not self.is_wiki_fullpage then
        local dict_counter_btn = self.button_table:getButtonById("dict_counter")
        if dict_counter_btn then
            dict_counter_btn:setText(self.displaynb or "", dict_counter_btn.width)
            dict_counter_btn:refresh()
        end
    end
end

function DictQuickLookup:addQueryWordToResult()
end

logger.info("Custom dictionary popup patch applied successfully")
