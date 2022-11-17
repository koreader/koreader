local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")

local Subscriptions = require("subscription/subscriptions")
local GazetteMessages = require("gazettemessages")
local ViewResults = require("composers/view_results")

local SyncSubscriptions = {}

function SyncSubscriptions:sync(subscriptions_to_sync)
   local Trapper = require("ui/trapper")
   NetworkMgr:runWhenOnline(function()
         Trapper:wrap(function()
               Trapper:info(GazetteMessages.SYNC_SUBSCRIPTIONS_SYNC)
               local subscriptions = Subscriptions:sync(
                  function(update)
                     Trapper:info(update)
                  end,
                  function(results)
                     Trapper:reset()
                     NetworkMgr:afterWifiAction()
                     ViewResults:listAll()
                  end,
                  subscriptions_to_sync
               )
         end)
   end)
end

function SyncSubscriptions:refresh()
   UIManager:close(self.view)
   SyncSubscriptions:list()
end

return SyncSubscriptions
