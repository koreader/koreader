local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local FeedView = require("feed_view")
local FeedSource = require("feed_source")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local KeyValuePage = require("ui/widget/keyvaluepage")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local Persist = require("persist")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local NewsDownloader = WidgetContainer:new{
    name = "news_downloader",
    initialized = false,
    feed_config_file = "feed_config.lua",
    feed_config_path = nil,
    news_config_file = "news_settings.lua",
    news_history_file = "news_history.lua",
    settings = nil,
    history = nil,
    download_dir_name = "news",
    download_dir = nil,
    config_key_custom_dl_dir = "custom_dl_dir",
    empty_feed = {
        [1] = "https://",
        limit = 5,
        download_full_article = true,
        include_images = true,
        enable_filter = false,
        filter_element = "",
        volumize = false
    },
    kv = {}
}

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    menu_items.news_downloader = {
        text = _("News downloader (RSS/Atom)"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function NewsDownloader:getSubMenuItems()
    self:lazyInitialization()
    local sub_item_table
    sub_item_table = {
        {
            text = _("Go to news folder"),
            callback = function()
                self:openDownloadsFolder()
            end,
        },
        {
            text = _("Sync news feeds"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                NetworkMgr:runWhenOnline(
                    function() self:syncAllFeedsWithUI(
                            touchmenu_instance,
                            function(feed_message)
                                -- Callback to fire after sync is finished
                                local UI = require("ui/trapper")
                                -- This callback is called after the
                                -- processing is complete.
                                --
                                -- Clear the info widgets before displaying the next ui widget.
                                -- UI:clear()
                                -- Ask the user if they want to go to their downloads folder
                                -- or if they'd rather remain at the menu.
                                feed_message = feed_message _("Go to downloaders folder?")
                                local should_go_to_downloads = UI:confirm(
                                    feed_message,
                                    _("Close"),
                                    _("Go to downloads")
                                )
                                if should_go_to_downloads then
                                    -- Go to downloads folder.
                                    UI:clear()
                                    self:openDownloadsFolder()
                                    touchmenu_instance:closeMenu()
                                    NetworkMgr:afterWifiAction()
                                    return
                                else
                                    -- Return to the menu.
                                    NetworkMgr:afterWifiAction()
                                    return
                                end
                            end
                ) end)
            end,
        },
        {
            text = _("Edit news feeds"),
            keep_menu_open = true,
            callback = function()
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                        self:viewFeedList()
                end)

            end,
        },
        {
            text = _("Settings"),
            sub_item_table = {
                {
                    text = _("Set download folder"),
                    keep_menu_open = true,
                    callback = function() self:setCustomDownloadDirectory() end,
                },
                {
                    text = _("Delete all downloaded items"),
                    keep_menu_open = true,
                    callback = function()
                        local Trapper = require("ui/trapper")
                        Trapper:wrap(function()
                                local should_delete = Trapper:confirm(
                                    _("Are you sure you want to delete all downloaded items?"),
                                    _("Cancel"),
                                    _("Delete")
                                )
                                if should_delete then
                                    self:removeNewsButKeepFeedConfig()
                                    -- Move user to the downloads folder to avoid an error where they
                                    -- are within a feed folder which we have just deleted.
                                    self:openDownloadsFolder()
                                    Trapper:reset()
                                else
                                    Trapper:reset()
                                end
                        end)
                    end,
                },
            },
        },
        {
            text = _("About"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                                   text = T(_("News downloader retrieves RSS and Atom news entries and stores them to:\n%1\n\nEach entry is a separate EPUB file that can be browsed by KOReader.\nFeeds can be configured with download limits and other customization through the Edit Feeds menu item."),
                                            BD.dirpath(self.download_dir))
                })
            end,
        },
    }
    return sub_item_table
end
-- lazyInitialization sets up our variables to point to the
-- Downloads folder and the feeds configuration file.
function NewsDownloader:lazyInitialization()
    if not self.initialized then
        logger.dbg("NewsDownloader: obtaining news folder")
        self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.news_config_file))
        -- Check to see if a custom download directory has been set.
        if self.settings:has(self.config_key_custom_dl_dir) then
            self.download_dir = self.settings:readSetting(self.config_key_custom_dl_dir)
        else
            self.download_dir =
                ("%s/%s/"):format(
                    DataStorage:getFullDataDir(),
                    self.download_dir_name)
        end
        logger.dbg("NewsDownloader: initializing download history")
        self.history = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.news_history_file))
        logger.dbg("NewsDownloader: Custom directory set to:", self.download_dir)
        -- If the directory doesn't exist we will create it.
        if not lfs.attributes(self.download_dir, "mode") then
            logger.dbg("NewsDownloader: Creating initial directory")
            lfs.mkdir(self.download_dir)
        end
        -- Now set the path to the feed configuration file.
        self.feed_config_path = self.download_dir .. self.feed_config_file
        -- If the configuration file doesn't exist create it.
        if not lfs.attributes(self.feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial feed config.")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, self.feed_config_file),
                             self.feed_config_path)
        end
        self.initialized = true
    end
