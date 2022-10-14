--[[--
Syndicated feed Reader... and more!

@module koplugin.Gazette
--]]--

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local GazetteMessages = require("gazettemessages")
local ConfigureSubscription = require("composers/configure_subscription")
local ViewSubscriptions = require("composers/view_subscriptions")
local SyncSubscriptions = require("composers/sync_subscriptions")
local ViewResults = require("composers/view_results")

local Gazette = WidgetContainer:new{
    name = "gazette",
}

function Gazette:init()
    self.ui.menu:registerToMainMenu(self)
end

function Gazette:addToMainMenu(menu_items)
    menu_items.gazette = {
        text = _("Gazette"),
        sorting_hint = "tools",
        sub_item_table_func = function()
           return self:getSubMenuItems()
        end,
    }
end

function Gazette:getSubMenuItems()
   return {
      {
         text = GazetteMessages.MENU_SYNC,
         keep_menu_open = true,
         callback = function()
            self:syncSubscriptions()
         end
      },
      {
         text = GazetteMessages.MENU_LIST_PREVIOUS_RESULTS,
         keep_menu_open = true,
         callback = function()
            self:viewResults()
         end,
         separator = true
      },
      {
         text = GazetteMessages.MENU_MANAGE_SUBSCRIPTIONS,
         keep_menu_open = true,
         callback = function()
            self:viewSubscriptions()
         end
      },
      {
         text = GazetteMessages.MENU_SETTINGS,
         keep_menu_open = true,
         sub_item_table = self:getConfigureSubMenuItems()
      }
   }
end

function Gazette:getConfigureSubMenuItems()
   return {
      -- {
      --    text = _("Add Subscription"),
      --    callback = function()
      --       ConfigureSubscription:newFeed()
      --    end
      -- },
   }
end

function Gazette:syncSubscriptions()
   SyncSubscriptions:sync()
end

function Gazette:viewSubscriptions()
   ViewSubscriptions:list()
end

function Gazette:viewResults()
   ViewResults:listAll()
end

return Gazette
