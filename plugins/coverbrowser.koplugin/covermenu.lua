local ButtonDialog = require("ui/widget/buttondialog")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local BookInfoManager = require("bookinfomanager")

-- This is a kind of "base class" for both MosaicMenu and ListMenu.
-- It implements the common code shared by these, mostly the non-UI
-- work : the updating of items and the management of background jobs.
--
-- Here the common overridden methods of Menu are defined:
--    :updateItems(select_number)
--    :onCloseWidget()
--
-- MosaicMenu or ListMenu should implement specific UI methods:
--    :_recalculateDimen()
--    :_updateItemsBuildUI()
-- This last method is called in the middle of :updateItems() , and
-- should fill self.item_group with some specific UI layout. It may add
-- not found item to self.items_to_update for us to update() them
-- regularly.

-- Store these as local, to be set by some object and re-used by
-- another object (as we plug the methods below to different objects,
-- we can't store them in 'self' if we want another one to use it)
local current_path = nil
local current_cover_specs = false

-- Do some collectgarbage() every few drawings
local NB_DRAWINGS_BETWEEN_COLLECTGARBAGE = 5
local nb_drawings_since_last_collectgarbage = 0

-- Simple holder of methods that will replace those
-- in the real Menu class or instance
local CoverMenu = {}

function CoverMenu:updateCache(file, status, do_create, pages)
    if do_create then -- create new cache entry if absent
        if self.cover_info_cache[file] then return end
        local doc_settings = DocSettings:open(file)
        -- We can get nb of page in the new 'doc_pages' setting, or from the old 'stats.page'
        local doc_pages = doc_settings:readSetting("doc_pages")
        if doc_pages then
            pages = doc_pages
        else
            local stats = doc_settings:readSetting("stats")
            if stats and stats.pages and stats.pages ~= 0 then -- crengine with statistics disabled stores 0
                pages = stats.pages
            end
        end
        local percent_finished = doc_settings:readSetting("percent_finished")
        local summary = doc_settings:readSetting("summary")
        status = summary and summary.status
        local has_highlight
        local annotations = doc_settings:readSetting("annotations")
        if annotations then
            has_highlight = #annotations > 0
        else
            local highlight = doc_settings:readSetting("highlight")
            has_highlight = highlight and next(highlight) and true
        end
        self.cover_info_cache[file] = table.pack(pages, percent_finished, status, has_highlight) -- may be a sparse array
    else
        if self.cover_info_cache and self.cover_info_cache[file] then
            if status then
                self.cover_info_cache[file][3] = status
            else
                self.cover_info_cache[file] = nil
            end
        end
    end
end

function CoverMenu:updateItems(select_number, no_recalculate_dimen)
    -- As done in Menu:updateItems()
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    -- NOTE: Our various _recalculateDimen overloads appear to have a stronger dependency
    --       on the rest of the widget elements being properly laid-out,
    --       so we have to run it *first*, unlike in Menu.
    --       Otherwise, various layout issues arise (e.g., MosaicMenu's page_info is misaligned).
    if not no_recalculate_dimen then
        self:_recalculateDimen()
    end
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()

    -- Reset the list of items not found in db that will need to
    -- be updated by a scheduled action
    self.items_to_update = {}
    -- Cancel any previous (now obsolete) scheduled update
    if self.items_update_action then
        UIManager:unschedule(self.items_update_action)
        self.items_update_action = nil
    end

    -- Force garbage collecting before drawing a new page.
    -- It's not really needed from a memory usage point of view, we did
    -- all the free() where necessary, and koreader memory usage seems
    -- stable when file browsing only (15-25 MB).
    -- But I witnessed some freezes after browsing a lot when koreader's main
    -- process was using 100% cpu (and some slow downs while drawing soon before
    -- the freeze, like the full refresh happening before the final drawing of
    -- new text covers), while still having a small memory usage (20/30 Mb)
    -- that I suspect may be some garbage collecting happening at one point
    -- and getting stuck...
    -- With this, garbage collecting may be more deterministic, and it has
    -- no negative impact on user experience.
    -- But don't do it on every drawing, to not have all of them slow
    -- when memory usage is already high
    nb_drawings_since_last_collectgarbage = nb_drawings_since_last_collectgarbage + 1
    if nb_drawings_since_last_collectgarbage >= NB_DRAWINGS_BETWEEN_COLLECTGARBAGE then
        -- (delay it a bit so this pause is less noticeable)
        UIManager:scheduleIn(0.2, function()
            collectgarbage()
            collectgarbage()
        end)
        nb_drawings_since_last_collectgarbage = 0
    end

    -- Specific UI building implementation (defined in some other module)
    self._has_cover_images = false
    select_number = self:_updateItemsBuildUI() or select_number
    -- Set the local variables with the things we know
    -- These are used only by extractBooksInDirectory(), which should
    -- use the cover_specs set for FileBrowser, and not those from History.
    -- Hopefully, we get self.path=nil when called from History
    if self.path then
        current_path = self.path
        current_cover_specs = self.cover_specs
    end

    -- As done in Menu:updateItems()
    self:updatePageInfo(select_number)
    Menu.mergeTitleBarIntoLayout(self)

    self.show_parent.dithered = self._has_cover_images
    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen, self.show_parent.dithered
    end)

    -- As additionally done in FileChooser:updateItems()
    if self.path_items then
        self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
    end

    -- Deal with items not found in db
    if #self.items_to_update > 0 then
        -- Prepare for background info extraction job
        local files_to_index = {} -- table of {filepath, cover_specs}
        for i=1, #self.items_to_update do
            table.insert(files_to_index, {
                filepath = self.items_to_update[i].filepath,
                cover_specs = self.items_to_update[i].cover_specs
            })
        end
        -- Launch it at nextTick, so UIManager can render us smoothly
        UIManager:nextTick(function()
            local launched = BookInfoManager:extractInBackground(files_to_index)
            if not launched then -- fork failed (never experienced that, but let's deal with it)
                -- Cancel scheduled update, as it won't get any result
                if self.items_update_action then
                    UIManager:unschedule(self.items_update_action)
                    self.items_update_action = nil
                end
                UIManager:show(InfoMessage:new{
                    text = _("Start-up of background extraction job failed.\nPlease restart KOReader or your device.")
                })
            end
        end)

        -- Scheduled update action
        self.items_update_action = function()
            logger.dbg("Scheduled items update:", #self.items_to_update, "waiting")
            local is_still_extracting = BookInfoManager:isExtractingInBackground()
            local i = 1
            while i <= #self.items_to_update do -- process and clean in-place
                local item = self.items_to_update[i]
                item:update()
                if item.bookinfo_found then
                    logger.dbg("  found", item.text)
                    self.show_parent.dithered = item._has_cover_image
                    local refreshfunc = function()
                        if item.refresh_dimen then
                            -- MosaicMenuItem may exceed its own dimen in its paintTo
                            -- with its "description" hint
                            return "ui", item.refresh_dimen, self.show_parent.dithered
                        else
                            return "ui", item[1].dimen, self.show_parent.dithered
                        end
                    end
                    UIManager:setDirty(self.show_parent, refreshfunc)
                    table.remove(self.items_to_update, i)
                else
                    logger.dbg("  not yet found", item.text)
                    i = i + 1
                end
            end
            if #self.items_to_update > 0 then -- re-schedule myself
                if is_still_extracting then -- we have still chances to get new stuff
                    logger.dbg("re-scheduling items update:", #self.items_to_update, "still waiting")
                    UIManager:scheduleIn(1, self.items_update_action)
                else
                    logger.dbg("Not all items found, but background extraction has stopped, not re-scheduling")
                end
            else
                logger.dbg("items update completed")
            end
        end
        UIManager:scheduleIn(1, self.items_update_action)
    end

    -- (We may not need to do the following if we extend showFileDialog
    -- code in filemanager.lua to check for existence and call a
    -- method: self:getAdditionalButtons() to add our buttons
    -- to its own set.)

    -- We want to add some buttons to the showFileDialog popup. This function
    -- is dynamically created by FileManager:init(), and we don't want
    -- to override this... So, here, when we see the showFileDialog function,
    -- we replace it by ours.
    -- (FileManager may replace file_chooser.showFileDialog after we've been called once, so we need
    -- to replace it again if it is not ours)
    if self.path -- FileManager only
        and (not self.showFileDialog_ours -- never replaced
              or self.showFileDialog ~= self.showFileDialog_ours) then -- it is no more ours
        -- We need to do it at nextTick, once FileManager has instantiated
        -- its FileChooser completely
        UIManager:nextTick(function()
            -- Store original function, so we can call it
            self.showFileDialog_orig = self.showFileDialog

            -- Replace it with ours
            -- This causes luacheck warning: "shadowing upvalue argument 'self' on line 34".
            -- Ignoring it (as done in filemanager.lua for the same showFileDialog)
            self.showFileDialog = function(self, item) -- luacheck: ignore
                local file = item.path
                -- Call original function: it will create a ButtonDialog
                -- and store it as self.file_dialog, and UIManager:show() it.
                self.showFileDialog_orig(self, item)

                local bookinfo = self.book_props -- getBookInfo(file) called by FileManager
                if not bookinfo or bookinfo._is_directory then
                    -- If no bookinfo (yet) about this file, or it's a directory, let the original dialog be
                    return true
                end

                -- Remember some of this original ButtonDialog properties
                local orig_title = self.file_dialog.title
                local orig_title_align = self.file_dialog.title_align
                local orig_buttons = self.file_dialog.buttons
                -- Close original ButtonDialog (it has not yet been painted
                -- on screen, so we won't see it)
                UIManager:close(self.file_dialog)
                -- And clear the rendering stack to avoid inheriting its dirty/refresh queue
                UIManager:clearRenderStack()

                -- Add some new buttons to original buttons set
                table.insert(orig_buttons, {
                    { -- Allow user to ignore some offending cover image
                        text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
                        enabled = bookinfo.has_cover and true or false,
                        callback = function()
                            BookInfoManager:setBookInfoProperties(file, {
                                ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                            })
                            UIManager:close(self.file_dialog)
                            self:updateItems(1, true)
                        end,
                    },
                    { -- Allow user to ignore some bad metadata (filename will be used instead)
                        text = bookinfo.ignore_meta and _("Unignore metadata") or _("Ignore metadata"),
                        enabled = bookinfo.has_meta and true or false,
                        callback = function()
                            BookInfoManager:setBookInfoProperties(file, {
                                ["ignore_meta"] = not bookinfo.ignore_meta and 'Y' or false,
                            })
                            UIManager:close(self.file_dialog)
                            self:updateItems(1, true)
                        end,
                    },
                })
                table.insert(orig_buttons, {
                    { -- Allow a new extraction (multiple interruptions, book replaced)...
                        text = _("Refresh cached book information"),
                        callback = function()
                            -- Wipe the cache
                            self:updateCache(file)
                            BookInfoManager:deleteBookInfo(file)
                            UIManager:close(self.file_dialog)
                            self:updateItems(1, true)
                        end,
                    },
                })

                -- Create the new ButtonDialog, and let UIManager show it
                self.file_dialog = ButtonDialog:new{
                    title = orig_title,
                    title_align = orig_title_align,
                    buttons = orig_buttons,
                }
                UIManager:show(self.file_dialog)
                return true
            end

            -- Remember our function
            self.showFileDialog_ours = self.showFileDialog
        end)
    end
end

-- Similar to showFileDialog setup just above, but for History,
-- which is plugged in main.lua _FileManagerHistory_updateItemTable()
function CoverMenu:onHistoryMenuHold(item)
    -- Call original function: it will create a ButtonDialog
    -- and store it as self.histfile_dialog, and UIManager:show() it.
    self.onMenuHold_orig(self, item)
    local file = item.file

    local bookinfo = self.book_props -- getBookInfo(file) called by FileManagerHistory
    if not bookinfo then
        -- If no bookinfo (yet) about this file, let the original dialog be
        return true
    end

    -- Remember some of this original ButtonDialog properties
    local orig_title = self.histfile_dialog.title
    local orig_title_align = self.histfile_dialog.title_align
    local orig_buttons = self.histfile_dialog.buttons
    -- Close original ButtonDialog (it has not yet been painted
    -- on screen, so we won't see it)
    UIManager:close(self.histfile_dialog)
    UIManager:clearRenderStack()

    -- Add some new buttons to original buttons set
    table.insert(orig_buttons, {
        { -- Allow user to ignore some offending cover image
            text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                })
                UIManager:close(self.histfile_dialog)
                self:updateItems(1, true)
            end,
        },
        { -- Allow user to ignore some bad metadata (filename will be used instead)
            text = bookinfo.ignore_meta and _("Unignore metadata") or _("Ignore metadata"),
            enabled = bookinfo.has_meta and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_meta"] = not bookinfo.ignore_meta and 'Y' or false,
                })
                UIManager:close(self.histfile_dialog)
                self:updateItems(1, true)
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow a new extraction (multiple interruptions, book replaced)...
            text = _("Refresh cached book information"),
            callback = function()
                -- Wipe the cache
                self:updateCache(file)
                BookInfoManager:deleteBookInfo(file)
                UIManager:close(self.histfile_dialog)
                self:updateItems(1, true)
            end,
        },
    })

    -- Create the new ButtonDialog, and let UIManager show it
    self.histfile_dialog = ButtonDialog:new{
        title = orig_title,
        title_align = orig_title_align,
        buttons = orig_buttons,
    }
    UIManager:show(self.histfile_dialog)
    return true
end

-- Similar to showFileDialog setup just above, but for Collections,
-- which is plugged in main.lua _FileManagerCollections_updateItemTable()
function CoverMenu:onCollectionsMenuHold(item)
    -- Call original function: it will create a ButtonDialog
    -- and store it as self.collfile_dialog, and UIManager:show() it.
    self.onMenuHold_orig(self, item)
    local file = item.file

    local bookinfo = self.book_props -- getBookInfo(file) called by FileManagerCollection
    if not bookinfo then
        -- If no bookinfo (yet) about this file, let the original dialog be
        return true
    end

    -- Remember some of this original ButtonDialog properties
    local orig_title = self.collfile_dialog.title
    local orig_title_align = self.collfile_dialog.title_align
    local orig_buttons = self.collfile_dialog.buttons
    -- Close original ButtonDialog (it has not yet been painted
    -- on screen, so we won't see it)
    UIManager:close(self.collfile_dialog)
    UIManager:clearRenderStack()

    -- Add some new buttons to original buttons set
    table.insert(orig_buttons, {
        { -- Allow user to ignore some offending cover image
            text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                })
                UIManager:close(self.collfile_dialog)
                self:updateItems(1, true)
            end,
        },
        { -- Allow user to ignore some bad metadata (filename will be used instead)
            text = bookinfo.ignore_meta and _("Unignore metadata") or _("Ignore metadata"),
            enabled = bookinfo.has_meta and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_meta"] = not bookinfo.ignore_meta and 'Y' or false,
                })
                UIManager:close(self.collfile_dialog)
                self:updateItems(1, true)
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow a new extraction (multiple interruptions, book replaced)...
            text = _("Refresh cached book information"),
            callback = function()
                -- Wipe the cache
                self:updateCache(file)
                BookInfoManager:deleteBookInfo(file)
                UIManager:close(self.collfile_dialog)
                self:updateItems(1, true)
            end,
        },
    })

    -- Create the new ButtonDialog, and let UIManager show it
    self.collfile_dialog = ButtonDialog:new{
        title = orig_title,
        title_align = orig_title_align,
        buttons = orig_buttons,
    }
    UIManager:show(self.collfile_dialog)
    return true
