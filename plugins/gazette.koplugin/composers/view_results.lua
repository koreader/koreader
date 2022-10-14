local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local T = require("ffi/util").template

local GazetteMessages = require("gazettemessages")
local FeedSubscription = require("subscription/type/feed")
local Results = require("subscription/result/results")
local ViewSubscriptions = require("composers/view_subscriptions")

local ViewResults = {}

function ViewResults:listAll()
   local kv_pairs = {}
   local subscriptions_results = Results.all()

   for id, subscription_results in pairs(subscriptions_results) do
      -- If a subscription hasn't had its feed value initialized,
      -- this will fail. So, maybe check if the feed is there,
      -- and if not, consider it a good time to update?
      -- Or don't include the subscription in the list?
      local subscription = FeedSubscription:new({
            id = subscription_results.subscription_id
      })
      table.insert(kv_pairs, {
            subscription:getTitle(),
            subscription_results:getOverviewMessage(),
            callback = function()
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
                              ViewSubscriptions:goToDownloadDirectory(subscription)
                           end,
                        },
                     },
                  }
               }
               UIManager:show(button_dialog)
            end
      })
   end

   self.view = KeyValuePage:new{
      title = GazetteMessages.VIEW_RESULTS_LIST,
      value_overflow_align = "right",
      kv_pairs = kv_pairs,
   }

   UIManager:show(self.view)
end

function ViewResults:forSubscription(subscription, subscription_results)
   local kv_pairs = {}

   if not subscription_results
   then
      subscription_results = Results.forFeed(subscription.id)
   end

   for entry_id, entry_result in pairs(subscription_results:getEntryResults()) do
      table.insert(kv_pairs, {
            entry_result:getStatus(),
            entry_result:getIdentifier(),
            callback = function()
               local message = T(
                  GazetteMessages.RESULT_EXPAND_INFO,
                  entry_result:getStatus(),
                  entry_result:getStatusMessage(),
                  entry_result:getIdentifier()
               )
               local result_info = InfoMessage:new{
                  text = message
               }
               UIManager:show(result_info)
            end
      })
   end

   self.view = KeyValuePage:new{
      title = T(GazetteMessages.VIEW_RESULTS_SUBSCRIPTION_TITLE, subscription:getTitle()),
      value_overflow_align = "right",
      kv_pairs = kv_pairs,
   }

   UIManager:show(self.view)
end

function ViewResults:refresh()
   UIManager:close(self.view)
   ViewResults:list()
end

return ViewResults