end
-- This function loads the config file. If the config is not available
-- then this function includes prompts for handling that.
function NewsDownloader:loadConfig()
    local UI = require("ui/trapper")
    logger.dbg("force repaint due to upcoming blocking calls")
    -- Check if the feed config file exists
    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return false
    end
    -- If the file contains no table elements, then the user hasn't set any feeds.
    if #feed_config <= 0 then
        logger.err("NewsDownloader: empty feed list.", self.feed_config_path)
        local should_edit_feed_list = UI:confirm(
            T(_("Feed list is empty. If you want to download news, you'll have to add a feed first.")),
            _("Close"),
            _("Edit feed list")
        )
        if should_edit_feed_list then
            -- Show the user a blank feed view so they can
            -- add a feed to their list.
            local feed_item_vc = FeedView:getItem(
                1,
                self.empty_feed,
                function(id, edit_key, value)
                    self:editFeedAttribute(id, edit_key, value)
                end
            )
            self:viewFeedItem(
                feed_item_vc
            )
        end
        return false
    end
    -- If we made it this far, then the feed config is valid
    -- and the next step is to process its contents
    return feed_config
end

function NewsDownloader:syncAllFeedsWithUI(touchmenu_instance, callback)
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
            local UI = require("ui/trapper")
            -- Get the config
            local config = self:loadConfig()
            local sync_errors = {}
            -- Get the HTML for the feeds
            local feedSource = FeedSource:new{}
            -- Get the initialized feeds list
            local initialized_feeds = feedSource:getInitializedFeeds(
                config,
                function(progress_message)
                    -- This callback relays updates to the UI
                    UI:info(progress_message)
                end,
                function(error_message)
                    table.insert(
                        sync_errors,
                        error_message
                    )
                end
            )
            -- In this block, each feed item will be its own
            -- epub complete with title and chapters
            local epubs_to_make = {}
            local epubs_successfully_created = {}
            local feed_history = {}

            for feed_index, feed in pairs(initialized_feeds) do
                -- Go through each feed and make new entry
                local items_content = feedSource:getItemsContent(
                    feed,
                    function(progress_message)
                        UI:info(progress_message)
                    end,
                    function(error_message)
                        table.insert(
                            sync_errors,
                            error_message
                        )
                    end
                )

                local volumize = feed.config.volumize ~= false
                local chapters = {}
                local feed_title = feedSource:getFeedTitleWithDate(feed)
                local feed_id = feed.config[1] -- The url.
                local sub_dir = feedSource:getFeedTitle(feed.document.title)
                local item_history = {}

                for content_index, content in pairs(items_content) do
                    -- Check to see if we've already downloaded this item.
                    local history_for_feed = self.history:child(feed_id)

                    if history_for_feed:has(content.md5) then
                        logger.dbg("NewsDownloader: ", "Item already downloaded")
                        UI:info(_("Skipping downloaded item"))
                    else
                        local abs_path = feedSource:getEpubOutputDir(
                            self.download_dir,
                            sub_dir,
                            content.item_title
                        )

                        -- Not sure the slug returned is what we want.
                        -- Should be something like 2022_09_20-ArticleTitle
                        table.insert(
                            chapters,
                            {
                                title = content.item_title,
                                slug = content.item_slug,
                                md5 = content.md5,
                                html = content.html,
                                images = content.images
                            }
                        )

                        if not volumize then
                            -- We're not volumizing, so each chapter
                            -- will be its own epub.
                            table.insert(
                                epubs_to_make,
                                {
                                    title = content.item_title,
                                    chapters = chapters,
                                    abs_path = abs_path,
                                    id = feed_id,
                                }
                            )
                            -- Reset the chapters list.
                            chapters = {}
                        end

                        table.insert(
                            item_history,
                            content.md5
                        )
                    end
                end
                -- We're volumizing, so all of the chapters we collected
                -- get added to a single epub.
                if volumize and #chapters > 0 then
                    local abs_path = feedSource:getEpubOutputDir(
                        self.download_dir,
                        sub_dir,
                        feed_title
                    )

                    table.insert(
                        epubs_to_make,
                        {
                            title = feed_title,
                            chapters = chapters,
                            abs_path = abs_path,
                            id = feed_id,
                        }
                    )
                end

                feed_history[feed_id] = item_history
            end

            -- Make each EPUB.
            for epub_index, epub in pairs(epubs_to_make) do
                local ok = feedSource:createEpub(
                    epub.title,
                    epub.chapters,
                    epub.abs_path,
                    function(progress_message)
                        UI:info(progress_message)
                    end,
                    function(error_message)
                        table.insert(
                            sync_errors,
                            error_message
                        )
                    end
                )
                if ok then
                    -- Save the hashes to the setting for this feed.
                    local hashes_to_save = feed_history[epub.id]
                    local history_for_feed = self.history:child(epub.id)

                    for index, hash in ipairs(hashes_to_save) do
                        if history_for_feed:hasNot(hash) then
                            history_for_feed:saveSetting(hash, true)
                        end
                    end
                    -- Add the epub title to the successfully created table.
                    table.insert(
                        epubs_successfully_created,
                        epub.title
                    )
                else
                    table.insert(
                        sync_errors,
                        T(
                            _('Error building EPUB %1'),
                            epub.title
                        )
                    )
                end
            end

            logger.dbg(epubs_to_make)

            self.history:flush()

            -- Relay any errors
            for index, error_message in pairs(sync_errors) do
                UI:confirm(
                    error_message,
                    _("Continue"),
                    ""
                )
            end

            local message = (#epubs_successfully_created == 0) and
                _("Sync complete. No new EPUBs created.") or
                T(_("Sync complete. EPUBs created: %1"),
                  table.concat(epubs_successfully_created, ", "))

            callback(message)
    end)
