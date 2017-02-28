local DataStorage = require("datastorage")
local DEBUG = require("dbg")

local MenuSorter = {
    menu_table = {},
    sub_menus = {},
    separator = {
        text = "KOMenu:separator",
    },
    sub_menu_position,
}

-- thanks to http://stackoverflow.com/a/4991602/2470572
-- no need to load lfs here
local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function MenuSorter:readMSSettings(table)
    local menu_order = DataStorage:getSettingsDir().."/menu_order"

    if file_exists(menu_order..".lua") then
        return require(menu_order) or {}
    else
        return {}
    end
end

function MenuSorter:sort(item_table, order)
DEBUG(item_table, order)
    --local menu_table = {}
    --local separator = {
        --text = "KOMenu:separator",
    --}
    DEBUG("menu before user order", order)
    -- take care of user customizations
    local user_order = self:readMSSettings(item_table_name)
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
    local tmp_menu_table = {}
    -- the actual sorting of menu items
    for order_id, order_item in pairs (order) do
        DEBUG("order_id",order_id)
        DEBUG("order_item",order_item)
        DEBUG("item_table[order_id]",item_table[order_id])
        -- user might define non-existing menu item
        if item_table[order_id] ~= nil then
            --menu_table[order_id] = item_table[order_id]
            --item_table[order_id] = nil
            self.menu_table[order_id] = item_table[order_id]
            self.menu_table[order_id].id = order_id
            --item_table[order_id].processed = true
            DEBUG("self.menu_table[order_id]",self.menu_table[order_id])
            for order_number,order_number_id in ipairs(order_item) do
                DEBUG("order_number,order_number_id", order_number,order_number_id)

                -- this is a submenu, mark it for later
                if order[order_number_id] then
                    table.insert(self.sub_menus, order_number_id)
                    self.menu_table[order_id][order_number] = {
                        id = order_number_id,
                        --sub = true,
                    }
                -- regular, just insert a menu action
                else
                    --self.menu_table[order_id] = tmp_menu_table[order_id]

                    if order_number_id == "----------------------------" then
                        -- it's a separator
                        self.menu_table[order_id][order_number] = self.separator
                    elseif item_table[order_number_id] ~= nil then
                        item_table[order_number_id].id = order_number_id
                        self.menu_table[order_id][order_number] = item_table[order_number_id]
                        item_table[order_number_id] = nil
                    end
                end

            end
        else
            DEBUG("menu id not found:", order_id)
        end
    end
    --attach orphans based on menu_hint
    
    -- now do the submenus
    DEBUG("SUBMENUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUS")
    DEBUG("self.sub_menus", self.sub_menus)
    for i,sub_menu in ipairs(self.sub_menus) do
        self.sub_menu_position = {}
        self:findById(self.menu_table["KOMenu:menu_buttons"], sub_menu)
        if self.sub_menu_position and self.sub_menu_position.id then
            self.sub_menu_position.sub_item_table = self.menu_table[sub_menu]
            self.menu_table[sub_menu] = nil
        end
    end
    -- @TODO avoid this extra mini-loop
    -- cleanup, top-level items shouldn't have sub_item_table
    for i,top_menu in ipairs(self.menu_table["KOMenu:menu_buttons"]) do
        self.menu_table["KOMenu:menu_buttons"][i] = self.menu_table["KOMenu:menu_buttons"][i].sub_item_table
    end
    
    
end

function MenuSorter:findById(tbl, needle_id, result)


--DEBUG("TBL given",tbl)
    for k,v in pairs(tbl) do
        if #self.sub_menu_position == 1 then
            break
        end
        --DEBUG("FINDBYID:", needle_id, "current:", k,v)

        if type(k) == "number" or k == "sub_item_table" then
            if v.id == needle_id then
                DEBUG("FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT FOUND IT ", v.id)
                self.sub_menu_position = v
                break
            elseif type(v) == "table" and v.id then
                DEBUG("GOING DEEPER", v.id)
                self:findById(v, needle_id)
            end
        end
    end
end

return MenuSorter
