local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local ImageViewer = require("ui/widget/imageviewer")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")

local BookInfoManager = require("bookinfomanager")

-- This is a kind of "base class" for both MosaicMenu and ListMenu.
-- It implements the common code shared by these, mostly the non-UI
-- work : the updating of items and the management of backgrouns jobs.
--
-- Here are defined the common overriden methods of Menu:
--    :updateItems(select_number)
--    :onCloseWidget()
--    :onSwipe(arg, ges_ev)
--
-- MosaicMenu or ListMenu should implement specific UI methods:
--    :_recalculateDimen()
--    :_updateItemsBuildUI()
-- This last method is called in the middle of :updateItems() , and
-- should fill self.item_group with some specific UI layout. It may add
-- not found item to self.items_to_update for us to update() them
-- regularly.

-- Simple holder of methods that will replace those
-- in the real Menu class or instance
local CoverMenu = {}

function CoverMenu:updateItems(select_number)
    -- As done in Menu:updateItems()
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for focusmanager
    self.layout = {}
    self.item_group:free() -- avoid memory leaks by calling free() on all our sub-widgets
    self.item_group:clear()
    -- strange, best here if resetLayout() are done after _recalculateDimen(),
    -- unlike what is done in menu.lua
    self:_recalculateDimen()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
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
    collectgarbage()
    collectgarbage()

    -- Specific UI building implementation (defined in some other module)
    self:_updateItemsBuildUI()

    -- As done in Menu:updateItems()
    if self.item_group[1] then
        if not Device:isTouchDevice() then
            -- only draw underline for nontouch device
            -- reset focus manager accordingly
            self.selected = { x = 1, y = select_number }
            -- set focus to requested menu item
            self.item_group[select_number]:onFocus()
            -- This will not work with our MosaicMenu, as a MosaicMenuItem is
            -- not a direct child of item_group (which contains VerticalSpans
            -- and HorizontalGroup...)
        end
        -- update page information
        self.page_info_text:setText(util.template(_("page %1 of %2"), self.page, self.page_num))
        self.page_info_left_chev:showHide(self.page_num > 1)
        self.page_info_right_chev:showHide(self.page_num > 1)
        self.page_info_first_chev:showHide(self.page_num > 2)
        self.page_info_last_chev:showHide(self.page_num > 2)
        self.page_return_arrow:showHide(self.onReturn ~= nil)

        self.page_info_left_chev:enableDisable(self.page > 1)
        self.page_info_right_chev:enableDisable(self.page < self.page_num)
        self.page_info_first_chev:enableDisable(self.page > 1)
        self.page_info_last_chev:enableDisable(self.page < self.page_num)
        self.page_return_arrow:enableDisable(#self.paths > 0)
    else
        self.page_info_text:setText(_("No choices available"))
    end
    UIManager:setDirty("all", function()
        local refresh_dimen =
            old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
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
                local InfoMessage = require("ui/widget/infomessage")
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
                    local refreshfunc = function()
                        if item.refresh_dimen then
                            -- MosaicMenuItem may exceed its own dimen in its paintTo
                            -- with its "description" hint
                            return "ui", item.refresh_dimen
                        else
                            return "ui", item[1].dimen
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
                if not bookinfo then
                    -- If no bookinfo (yet) about this file, let the original dialog be
                    return true
                end

                -- Remember some of this original ButtonDialogTitle properties
                local orig_title = self.file_dialog.title
                local orig_title_align = self.file_dialog.title_align
                local orig_buttons = self.file_dialog.buttons
                -- Close original ButtonDialogTitle (it has not yet been painted
                -- on screen, so we won't see it)
                UIManager:close(self.file_dialog)

                -- Replace Book information callback to use directly our bookinfo
                orig_buttons[4][2].callback = function()
                    FileManagerBookInfo:show(file, bookinfo)
                    UIManager:close(self.file_dialog)
                end

                -- Add some new buttons to original buttons set
                table.insert(orig_buttons, {
                    { -- Allow user to view real size cover in ImageViewer
                        text = _("View full size cover"),
                        enabled = bookinfo.has_cover and true or false,
                        callback = function()
                            local document = DocumentRegistry:openDocument(file)
                            if document then
                                local cover_bb = document:getCoverPageImage()
                                local imgviewer = ImageViewer:new{
                                    image = cover_bb,
                                    with_title_bar = false,
                                    fullscreen = true,
                                }
                                UIManager:show(imgviewer)
                                UIManager:close(self.file_dialog)
                                DocumentRegistry:closeDocument(file)
                            end
                        end,
                    },
                    { -- Allow user to directly view description in TextViewer
                        text = bookinfo.description and _("View book description") or _("No book description"),
                        enabled = bookinfo.description and true or false,
                        callback = function()
                            local description = require("util").htmlToPlainTextIfHtml(bookinfo.description)
                            local textviewer = TextViewer:new{
                                title = bookinfo.title,
                                text = description,
                            }
                            UIManager:show(textviewer)
                            UIManager:close(self.file_dialog)
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
                    local cover_bb = document:getCoverPageImage()
                    local imgviewer = ImageViewer:new{
                        image = cover_bb,
                        with_title_bar = false,
                        fullscreen = true,
                    }
                    UIManager:show(imgviewer)
                    UIManager:close(self.histfile_dialog)
                    DocumentRegistry:closeDocument(file)
                end
            end,
        },
        { -- Allow user to directly view description in TextViewer
            text = bookinfo.description and _("View book description") or _("No book description"),
            enabled = bookinfo.description and true or false,
            callback = function()
                local description = require("util").htmlToPlainTextIfHtml(bookinfo.description)
                local textviewer = TextViewer:new{
                    title = bookinfo.title,
                    text = description,
                }
                UIManager:show(textviewer)
                UIManager:close(self.histfile_dialog)
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

function CoverMenu:onCloseWidget()
    -- Due to close callback in FileManagerHistory:onShowHist, we may be called
    -- multiple times (witnessed that with print(debug.traceback())

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
    collectgarbage()
    collectgarbage()

    -- Call original Menu:onCloseWidget (no subclass seems to override it)
    Menu.onCloseWidget(self)
end

-- Overriden just to allow full refresh (useful with images)
function CoverMenu:onSwipe(arg, ges_ev)
    if ges_ev.direction == "west" then
        self:onNextPage()
    elseif ges_ev.direction == "east" then
        self:onPrevPage()
    elseif ges_ev.direction ~= "north" and ges_ev.direction ~= "south" then
        -- but not if north/south, and we're triggering menu
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
    end
end

return CoverMenu