end

function NewsDownloader:removeNewsButKeepFeedConfig()
    logger.dbg("NewsDownloader: Removing news from :", self.download_dir)
    for entry in lfs.dir(self.download_dir) do
        if entry ~= "." and entry ~= ".." and entry ~= self.feed_config_file then
            local entry_path = self.download_dir .. "/" .. entry
            local entry_mode = lfs.attributes(entry_path, "mode")
            if entry_mode == "file" then
                os.remove(entry_path)
            elseif entry_mode == "directory" then
                FFIUtil.purgeDir(entry_path)
            end
        end
    end
    UIManager:show(InfoMessage:new{
                       text = _("All downloaded news feed items deleted. To download these again in the future, reset the feed history.")
    })
end

function NewsDownloader:setCustomDownloadDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("NewsDownloader: set download directory to: ", path)
            self.settings:saveSetting(self.config_key_custom_dl_dir, ("%s/"):format(path))
            self.settings:flush()

            logger.dbg("NewsDownloader: Coping to new download folder previous self.feed_config_file from: ", self.feed_config_path)
            FFIUtil.copyFile(self.feed_config_path, ("%s/%s"):format(path, self.feed_config_file))

            self.initialized = false
            self:lazyInitialization()
        end,
                                 }:chooseDir()
end

