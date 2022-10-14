local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")

local GazetteMessages = require("gazettemessages")
local ConfigureSubscription = require("composers/configure_subscription")

local ResultsActionDialog = {}

function ResultsActionDialog:show(subscription_results, subscription)
   local button_dialog -- Declare variable here so it can be passed into ButtonDialog
   button_dialog = ButtonDialog:new{
      buttons = {
         {
            {
               text = "View results",
               callback = function()
                  UIManager:close(button_dialog)
                  ViewResults:forSubscription(subscription, subscription_results)
               end,
            },
         },
         {
            {
               text = "Go to downloads",
               callback = function()
                  UIManager:close(button_dialog)
               end,
            },
         },
      }
   }
   UIManager:show(button_dialog)
end

return ResultsActionDialog
