local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local GazetteMessages = require("gazettemessages")

local EditDialog = {

}

EditDialog.URL = 1
EditDialog.DOWNLOAD_DIRECTORY = 2
EditDialog.LIMIT = 3
EditDialog.CONTENT_SOURCE = 4

function EditDialog:newFeed(composer)
   local dialog
   local passed_test = false
   dialog = MultiInputDialog:new{
      title = _("Add a RSS or Atom feed"),
      fields = {
         {
            description = _("URL"),
            text = _("https://"),
            hint = _("URL"),
         },
         {
            description = _("Download directory"),
            text = composer:getDownloadDirectory()
         },
         {
            description = _("Limit"),
            text = composer:getLimit()
         },
         {
            description = _("Content source"),
            text = composer:getContentSource(),
         },
      },
      buttons = {
         {
            {
               text = _("Cancel"),
               id = "close",
               callback = function()
                  UIManager:close(dialog)
               end
            },
            {
               text = _("Test"),
               callback = function()
                  local Trapper = require("ui/trapper")
                  Trapper:wrap(function()
                        passed_test, new_subscription = composer:testFeed(dialog)
                        if passed_test
                        then
                           composer:updateSubscriptionFromTest(new_subscription)
                        end
                  end)
               end
            },
            {
               text = _("Set download directory"),
               callback = function()
                  composer:chooseDownloadDirectory(function(path)
                     if path
                     then
                        dialog:getInputFields()[2]:setText(path)
                     end
                  end)
               end
            },
            {
               text = _("Save"),
               callback = function(touchmenu_instance)
                  local Trapper = require("ui/trapper")
                  Trapper:wrap(function()
                        if not passed_test
                        then
                           Trapper:info(GazetteMessages.CONFIGURE_SUBSCRIPTION_FEED_NOT_TESTED)
                        else
                           composer:updateFromDialog(dialog)
                           composer:saveSubscription()
                           self:close(dialog)
                        end
                  end)
               end
            },
         },
      },
   }
   return dialog
end

function EditDialog:editFeed(composer, subscription)
   local dialog
   local passed_test = false
   dialog = MultiInputDialog:new{
      title = _("Edit feed"),
      fields = {
         {
            description = _("URL"),
            text = subscription.url
         },
         {
            description = _("Download Directory"),
            text = subscription:getDownloadDirectory()
         },
         {
            description = _("Limit"),
            text = composer:getLimit()
         },
         {
            description = _("Content Source"),
            text = composer:getContentSource()
         },
      },
      buttons = {
         {
            {
               text = _("Cancel"),
               id = "close",
               callback = function()
                  UIManager:close(dialog)
               end
            },
            {
               text = _("Test"),
               callback = function()
                  local Trapper = require("ui/trapper")
                  Trapper:wrap(function()
                        passed_test, new_subscription = composer:testFeed(dialog)

                        if passed_test
                        then
                           passed_test = true
                           -- This next assignment is not ideal. If there is any important
                           -- history in the stored subscription, it'll be overwritten. So this
                           -- could actually cause a dissonance between what the user has or hasn't read.
                           -- Better would be to just update the subscription with the changed fields.
                           composer:updateSubscriptionFromTest(new_subscription)
                        end
                  end)
               end
            },
            {
               text = _("Set download directory"),
               callback = function()
                  composer:chooseDownloadDirectory(function(path)
                     if path
                     then
                        dialog:getInputFields()[2]:setText(path)
                     end
                  end)
               end
            },
            {
               text = _("Delete"),
               callback = function()
                  local Trapper = require("ui/trapper")
                  Trapper:wrap(function()
                        composer:deleteSubscription()
                        UIManager:close(dialog)
                        dialog.callback()
                  end)
               end
            },
            {
               text = _("Save"),
               callback = function(touchmenu_instance)
                  local Trapper = require("ui/trapper")
                  Trapper:wrap(function()
                        if composer:hasUrlChanged(dialog) and
                           passed_test == false
                        then
                           Trapper:info(GazetteMessages.CONFIGURE_SUBSCRIPTION_FEED_NOT_TESTED)
                        else
                           composer:updateFromDialog(dialog)
                           composer:saveSubscription()
                           self:close(dialog)
                        end
                  end)
               end
            },
         },
p      },
   }
   return dialog
end

function EditDialog:close(dialog)
   dialog.callback()
   UIManager:close(dialog)
end

return EditDialog
