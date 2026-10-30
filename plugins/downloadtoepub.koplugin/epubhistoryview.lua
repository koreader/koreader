local _ = require("gettext")
local History = require("epubhistory")

local HistoryView = {}

function HistoryView:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function HistoryView:getLastDownloadButton(load_puzzle_cb)
    local history = History:new{}
    if #history:get() > 0 then
        local history_item = history:get()[1]
        return {
            text = _(("Last download: \"%s\""):format(history_item['url'])),
            callback = function()
                load_puzzle_cb(history_item)
            end
        }
    else
        return nil
    end
end

--[[--
    Return a list that can be used to populate a plugin menu.
]]
function HistoryView:getMenuItems(open_epub_cb, clear_history_cb)
    local menu_items = {}
    local sub_menu_items = {}
    -- If the user has started a puzzle, we'll add a new option to the menu.
    local history = History:new{}

    if #history:get() > 0 then
        local history_list = {}
        for i, item in ipairs(history:get()) do
            table.insert(sub_menu_items, {
                    text = item['url'],
                    callback = function()
                        open_epub_cb(item)
                    end
            })
        end
        -- Add a clear history button
        table.insert(sub_menu_items,
            {
                text = _("Clear history"),
                keep_menu_open = false,
                callback = function()
                    history:clear()
                end
            }
        )
        table.insert(menu_items, {
                text = _("History"),
                sub_item_table = sub_menu_items
        })
        return menu_items
    else
        return nil
    end
end

return HistoryView
