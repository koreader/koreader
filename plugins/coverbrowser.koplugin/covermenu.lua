local BD = require("ui/bidi")
local DocumentRegistry = require("document/documentregistry")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local util = require("util")

local BookInfoManager = require("bookinfomanager")

-- This is a kind of "base class" for both MosaicMenu and ListMenu.
-- It implements the common code shared by these, mostly the non-UI
-- work : the updating of items and the management of backgrouns jobs.
--
-- Here are defined the common overriden methods of Menu:
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

function CoverMenu:updateItems(select_number)
    -- As done in Menu:updateItems()
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:clear()
    -- NOTE: Our various _recalculateDimen overloads appear to have a stronger dependency
    --       on the rest of the widget elements being properly laid-out,
    --       so we have to run it *first*, unlike in Menu.
    --       Otherwise, various layout issues arise (e.g., MosaicMenu's page_info is misaligned).
    self:_recalculateDimen()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.vertical_span:clear()
    self.content_group:resetLayout()
    -- default to select the first item
    if not select_number then
        select_number = 1
    end

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
        -- (delay it a bit so this pause is less noticable)
        UIManager:scheduleIn(0.2, function()
            collectgarbage()
            collectgarbage()
        end)
        nb_drawings_since_last_collectgarbage = 0
    end

    -- Specific UI building implementation (defined in some other module)
    self._has_cover_images = false
    self:_updateItemsBuildUI()

    -- Set the local variables with the things we know
    -- These are used only by extractBooksInDirectory(), which should
    -- use the cover_specs set for FileBrowser, and not those from History.
    -- Hopefully, we get self.path=nil when called fro History
    if self.path then
        current_path = self.path
        current_cover_specs = self.cover_specs
    end

    -- As done in Menu:updateItems()
    self:updatePageInfo(select_number)

    if self.show_path then
        self.path_text:setText(BD.directory(self.path))
    end
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

    -- (We may not need to do the following if we extend onFileHold
    -- code in filemanager.lua to check for existence and call a
    -- method: self:getAdditionalButtons() to add our buttons
    -- to its own set.)

    -- We want to add some buttons to the onFileHold popup. This function
    -- is dynamically created by FileManager:init(), and we don't want
    -- to override this... So, here, when we see the onFileHold function,
    -- we replace it by ours.
    -- (FileManager may replace file_chooser.onFileHold after we've been called once, so we need
    -- to replace it again if it is not ours)
    if not self.onFileHold_ours -- never replaced
            or self.onFileHold ~= self.onFileHold_ours then -- it is no more ours
        -- We need to do it at nextTick, once FileManager has instantiated
        -- its FileChooser completely
        UIManager:nextTick(function()
            -- Store original function, so we can call it
            self.onFileHold_orig = self.onFileHold

            -- Replace it with ours
            -- This causes luacheck warning: "shadowing upvalue argument 'self' on line 34".
            -- Ignoring it (as done in filemanager.lua for the same onFileHold)
            self.onFileHold = function(self, file) -- luacheck: ignore
                -- Call original function: it will create a ButtonDialogTitle
                -- and store it as self.file_dialog, and UIManager:show() it.
                self.onFileHold_orig(self, file)

                local bookinfo = BookInfoManager:getBookInfo(file)
                if not bookinfo or bookinfo._is_directory then
                    -- If no bookinfo (yet) about this file, or it's a directory, let the original dialog be
                    return true
                end

                -- Remember some of this original ButtonDialogTitle properties
                local orig_title = self.file_dialog.title
                local orig_title_align = self.file_dialog.title_align
                local orig_buttons = self.file_dialog.buttons
                -- Close original ButtonDialogTitle (it has not yet been painted
                -- on screen, so we won't see it)
                UIManager:close(self.file_dialog)
                -- And clear the rendering stack to avoid inheriting its dirty/refresh queue
                UIManager:clearRenderStack()

                -- Replace Book information callback to use directly our bookinfo
                orig_buttons[4][2].callback = function()
                    FileManagerBookInfo:show(file, bookinfo)
                    UIManager:close(self.file_dialog)
                end

                -- Fudge the "Purge .sdr" button ([1][3]) callback to also trash the cover_info_cache
                local orig_purge_callback = orig_buttons[1][3].callback
                orig_buttons[1][3].callback = function()
                    -- Wipe the cache
                    if self.cover_info_cache and self.cover_info_cache[file] then
                        self.cover_info_cache[file] = nil
                    end
                    -- And then purge the sidecar folder as expected
                    orig_purge_callback()
                end

                -- Add some new buttons to original buttons set
                table.insert(orig_buttons[5], 1,
                    { -- Mark the book as read/unread
                        text_func = function()
                            -- If the book has a cache entry, it means it has a sidecar file, and it *may* have the info we need.
                            local status
                            if self.cover_info_cache and self.cover_info_cache[file] then
                                local _, _, c_status = unpack(self.cover_info_cache[file])
                                status = c_status
                            end
                            -- NOTE: status may still be nil if the BookStatus widget was never opened in this book.
                            --       For our purposes, we assume this means reading or on hold, which is just fine.
                            -- NOTE: This also means we assume "on hold" means reading, meaning it'll be flipped to "finished",
                            --       which I'm personally okay with, too.
                            --       c.f., BookStatusWidget:generateSwitchGroup for the three possible constant values.
                            return status == "complete" and _("Mark as reading") or _("Mark as read")
                        end,
                        enabled = true,
                        callback = function()
                            local status
                            if self.cover_info_cache and self.cover_info_cache[file] then
                                local c_pages, c_percent_finished, c_status = unpack(self.cover_info_cache[file])
                                status = c_status == "complete" and "reading" or "complete"
                                -- Update the cache, even if it had a nil status before
                                self.cover_info_cache[file] = {c_pages, c_percent_finished, status}
                            else
                                -- We assumed earlier an empty status meant "reading", so, flip that to "complete"
                                status = "complete"
                            end

                            -- In case the book doesn't have a sidecar file, this'll create it
                            local docinfo = DocSettings:open(file)
                            if docinfo.data.summary and docinfo.data.summary.status then
                                -- Book already had the full BookStatus table in its sidecar, easy peasy!
                                docinfo.data.summary.status = status
                            else
                                -- No BookStatus table, create a minimal one...
                                if docinfo.data.summary then
                                    -- Err, a summary table with no status entry? Should never happen...
                                    local summary = { status = status }
                                    -- Append the status entry to the existing summary...
                                    util.tableMerge(docinfo.data.summary, summary)
                                else
                                    -- No summary table at all, create a minimal one
                                    local summary = { status = status }
                                    docinfo:saveSetting("summary", summary)
                                end
                            end
                            docinfo:flush()

                            UIManager:close(self.file_dialog)
                            self:updateItems()
                        end,
                    }
                )

                -- Keep on adding new buttons
                table.insert(orig_buttons, {
                    { -- Allow user to view real size cover in ImageViewer
                        text = _("View full size cover"),
                        enabled = bookinfo.has_cover and true or false,
                        callback = function()
                            local document = DocumentRegistry:openDocument(file)
                            if document then
                                if document.loadDocument then -- needed for crengine
                                    document:loadDocument(false) -- load only metadata
                                end
                                local cover_bb = document:getCoverPageImage()
                                if cover_bb then
                                    local imgviewer = ImageViewer:new{
                                        image = cover_bb,
                                        with_title_bar = false,
                                        fullscreen = true,
                                    }
                                    UIManager:show(imgviewer)
                                else
                                    UIManager:show(InfoMessage:new{
                                        text = _("No cover image available."),
                                    })
                                end
                                UIManager:close(self.file_dialog)
                                document:close()
                            end
                        end,
                    },
                    { -- Allow user to directly view description in TextViewer
                        text = _("Book description"),
                        enabled = bookinfo.description and true or false,
                        callback = function()
                            local description = util.htmlToPlainTextIfHtml(bookinfo.description)
                            local textviewer = TextViewer:new{
                                title = _("Description:"),
                                text = description,
                            }
                            UIManager:close(self.file_dialog)
                            UIManager:show(textviewer)
                        end,
                    },
                })
                table.insert(orig_buttons, {
                    { -- Allow user to ignore some offending cover image
                        text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
                        enabled = bookinfo.has_cover and true or false,
                        callback = function()
                            BookInfoManager:setBookInfoProperties(file, {
                                ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                            })
                            UIManager:close(self.file_dialog)
                            self:updateItems()
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
                            self:updateItems()
                        end,
                    },
                })
                table.insert(orig_buttons, {
                    { -- Allow a new extraction (multiple interruptions, book replaced)...
                        text = _("Refresh cached book information"),
                        enabled = bookinfo and true or false,
                        callback = function()
                            -- Wipe the cache
                            if self.cover_info_cache and self.cover_info_cache[file] then
                                self.cover_info_cache[file] = nil
                            end
                            BookInfoManager:deleteBookInfo(file)
                            UIManager:close(self.file_dialog)
                            self:updateItems()
                        end,
                    },
                })

                -- Create the new ButtonDialogTitle, and let UIManager show it
                local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
                self.file_dialog = ButtonDialogTitle:new{
                    title = orig_title,
                    title_align = orig_title_align,
                    buttons = orig_buttons,
                }
                UIManager:show(self.file_dialog)
                return true
            end

            -- Remember our function
            self.onFileHold_ours = self.onFileHold
        end)
    end
end

-- Similar to onFileHold setup just above, but for History,
-- which is plugged in main.lua _FileManagerHistory_updateItemTable()
function CoverMenu:onHistoryMenuHold(item)
    -- Call original function: it will create a ButtonDialog
    -- and store it as self.histfile_dialog, and UIManager:show() it.
    self.onMenuHold_orig(self, item)
    local file = item.file

    local bookinfo = BookInfoManager:getBookInfo(file)
    if not bookinfo then
        -- If no bookinfo (yet) about this file, let the original dialog be
        return true
    end

    -- Remember some of this original ButtonDialogTitle properties
    local orig_title = self.histfile_dialog.title
    local orig_title_align = self.histfile_dialog.title_align
    local orig_buttons = self.histfile_dialog.buttons
    -- Close original ButtonDialog (it has not yet been painted
    -- on screen, so we won't see it)
    UIManager:close(self.histfile_dialog)
    UIManager:clearRenderStack()

    -- Replace Book information callback to use directly our bookinfo
    orig_buttons[2][2].callback = function()
        FileManagerBookInfo:show(file, bookinfo)
        UIManager:close(self.histfile_dialog)
    end

    -- Remove last button ("Clear history of deleted files"), we'll
    -- add it back after our buttons
    local last_button = table.remove(orig_buttons)

    -- Add some new buttons to original buttons set
    table.insert(orig_buttons, {
        { -- Allow user to view real size cover in ImageViewer
            text = _("View full size cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                local document = DocumentRegistry:openDocument(file)
                if document then
                    if document.loadDocument then -- needed for crengine
                        document:loadDocument(false) -- load only metadata
                    end
                    local cover_bb = document:getCoverPageImage()
                    if cover_bb then
                        local imgviewer = ImageViewer:new{
                            image = cover_bb,
                            with_title_bar = false,
                            fullscreen = true,
                        }
                        UIManager:show(imgviewer)
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("No cover image available."),
                        })
                    end
                    UIManager:close(self.histfile_dialog)
                    document:close()
                end
            end,
        },
        { -- Allow user to directly view description in TextViewer
            text = _("Book description"),
            enabled = bookinfo.description and true or false,
            callback = function()
                local description = util.htmlToPlainTextIfHtml(bookinfo.description)
                local textviewer = TextViewer:new{
                    title = _("Description:"),
                    text = description,
                }
                UIManager:close(self.histfile_dialog)
                UIManager:show(textviewer)
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow user to ignore some offending cover image
            text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                })
                UIManager:close(self.histfile_dialog)
                self:updateItems()
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
                self:updateItems()
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow a new extraction (multiple interruptions, book replaced)...
            text = _("Refresh cached book information"),
            enabled = bookinfo and true or false,
            callback = function()
                BookInfoManager:deleteBookInfo(file)
                UIManager:close(self.histfile_dialog)
                self:updateItems()
            end,
        },
    })
    table.insert(orig_buttons, {}) -- separator
    -- Put back "Clear history of deleted files"
    table.insert(orig_buttons, last_button)

    -- Create the new ButtonDialog, and let UIManager show it
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    self.histfile_dialog = ButtonDialogTitle:new{
        title = orig_title,
        title_align = orig_title_align,
        buttons = orig_buttons,
    }
    UIManager:show(self.histfile_dialog)
    return true
