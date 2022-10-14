local util = require("frontend/util")

local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local EditDialog = require("views/subscription_edit_dialog")
local SubscriptionFactory = require("subscription/subscriptionfactory")
local FeedSubscription = require("subscription/type/feed")

local InfoMessage = require("ui/widget/infomessage")
local GazetteMessages = require("gazettemessages")
local Screen = require("device").screen
local T = require("ffi/util").template

local ConfigureSubscription = {
   subscription = nil,
}

function ConfigureSubscription:newFeed(callback)
   NetworkMgr:runWhenOnline(function()
         self.subscription = SubscriptionFactory:makeFeed({})
         local dialog = EditDialog:newFeed(self)
         dialog.callback = function()
            callback(self.subscription)
            NetworkMgr:afterWifiAction()
         end

         UIManager:show(dialog)
   end)
end

function ConfigureSubscription:editFeed(subscription, callback)
   NetworkMgr:runWhenOnline(function()
         self.subscription = subscription
         local dialog = EditDialog:editFeed(self, self.subscription)
         dialog.callback = function()
            callback(self.subscription)
            NetworkMgr:afterWifiAction()
         end

         UIManager:show(dialog)
   end)
end

function ConfigureSubscription:testFeed(dialog)
   local Trapper = require("ui/trapper")
   Trapper:info(GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_FEED_BEGIN)

   local test_subscription, err = ConfigureSubscription:createFeedFromDialog(dialog)

   if not test_subscription
   then
      local error_message = T(GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_ERROR, err)
      Trapper:info(error_message)
      return false
   end

   Trapper:info(GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_FETCH_URL)
   local success, err = test_subscription:sync()

   if not success
   then
      local error_message = T(GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_ERROR, err)
      Trapper:info(error_message)
      return false
   end

   local success_message = T(GazetteMessages.CONFIGURE_SUBSCRIPTION_TEST_SUCCESS, test_subscription.feed.title)
   Trapper:info(success_message)

   return true, test_subscription
end

function ConfigureSubscription:deleteSubscription()
   self.subscription:delete()
end

function ConfigureSubscription:saveSubscription()
   self.subscription:save()
end

function ConfigureSubscription:updateFromDialog(dialog)
   self.subscription.download_directory = self:getDownloadDirectoryFromDialog(dialog)
   self.subscription.url = self:getUrlFromDialog(dialog)
   self.subscription.limit = tonumber(self:getLimitFromDialog(dialog))
   self.subscription.content_source = self:getContentSourceFromDialog(dialog)
end

function ConfigureSubscription:hasUrlChanged(dialog)
   local url = dialog:getFields()[1]

   if url and
      url ~= self.subscription.url
   then
      return true
   else
      return false
   end
end

function ConfigureSubscription:chooseDownloadDirectory(callback)
   require("ui/downloadmgr"):new
   {
      onConfirm = function(path)
         -- Copy old dir to new dir?
         -- FFIUtil.copyFile(self.feed_config_path, ("%s/%s"):format(path, self.feed_config_file))
         if self.subscription:getTitle()
         then
            local safe_title = util.getSafeFilename(self.subscription:getTitle())
            path = string.format("%s/%s", path, safe_title)
         end

         self.subscription:setDownloadDirectory(path)
         callback(path)
      end
   }:chooseDir()
end

function ConfigureSubscription:setFeedUrl(url)
   self.subscription.url = url
end

function ConfigureSubscription:updateSubscriptionFromTest(new_subscription)
   self.subscription.url = new_subscription.url
   self.subscription.feed = new_subscription.feed
end

function ConfigureSubscription:getUrlFromDialog(dialog)
   local fields = dialog:getFields()
   return fields[EditDialog.URL]
end

function ConfigureSubscription:getDownloadDirectoryFromDialog(dialog)
   local fields = dialog:getFields()
   return fields[EditDialog.DOWNLOAD_DIRECTORY]
end

function ConfigureSubscription:getLimitFromDialog(dialog)
   local fields = dialog:getFields()
   return fields[EditDialog.LIMIT]
end

function ConfigureSubscription:getContentSourceFromDialog(dialog)
   local fields = dialog:getFields()
   return fields[EditDialog.CONTENT_SOURCE]
end

function ConfigureSubscription:getDownloadDirectory()
   return self.subscription:getDownloadDirectory()
end

function ConfigureSubscription:getLimit()
   return tostring(self.subscription.limit)
end

function ConfigureSubscription:getContentSource()
   return self.subscription:getContentSource()
end

function ConfigureSubscription:createFeedFromDialog(dialog)
   local configuration = {
      url = ConfigureSubscription:getUrlFromDialog(dialog)
   }

   local subscription, err = FeedSubscription:new({})
   subscription.url = configuration.url

   return subscription
end

return ConfigureSubscription
