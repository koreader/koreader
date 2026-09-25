local IReaderPageEffect = require("ui/ireaderpageeffect")
local _ = require("gettext")

local OPTIONS = {
    { id = "none",             text = _("无动效") },
    { id = "ripple_slow",      text = _("水波纹-慢") },
    { id = "ripple_standard",  text = _("水波纹-标准") },
    { id = "ripple_fast",      text = _("水波纹-快") },
}

local function currentUI(menu)
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok and ReaderUI and ReaderUI.instance then
        return ReaderUI.instance
    end
    return menu and menu.ui
end

-- Same idea as the font list: radio choice is per-document.
-- Defaults are updated only via “Save document settings as default”.
return function(menu)
    if not IReaderPageEffect.enabled() then
        return nil
    end

    local sub_item_table = {}
    for _, opt in ipairs(OPTIONS) do
        local id = opt.id
        table.insert(sub_item_table, {
            text = opt.text,
            checked_func = function()
                return IReaderPageEffect.resolve(currentUI(menu)) == id
            end,
            radio = true,
            callback = function()
                IReaderPageEffect.persist(currentUI(menu), id)
            end,
        })
    end

    return {
        text = _("翻页动画"),
        help_text = _("Page-turn animation for this document. Use “Save document settings as default” to apply the current choice to new documents."),
        sub_item_table = sub_item_table,
    }
end
