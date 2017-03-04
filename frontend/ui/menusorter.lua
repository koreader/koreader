--[[--
This module is responsible for constructing the KOReader menu based on a list of
menu_items and a separate menu order.
]]

local DataStorage = require("datastorage")
local util = require("util")
local DEBUG = require("dbg")
local _ = require("gettext")

local MenuSorter = {
    menu_table = {},
    orphaned_prefix = _("NEW: "),
    separator = {
        id = "----------------------------",
        text = "KOMenu:separator",
    },
}

-- thanks to http://stackoverflow.com/a/4991602/2470572
-- no need to load lfs here
local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function MenuSorter:readMSSettings(table, config_prefix)
    if config_prefix then
        local config_prefix = config_prefix.."_"
        local menu_order = DataStorage:getSettingsDir().."/"..config_prefix.."menu_order"

        if file_exists(menu_order..".lua") then
            return require(menu_order) or {}
        else
            return {}
        end
    else
        return {}
    end
end

function MenuSorter:sort(item_table, order, config_prefix)
DEBUG(item_table, order)
    --local menu_table = {}
    --local separator = {
        --text = "KOMenu:separator",
    --}
    DEBUG("menu before user order", order)
    -- take care of user customizations
    local user_order = self:readMSSettings(item_table_name, config_prefix)
    if user_order then
        for user_order_id,user_order_item in pairs(user_order) do
            for order_id, order_item in pairs (order) do
                if user_order_id == order_id then
                    order[order_id] = user_order[order_id]
                end
            end
        end
    end
    DEBUG("menu after user order", order)

    --self.menu_table = self:magic(item_table, order)
    self:magic(item_table, order)
    DEBUG("after sort",self.menu_table["KOMenu:menu_buttons"])


    
    -- deal with leftovers
    
    return self.menu_table["KOMenu:menu_buttons"]
end

function MenuSorter:magic(item_table, order)
    local sub_menus = {}
    -- the actual sorting of menu items
    for order_id, order_item in pairs (order) do
        DEBUG("order_id",order_id)
        DEBUG("order_item",order_item)
        DEBUG("item_table[order_id]",item_table[order_id])
        -- user might define non-existing menu item
        if item_table[order_id] ~= nil then
            local tmp_menu_table = {}
            self.menu_table[order_id] = item_table[order_id]
            --self.menu_table[order_id] = item_table[order_id]
            self.menu_table[order_id].id = order_id
            --item_table[order_id].processed = true
            DEBUG("tmp_menu_table[order_id]",tmp_menu_table[order_id])
            for order_number,order_number_id in ipairs(order_item) do
                DEBUG("order_number,order_number_id", order_number,order_number_id)

                -- this is a submenu, mark it for later
                if order[order_number_id] then
                    table.insert(sub_menus, order_number_id)
                    tmp_menu_table[order_number] = {
                        id = order_number_id,
                    }
                -- regular, just insert a menu action
                else
                    if order_number_id == "----------------------------" then
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
            --k, v = next(tmp_menu_table, nil)
            while i <= table.maxn(tmp_menu_table) do
                v = tmp_menu_table[i]
                if v then
                    if v.id == "----------------------------" then
                        new_index = new_index - 1
                        self.menu_table[order_id][new_index].separator = true
                    else
                        -- fix the index
                        self.menu_table[order_id][new_index] = tmp_menu_table[i]
                    end

                    new_index = new_index + 1
                end
                i = i + 1
            end
        else
            DEBUG("menu id not found:", order_id)
        end
    end

    -- now do the submenus
    DEBUG("SUBMENUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUS")
    DEBUG("self.sub_menus", sub_menus)
    for i,sub_menu in ipairs(sub_menus) do
        local sub_menu_position = self:findById(self.menu_table["KOMenu:menu_buttons"], sub_menu) or nil
        if sub_menu_position and sub_menu_position.id then
            sub_menu_position.sub_item_table = self.menu_table[sub_menu]
            -- remove reference from top level output
            self.menu_table[sub_menu] = nil
            -- remove reference from input so it won't show up as orphaned
            item_table[sub_menu] = nil
        end
    end
    -- @TODO avoid this extra mini-loop
    -- cleanup, top-level items shouldn't have sub_item_table
    for i,top_menu in ipairs(self.menu_table["KOMenu:menu_buttons"]) do
        self.menu_table["KOMenu:menu_buttons"][i] = self.menu_table["KOMenu:menu_buttons"][i].sub_item_table
    end

    -- handle disabled
    DEBUG("MenuSorter: order.KOMenu_disabled", order.KOMenu_disabled)
    if order.KOMenu__disabled then
        for _,item in ipairs(order.KOMenu_disabled) do
            if item_table[item] then
                -- remove reference from input so it won't show up as orphaned
                item_table[item] = nil
            end
        end
    end

    -- remove top level reference before orphan handling
    item_table["KOMenu:menu_buttons"] = nil
        --attach orphans based on menu_hint
    DEBUG("ORPHAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANSS", util.tableSize(item_table))
    for k,v in pairs(item_table) do
    DEBUG(k)
        -- normally there should be menu text but check to be sure
        if v.text and v.new ~= true then
            v.id = k
            v.text = self.orphaned_prefix .. v.text
            -- prevent text being prepended to item on menu reload, i.e., on switching between reader and filemanager
            v.new = true
        end
        table.insert(self.menu_table["KOMenu:menu_buttons"][1], v)
    end
end

--- Returns a menu item by ID.
---- @param tbl Lua table
---- @param needle_id Menu item ID string
---- @treturn table a reference to the table item if found
function MenuSorter:findById(tbl, needle_id)
    local items = {}

    for _,item in pairs(tbl) do
        table.insert(items, item)
    end

    local k, v
    k, v = next(items, nil)
    while k do
        if type(k) == "number" or k == "sub_item_table" then
            if v.id == needle_id then
                DEBUG("FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT ", v.id)
                return v
            elseif type(v) == "table" and v.id then
                DEBUG("GOING DEEPER", v.id)
                table.insert(items, v)
            end
        end
        k, v = next(items, k)
    end
end

return MenuSorter
