local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")

local GazetteMessages = require("gazettemessages")
local ConfigureSubscription = require("composers/configure_subscription")
local Results = require("subscription/result/results")

local SubscriptionActionDialog = {}

function SubscriptionActionDialog:show(subscription, on_close_callback)
   local button_dialog -- Declare variable here so it can be passed into ButtonDialog
   button_dialog = ButtonDialog:new{
      buttons = {
         {
            {
               text = GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_EDIT,
               callback = function()
                  UIManager:close(button_dialog)
                  ConfigureSubscription:editFeed(subscription, function()
                        on_close_callback()
                  end)
               end,
            },
         },
         {
            {
               text = GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_CLEAR_RESULTS,
               callback = function()
                  UIManager:close(button_dialog)
                  Results.deleteForSubscription(subscription.id)
                  on_close_callback()
               end,
            },
         },
         {
            {
               text = GazetteMessages.SUBSCRIPTION_ACTION_DIALOG_DELETE,
               callback = function()
                  UIManager:close(button_dialog)
                  subscription:delete()
                  on_close_callback()
               end,
            },
         },
      }
   }
   UIManager:show(button_dialog)
end

return SubscriptionActionDialog
