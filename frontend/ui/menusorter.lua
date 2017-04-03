--[[--
This module is responsible for constructing the KOReader menu based on a list of
menu_items and a separate menu order.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local separator_id = "----------------------------"

local MenuSorter = {
    orphaned_prefix = _("NEW: "),
    separator = {
        id = separator_id,
        text = "KOMenu:separator",
    },
}

function MenuSorter:readMSSettings(config_prefix)
    if config_prefix then
        local menu_order = string.format(
            "%s/%s_menu_order", DataStorage:getSettingsDir(), config_prefix)

        if lfs.attributes(menu_order..".lua") then
            return require(menu_order) or {}
        end
    end
    return {}
end

function MenuSorter:mergeAndSort(config_prefix, item_table, order)
    local user_order = self:readMSSettings(config_prefix)
    if user_order then
        for user_order_id,user_order_item in pairs(user_order) do
            if order[user_order_id] then
                order[user_order_id] = user_order_item
            end
        end
    end
    return self:sort(item_table, order)
end

function MenuSorter:sort(item_table, order)
    local menu_table = {}
    local sub_menus = {}
    -- the actual sorting of menu items
    for order_id, order_item in pairs (order) do
        -- user might define non-existing menu item
        if item_table[order_id] ~= nil then
            local tmp_menu_table = {}
            menu_table[order_id] = item_table[order_id]
            menu_table[order_id].id = order_id
            for order_number,order_number_id in ipairs(order_item) do
                -- this is a submenu, mark it for later
                if order[order_number_id] then
                    table.insert(sub_menus, order_number_id)
                    tmp_menu_table[order_number] = {
                        id = order_number_id,
                    }
                -- regular, just insert a menu action
                else
                    if order_number_id == separator_id then
                        -- it's a separator
                        tmp_menu_table[order_number] = self.separator
                    elseif item_table[order_number_id] ~= nil then
                        item_table[order_number_id].id = order_number_id
                        tmp_menu_table[order_number] = item_table[order_number_id]
                        -- remove reference from item_table so it won't show up as orphaned
                        item_table[order_number_id] = nil
                    end
                end
            end
            -- compress menus
            -- if menu_items were missing we might have a table with gaps
            -- but ipairs doesn't like that and quits when it hits nil
            local i = 1
            local new_index = 1
            while i <= table.maxn(tmp_menu_table) do
                local v = tmp_menu_table[i]
                if v then
                    if v.id == separator_id then
                        new_index = new_index - 1
                        menu_table[order_id][new_index].separator = true
                    else
                        -- fix the index
                        menu_table[order_id][new_index] = tmp_menu_table[i]
                    end

                    new_index = new_index + 1
                end
                i = i + 1
            end
        else
            if order_id ~= "KOMenu:disabled" then
                logger.warn("menu id not found:", order_id)
            end
        end
    end

    -- now do the submenus
    for i,sub_menu in ipairs(sub_menus) do
        local sub_menu_position = self:findById(menu_table["KOMenu:menu_buttons"], sub_menu)
        if sub_menu_position then
            local sub_menu_content = menu_table[sub_menu]
            sub_menu_position.text = sub_menu_content.text
            sub_menu_position.sub_item_table = sub_menu_content
            -- remove reference from top level output
            sub_menu_content = nil
            -- remove reference from input so it won't show up as orphaned
            item_table[sub_menu] = nil
        end
    end
    -- @TODO avoid this extra mini-loop
    -- cleanup, top-level items shouldn't have sub_item_table
    for i,top_menu in ipairs(menu_table["KOMenu:menu_buttons"]) do
        menu_table["KOMenu:menu_buttons"][i] = menu_table["KOMenu:menu_buttons"][i].sub_item_table
    end

    -- handle disabled
    if order["KOMenu:disabled"] then
        for _,item in ipairs(order["KOMenu:disabled"]) do
            if item_table[item] then
                -- remove reference from input so it won't show up as orphaned
                item_table[item] = nil
            end
        end
    end

    -- remove top level reference before orphan handling
    item_table["KOMenu:menu_buttons"] = nil
        --attach orphans based on menu_hint
    for k,v in pairs(item_table) do
        -- normally there should be menu text but check to be sure
        if v.text and v.new ~= true then
            v.id = k
            v.text = self.orphaned_prefix .. v.text
            -- prevent text being prepended to item on menu reload, i.e., on switching between reader and filemanager
            v.new = true
        end
        table.insert(menu_table["KOMenu:menu_buttons"][1], v)
    end
    return menu_table["KOMenu:menu_buttons"]
end

--- Returns a menu item by ID.
---- @param tbl Lua table
---- @param needle_id Menu item ID string
---- @treturn table a reference to the table item if found
function MenuSorter:findById(tbl, needle_id)
    local items = {}

    for _,item in pairs(tbl) do
        if item ~= "KOMenu:menu_buttons" then
            table.insert(items, item)
        end
    end

    local k, v
    k, v = next(items, nil)
    while k do
        if v.id == needle_id then
            return v
        elseif v.sub_item_table then
            for _,item in pairs(v.sub_item_table) do
                if type(item) == "table" and item.id then
                    table.insert(items, item)
                end
            end
        end
        k, v = next(items, k)
    end
end

return MenuSorter