function NewsDownloader:viewFeedList()
    -- Protected call to see if feed config path returns a file that can be opened.
    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        local UI = require("ui/trapper")
        local change_feed_config = UI:confirm(
            _("Could not open feed list. Feeds configuration file is invalid."),
            _("Close"),
            _("View file")
        )
        if change_feed_config then
            self:changeFeedConfig()
        end
        return
    end

    local view_content = FeedView:getList(
        feed_config,
        function(feed_item_vc)
            self:viewFeedItem(
                feed_item_vc
            )
        end,
        function(id, edit_key, value)
            self:editFeedAttribute(id, edit_key, value)
        end,
        function(id, action)
            if action == FeedView.ACTION_DELETE_FEED then
                self:deleteFeed(id)
            elseif action == FeedView.ACTION_RESET_HISTORY then
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                        local should_reset = Trapper:confirm(
                            _("Are you sure you want to reset the feed history? Proceeding will cause items to be re-downloaded next time you sync."),
                            _("Cancel"),
                            _("Reset")
                        )
                        if should_reset then
                            self:resetFeedHistory(id)
                            Trapper:reset()
                        else
                            Trapper:reset()
                        end
                end)
            end
        end
    )
    -- Add a "Add new feed" button with callback
    table.insert(
        view_content,
        {
            _("Add new feed"),
            "",
            callback = function()
                -- Prepare the view with all the callbacks for editing the attributes
                local feed_item_vc = FeedView:getItem(
                    #feed_config + 1,
                    self.empty_feed,
                    function(id, edit_key, value)
                        self:editFeedAttribute(id, edit_key, value)
                    end
                )
                self:viewFeedItem(
                    feed_item_vc
                )
            end
        }
    )
    -- Show the list of feeds.
    if #self.kv ~= 0 then
        UIManager:close(self.kv)
    end
    self.kv = KeyValuePage:new{
        title = _("RSS/Atom feeds"),
        value_overflow_align = "right",
        kv_pairs = view_content,
        callback_return = function()
            UIManager:close(self.kv)
        end
    }
    UIManager:show(self.kv)
end

function NewsDownloader:viewFeedItem(data)
    if #self.kv ~= 0 then
        UIManager:close(self.kv)
    end
    self.kv = KeyValuePage:new{
        title = _("Edit Feed"),
        value_overflow_align = "left",
        kv_pairs = data,
        callback_return = function()
            self:viewFeedList()
        end
    }
    UIManager:show(self.kv)
end

function NewsDownloader:editFeedAttribute(id, key, value)
    local kv = self.kv
    -- This block determines what kind of UI to produce, or action to run,
    -- based on the key value. Some values need an input dialog, others need
    -- a Yes/No dialog.
    if key == FeedView.RESET_HISTORY then
        -- Show a "are you sure" box.
        -- Reset the history
        self.history:removeTableItem(value, 1)
        self.history:flush()
    elseif key == FeedView.URL
        or key == FeedView.LIMIT
        or key == FeedView.FILTER_ELEMENT then

        local title
        local input_type
        local description

        if key == FeedView.URL then
            title = _("Edit feed URL")
            input_type = "string"
        elseif key == FeedView.LIMIT then
            title = _("Edit feed limit")
            description = _("Set to 0 for no limit to how many items are downloaded")
            input_type = "number"
        elseif key == FeedView.FILTER_ELEMENT then
            title = _("Edit filter element.")
            description = _("Filter based on the given CSS selector. E.g.: name_of_css.element.class")
            input_type = "string"
        else
            return false
        end

        local input_dialog
        input_dialog = InputDialog:new{
            title = title,
            input = value,
            input_type = input_type,
            description = description,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(input_dialog)
                            UIManager:show(kv)
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(input_dialog)
                            self:updateFeedConfig(id, key, input_dialog:getInputValue())
                        end,
                    },
                }
            },
        }
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
        return true
    else
        local text
        if key == FeedView.DOWNLOAD_FULL_ARTICLE then
            text = _("Download full article?")
        elseif key == FeedView.INCLUDE_IMAGES then
            text = _("Include images?")
        elseif key == FeedView.ENABLE_FILTER then
            text = _("Enable CSS filter?")
        elseif key == FeedView.VOLUMIZE then
            text = _("Volumize feed?")
        end

        local multi_box
        multi_box= MultiConfirmBox:new{
            text = text,
            choice1_text = _("Yes"),
            choice1_callback = function()
                UIManager:close(multi_box)
                self:updateFeedConfig(id, key, true)
            end,
            choice2_text = _("No"),
            choice2_callback = function()
                UIManager:close(multi_box)
                self:updateFeedConfig(id, key, false)
            end,
            cancel_callback = function()
                UIManager:close(multi_box)
                UIManager:show(kv)
            end,
        }
        UIManager:show(multi_box)
    end
