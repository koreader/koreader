local Device = require("device")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local DEFAULT_EFFECT = "ripple_standard"

local OPTIONS = {
    { id = "none",             text = _("无动效") },
    { id = "ripple_slow",      text = _("水波纹-慢") },
    { id = "ripple_standard",  text = _("水波纹-标准") },
    { id = "ripple_fast",      text = _("水波纹-快") },
}

local function defaultEffect()
    return G_reader_settings:readSetting("ireader_page_effect") or DEFAULT_EFFECT
end

local function documentEffect(ui)
    if ui and ui.doc_settings then
        local value = ui.doc_settings:readSetting("ireader_page_effect")
        if value then
            return value
        end
    end
    return defaultEffect()
end

-- ReaderMenu passes itself so we can read/write the current document settings.
return function(menu)
    if not (Device.isIReaderEink and Device:isIReaderEink()) then
        return nil
    end

    local sub_item_table = {}
    for _, opt in ipairs(OPTIONS) do
        local id = opt.id
        local label = opt.text
        table.insert(sub_item_table, {
            text_func = function()
                local text = label
                if defaultEffect() == id then
                    text = text .. "   ★"
                end
                return text
            end,
            checked_func = function()
                return documentEffect(menu.ui) == id
            end,
            callback = function()
                if menu.ui and menu.ui.doc_settings then
                    menu.ui.doc_settings:saveSetting("ireader_page_effect", id)
                end
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("ireader_page_effect", id)
                UIManager:show(Notification:new{
                    text = _("Default settings updated"),
                })
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return {
        text = _("翻页动画"),
        help_text = _("Official eink page-turn animation. Long-press an item to save it as the default for new documents. “Save document settings as default” also keeps the current choice."),
        sub_item_table = sub_item_table,
    }
end