end

-- Similar to onFileHold setup just above, but for Collections,
-- which is plugged in main.lua _FileManagerCollections_updateItemTable()
function CoverMenu:onCollectionsMenuHold(item)
    -- Call original function: it will create a ButtonDialog
    -- and store it as self.collfile_dialog, and UIManager:show() it.
    self.onMenuHold_orig(self, item)
    local file = item.file

    local bookinfo = BookInfoManager:getBookInfo(file)
    if not bookinfo then
        -- If no bookinfo (yet) about this file, let the original dialog be
        return true
    end

    -- Remember some of this original ButtonDialogTitle properties
    local orig_title = self.collfile_dialog.title
    local orig_title_align = self.collfile_dialog.title_align
    local orig_buttons = self.collfile_dialog.buttons
    -- Close original ButtonDialog (it has not yet been painted
    -- on screen, so we won't see it)
    UIManager:close(self.collfile_dialog)
    UIManager:clearRenderStack()

    -- Replace Book information callback to use directly our bookinfo
    orig_buttons[2][1].callback = function()
        FileManagerBookInfo:show(file, bookinfo)
        UIManager:close(self.collfile_dialog)
    end

    -- Add some new buttons to original buttons set
    table.insert(orig_buttons, {
        { -- Allow user to view real size cover in ImageViewer
            text = _("View full size cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                local document = DocumentRegistry:openDocument(file)
                if document then
                    if document.loadDocument then -- needed for crengine
                        document:loadDocument(false) -- load only metadata
                    end
                    local cover_bb = document:getCoverPageImage()
                    if cover_bb then
                        local imgviewer = ImageViewer:new{
                            image = cover_bb,
                            with_title_bar = false,
                            fullscreen = true,
                        }
                        UIManager:show(imgviewer)
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("No cover image available."),
                        })
                    end
                    UIManager:close(self.collfile_dialog)
                    document:close()
                end
            end,
        },
        { -- Allow user to directly view description in TextViewer
            text = _("Book description"),
            enabled = bookinfo.description and true or false,
            callback = function()
                local description = util.htmlToPlainTextIfHtml(bookinfo.description)
                local textviewer = TextViewer:new{
                    title = _("Description:"),
                    text = description,
                }
                UIManager:close(self.collfile_dialog)
                UIManager:show(textviewer)
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow user to ignore some offending cover image
            text = bookinfo.ignore_cover and _("Unignore cover") or _("Ignore cover"),
            enabled = bookinfo.has_cover and true or false,
            callback = function()
                BookInfoManager:setBookInfoProperties(file, {
                    ["ignore_cover"] = not bookinfo.ignore_cover and 'Y' or false,
                })
                UIManager:close(self.collfile_dialog)
                self:updateItems()
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
                self:updateItems()
            end,
        },
    })
    table.insert(orig_buttons, {
        { -- Allow a new extraction (multiple interruptions, book replaced)...
            text = _("Refresh cached book information"),
            enabled = bookinfo and true or false,
            callback = function()
                BookInfoManager:deleteBookInfo(file)
                UIManager:close(self.collfile_dialog)
                self:updateItems()
            end,
        },
    })
    -- Create the new ButtonDialog, and let UIManager show it
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    self.collfile_dialog = ButtonDialogTitle:new{
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

    -- Clean any short term cache (used by ListMenu to cache some DocSettings info)
    self.cover_info_cache = nil

    -- Force garbage collecting when leaving too
    -- (delay it a bit so this pause is less noticable)
    UIManager:scheduleIn(0.2, function()
        collectgarbage()
        collectgarbage()
    end)
    nb_drawings_since_last_collectgarbage = 0

    -- Call original Menu:onCloseWidget (no subclass seems to override it)
    Menu.onCloseWidget(self)
end

function CoverMenu:tapPlus()
    -- Call original function: it will create a ButtonDialogTitle
    -- and store it as self.file_dialog, and UIManager:show() it.
    CoverMenu._FileManager_tapPlus_orig(self)

    -- Remember some of this original ButtonDialogTitle properties
    local orig_title = self.file_dialog.title
    local orig_title_align = self.file_dialog.title_align
    local orig_buttons = self.file_dialog.buttons
    -- Close original ButtonDialogTitle (it has not yet been painted
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

    -- Create the new ButtonDialogTitle, and let UIManager show it
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    self.file_dialog = ButtonDialogTitle:new{
        title = orig_title,
        title_align = orig_title_align,
        buttons = orig_buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

return CoverMenu