end

function NewsDownloader:updateFeedConfig(id, key, value)
    local UI = require("ui/trapper")
    -- Because this method is called at the menu,
    -- we might not have an active view. So this conditional
    -- statement avoids closing a null reference.
    if #self.kv ~= 0 then
        UIManager:close(self.kv)
    end
    -- It's possible that we will get a null value.
    -- This block catches that possibility.
    if id ~= nil and key ~= nil and value ~= nil then
        -- This logger is a bit opaque because T() wasn't playing nice with booleans
        logger.dbg("Newsdownloader: attempting to update config:")
    else
        logger.dbg("Newsdownloader: null value supplied to update. Not updating config")
        return
    end

    local ok, feed_config = pcall(dofile, self.feed_config_path)

    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- If the file contains no table elements, then the user hasn't set any feeds.
    if #feed_config <= 0 then
        logger.dbg("NewsDownloader: empty feed list.", self.feed_config_path)
    end
    -- Check to see if the id is larger than the number of feeds. If it is,
    -- then we know this is a new add. Insert the base array.
    if id > #feed_config then
        table.insert(
            feed_config,
            self.empty_feed
        )
    end

    local new_config = {}
    -- In this loop, we cycle through the feed items. A series of
    -- conditionals checks to see if we are at the right id
    -- and key (i.e.: the key that triggered this function.
    -- If we are at the right spot, we overrite (or create) the value
    for idx, feed in ipairs(feed_config) do
        -- Check to see if this is the correct feed to update.
        if idx == id then
            if key == FeedView.URL then
                if feed[1] then
                    -- If the value exists, then it's been set. So all we do
                    -- is overwrite the value.
                    feed[1] = value
                else
                    -- If the value doesn't exist, then we need to set it.
                    -- So we insert it into the table.
                    table.insert(
                        feed,
                        {
                            value
                        }
                    )
                end
            elseif key == FeedView.LIMIT then
                feed.limit = value
            elseif key == FeedView.DOWNLOAD_FULL_ARTICLE then
                feed.download_full_article = value
            elseif key == FeedView.INCLUDE_IMAGES then
                feed.include_images = value
            elseif key == FeedView.ENABLE_FILTER then
                feed.enable_filter = value
            elseif key == FeedView.FILTER_ELEMENT then
                feed.filter_element = value
            elseif key == FeedView.VOLUMIZE then
                feed.volumize = value
            end
        end
        -- Now we insert the updated (or newly created) feed into the
        -- new config feed that we're building in this loop.
        table.insert(
            new_config,
            feed
        )
    end
    -- Save the config
    logger.dbg("NewsDownloader: config to save", new_config)
    self:saveConfig(new_config)
    -- Refresh the view
    local feed_item_vc = FeedView:getItem(
        id,
        new_config[id],
        function(cb_id, cb_edit_key, cb_value)
            self:editFeedAttribute(cb_id, cb_edit_key, cb_value)
        end,
        function(feed_id, action)
            if action == FeedView.ACTION_DELETE_FEED then
                self:deleteFeed(feed_id)
            elseif action == FeedView.ACTION_RESET_HISTORY then
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                        local should_reset = Trapper:confirm(
                            _("Are you sure you want to reset the feed history? Proceeding will cause items to be re-downloaded next time you sync."),
                            _("Cancel"),
                            _("Reset")
                        )
                        if should_reset then
                            self:resetFeedHistory(id)
                            Trapper:reset()
                        else
                            Trapper:reset()
                        end
                end)
            end
        end
    )
    self:viewFeedItem(
        feed_item_vc
    )
