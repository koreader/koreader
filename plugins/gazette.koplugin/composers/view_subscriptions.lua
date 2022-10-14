local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")

local GazetteMessages = require("gazettemessages")
local Subscriptions = require("subscription/subscriptions")
local ConfigureSubscription = require("composers/configure_subscription")
local SubscriptionActionDialog = require("composers/subscription_action_dialog")

local ViewSubscriptions = {}

function ViewSubscriptions:list()
   local kv_pairs = {}
   local subscriptions = Subscriptions.all()

   for _, subscription in pairs(subscriptions) do
      -- If a subscription hasn't had its feed value initialized,
      -- this will fail. So, maybe check if the feed is there,
      -- and if not, consider it a good time to update?
      -- Or don't include the subscription in the list?
      table.insert(kv_pairs, {
            subscription:getTitle(),
            subscription:getDescription(),
            callback = function()
               SubscriptionActionDialog:show(subscription, function()
                     ViewSubscriptions:refresh()
               end)
            end
      })
   end

   self.view = KeyValuePage:new{
         title = GazetteMessages.VIEW_SUBSCRIPTIONS_LIST,
         value_overflow_align = "right",
         kv_pairs = kv_pairs,
         title_bar_left_icon = "plus",
         title_bar_left_icon_tap_callback = function()
            ConfigureSubscription:newFeed(function(subscription)
                  ViewSubscriptions:refresh()
            end)
         end
   }

   UIManager:show(self.view)
end

function ViewSubscriptions:refresh()
   UIManager:close(self.view)
   ViewSubscriptions:list()
end

function ViewSubscriptions:goToDownloadDirectory(subscription)
   local FileManager = require("apps/filemanager/filemanager")
   if self.view
   then
      UIManager:close(self.view)
   end
   if FileManager.instance then
      FileManager.instance:reinit(subscription:getDownloadDirectory())
   else
      FileManager:showFiles(subscription:getDownloadDirectory())
   end
end

return ViewSubscriptions