end

function CoverMenu:onCloseWidget()
    -- Due to close callback in FileManagerHistory:onShowHist, we may be called
    -- multiple times (witnessed that with print(debug.traceback())
    -- So, avoid doing what follows twice
    if self._covermenu_onclose_done then
        return
    end
    self._covermenu_onclose_done = true

    -- Stop background job if any (so that full cpu is available to reader)
    logger.dbg("CoverMenu:onCloseWidget: terminating jobs if needed")
    BookInfoManager:terminateBackgroundJobs()
    BookInfoManager:closeDbConnection() -- sqlite connection no more needed
    BookInfoManager:cleanUp() -- clean temporary resources

    -- Cancel any still scheduled update
    if self.items_update_action then
        logger.dbg("CoverMenu:onCloseWidget: unscheduling items_update_action")
        UIManager:unschedule(self.items_update_action)
        self.items_update_action = nil
    end

    -- Propagate a call to free() to all our sub-widgets, to release memory used by their _bb
    self.item_group:free()

    -- Clean any short term cache (used by ListMenu to cache some Doc Settings info)
    self.cover_info_cache = nil

    -- Force garbage collecting when leaving too
    -- (delay it a bit so this pause is less noticeable)
    UIManager:scheduleIn(0.2, function()
        collectgarbage()
        collectgarbage()
    end)
    nb_drawings_since_last_collectgarbage = 0

    -- Call the object's original onCloseWidget (i.e., Menu's, as none our our expected subclasses currently implement it)
    Menu.onCloseWidget(self)