end

function NewsDownloader:deleteFeed(id)
    local UI = require("ui/trapper")
    logger.dbg("Newsdownloader: attempting to delete feed")
    -- Check to see if we can get the config file.
    local ok, feed_config = pcall(dofile, self.feed_config_path)

    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- In this loop, we cycle through the feed items. A series of
    -- conditionals checks to see if we are at the right id
    -- and key (i.e.: the key that triggered this function.
    -- If we are at the right spot, we overrite (or create) the value
    local new_config = {}

    for idx, feed in ipairs(feed_config) do
        -- Check to see if this is the correct feed to update.
        if idx ~= id then
            table.insert(
                new_config,
                feed
            )
        end
    end
    -- Save the config
    local Trapper = require("ui/trapper")

    Trapper:wrap(function()
            logger.dbg("NewsDownloader: config to save", new_config)
            self:saveConfig(new_config)
    end)
    -- Refresh the view
    self:viewFeedList()
end

function NewsDownloader:resetFeedHistory(url)
    logger.dbg("Newsdownloader: attempting to reset feed history")
    self.history:saveSetting(url, {})
    self.history:flush()
    -- Refresh the view
    self:viewFeedList()
end

function NewsDownloader:saveConfig(config)
    local UI = require("ui/trapper")
    UI:info(_("Saving news feed list…"))
    local persist = Persist:new{
        path = self.feed_config_path
    }
    local ok = persist:save(config)
    if not ok then
        UI:info(_("Could not save news feed config."))
    else
        UI:info(_("News feed config updated successfully."))
    end
    UI:reset()
end

-- This function opens an input dialog that lets the user
-- manually change their feed config. This function is called
-- when there is an error with the parsing.
function NewsDownloader:changeFeedConfig()
    local feed_config_file = io.open(self.feed_config_path, "rb")
    local config = feed_config_file:read("*all")
    feed_config_file:close()
    local config_editor
    logger.info("NewsDownloader: opening configuration file", self.feed_config_path)
    config_editor = InputDialog:new{
        title = T(_("Config: %1"), BD.filepath(self.feed_config_path)),
        input = config,
        input_type = "string",
        para_direction_rtl = false, -- force LTR
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = function()
            return config
        end,
        save_callback = function(content)
            if content and #content > 0 then
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local syntax_okay, syntax_error = pcall(loadstring(content))
                    if syntax_okay then
                        feed_config_file = io.open(self.feed_config_path, "w")
                        feed_config_file:write(content)
                        feed_config_file:close()
                        return true, _("Configuration saved")
                    else
                        return false, T(_("Configuration invalid: %1"), syntax_error)
                    end
                else
                    return false, T(_("Configuration invalid: %1"), parse_error)
                end
            end
            return false, _("Configuration empty")
        end,
    }
    UIManager:show(config_editor)
    config_editor:onShowKeyboard()
end

function NewsDownloader:openDownloadsFolder()
    local FileManager = require("apps/filemanager/filemanager")
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(self.download_dir)
    else
        FileManager:showFiles(self.download_dir)
    end
end

function NewsDownloader:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and self.download_dir and self.download_dir == string.sub(document_full_path, 1, string.len(self.download_dir)) then
        logger.dbg("NewsDownloader: document_full_path:", document_full_path)
        logger.dbg("NewsDownloader: self.download_dir:", self.download_dir)
        logger.dbg("NewsDownloader: removing NewsDownloader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
        local doc_dir = util.splitFilePathName(document_full_path)
        self.ui:setLastDirForFileBrowser(doc_dir)
    end
end

return NewsDownloader