end

function CoverMenu:tapPlus()
    -- Call original function: it will create a ButtonDialog
    -- and store it as self.file_dialog, and UIManager:show() it.
    CoverMenu._FileManager_tapPlus_orig(self)
    if self.file_dialog.select_mode then return end -- do not change select menu

    -- Remember some of this original ButtonDialog properties
    local orig_title = self.file_dialog.title
    local orig_title_align = self.file_dialog.title_align
    local orig_buttons = self.file_dialog.buttons
    -- Close original ButtonDialog (it has not yet been painted
    -- on screen, so we won't see it)
    UIManager:close(self.file_dialog)
    UIManager:clearRenderStack()

    -- Add a new button to original buttons set
    table.insert(orig_buttons, {}) -- separator
    table.insert(orig_buttons, {
        {
            text = _("Extract and cache book information"),
            callback = function()
                UIManager:close(self.file_dialog)
                local Trapper = require("ui/trapper")
                Trapper:wrap(function()
                    BookInfoManager:extractBooksInDirectory(current_path, current_cover_specs)
                end)
            end,
        },
    })

    -- Create the new ButtonDialog, and let UIManager show it
    self.file_dialog = ButtonDialog:new{
        title = orig_title,
        title_align = orig_title_align,
        buttons = orig_buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

return CoverMenu
