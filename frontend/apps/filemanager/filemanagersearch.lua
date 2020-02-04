local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local FFIUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local calibre = "metadata.calibre"
local koreaderfile = "temp/metadata.koreader"

local Search = InputContainer:new{
    search_dialog = nil,
    title = 1,
    authors = 2,
    authors2 = 3,
    path = 4,
    series = 5,
    series_index = 6,
    tags = 7,
    tags2 = 8,
    tags3 = 9,
    count = 0,
    data = {},
    results = {},
    browse_tags = {},
    browse_series = {},
    error = nil,
    use_previous_search_results = false,
    lastsearch = nil,
    use_own_metadata_file = false,
    metafile_1 = nil,
    metafile_2 = nil,
}

local function findcalibre(root)
    local t = nil
    -- protect lfs.dir which will raise error on no-permission directory
    local ok, iter, dir_obj = pcall(lfs.dir, root)
    if ok then
        for entity in iter, dir_obj do
            if t then
                break
            else
                if entity ~= "." and entity ~= ".." then
                    local fullPath=root .. "/" .. entity
                    local mode = lfs.attributes(fullPath, "mode")
                    if mode == "file" then
                        if entity == calibre or entity == "." .. calibre then
                            t = root .. "/" .. entity
                            -- If we got so far, SEARCH_LIBRARY_PATH is either empty or bogus, so, re-set it,
                            -- so that we actually can convert a book's relative path to its absolute path.
                            -- NOTE: No-one should actually rely on that, as the value is *NEVER* saved to the defaults.
                            --       (SetDefaults can only do that with values modified from within its own advanced menu).
                            _G['SEARCH_LIBRARY_PATH'] = root .. "/"
                            logger.info("FMSearch: Found a SEARCH_LIBRARY_PATH @", SEARCH_LIBRARY_PATH)
                        end
                    elseif mode == "directory" then
                        t = findcalibre(fullPath)
                    end
                end
            end
        end
    end
    return t
end

function Search:getCalibre()
    -- check if we find the calibre file
    -- check 1st file
    if SEARCH_LIBRARY_PATH == nil then
        logger.dbg("search Calibre database")
        self.metafile_1 = findcalibre("/mnt")
        if not self.metafile_1 then
            self.error = _("The SEARCH_LIBRARY_PATH variable must be defined in 'persistent.defaults.lua' in order to use the calibre file search functionality.")
        end
    else
        if string.sub(SEARCH_LIBRARY_PATH, string.len(SEARCH_LIBRARY_PATH)) ~= "/" then
            _G['SEARCH_LIBRARY_PATH'] = SEARCH_LIBRARY_PATH .. "/"
        end
        if io.open(SEARCH_LIBRARY_PATH .. calibre, "r") == nil then
            if io.open(SEARCH_LIBRARY_PATH .. "." .. calibre, "r") == nil then
                self.error = SEARCH_LIBRARY_PATH .. calibre .. " " .. _("not found.")
                logger.err(self.error)
            else
                self.metafile_1 = SEARCH_LIBRARY_PATH .. "." .. calibre
            end
        else
            self.metafile_1 = SEARCH_LIBRARY_PATH .. calibre
        end

        if not (SEARCH_AUTHORS or SEARCH_TITLE or SEARCH_PATH or SEARCH_SERIES or SEARCH_TAGS) then
            self.metafile_1 = nil
            UIManager:show(InfoMessage:new{text = _("You must specify at least one field to search at! (SEARCH_XXX = true in defaults.lua)")})
        elseif self.metafile_1 == nil then
            self.metafile_1 = findcalibre("/mnt")
        end
    end
    -- check 2nd file
    local dummy

    if string.sub(SEARCH_LIBRARY_PATH2, string.len(SEARCH_LIBRARY_PATH2)) ~= "/" then
        _G['SEARCH_LIBRARY_PATH2'] = SEARCH_LIBRARY_PATH2 .. "/"
    end
    if io.open(SEARCH_LIBRARY_PATH2 .. calibre, "r") == nil then
        if io.open(SEARCH_LIBRARY_PATH2 .. "." .. calibre, "r") ~= nil then
            dummy = SEARCH_LIBRARY_PATH2 .. "." .. calibre
        end
    else
        dummy = SEARCH_LIBRARY_PATH2 .. calibre
    end
    if dummy and dummy ~= self.metafile_1 then
        self.metafile_2 = dummy
    else
        self.metafile_2 = nil
    end

    -- check if they are newer than our own file
    self.use_own_metadata_file = false
    if self.metafile_1 then
        pcall(lfs.mkdir("temp"))
        if io.open(koreaderfile, "r") then
            if lfs.attributes(koreaderfile, "modification") > lfs.attributes(self.metafile_1, "modification") then
                if self.metafile_2 then
                    if lfs.attributes(koreaderfile, "modification") > lfs.attributes(self.metafile_2, "modification") then
                        self.use_own_metadata_file = true
                        logger.info("FMSearch: Using our own simplified metadata file as it's newer than", self.metafile_2)
                    end
                else
                    self.use_own_metadata_file = true
                    logger.info("FMSearch: Using our own simplified metadata file as it's newer than", self.metafile_1)
                end
            end
        end
    end
end

function Search:ShowSearch()
    if self.metafile_1 ~= nil then
        local dummy = self.search_value
        self.search_dialog = InputDialog:new{
            title = _("Search books"),
            input = self.search_value,
            buttons = {
                {
                    {
                        text = _("Browse series"),
                        enabled = true,
                        callback = function()
                            self.search_value = self.search_dialog:getInputText()
                            if self.search_value == dummy and self.lastsearch == "series" then
                                 self.use_previous_search_results = true
                            else
                                 self.use_previous_search_results = false
                            end
                            self.lastsearch = "series"
                            self:close()
                        end,
                    },
                    {
                        text = _("Browse tags"),
                        enabled = true,
                        callback = function()
                            self.search_value = self.search_dialog:getInputText()
                            if self.search_value == dummy and self.lastsearch == "tags" then
                                 self.use_previous_search_results = true
                            else
                                 self.use_previous_search_results = false
                            end
                            self.lastsearch = "tags"
                            self:close()
                        end,
                    },
                },
                {
                    {
                        text = _("Cancel"),
                        enabled = true,
                        callback = function()
                            self.search_dialog:onClose()
                            UIManager:close(self.search_dialog)
                        end,
                    },
                    {
                        -- @translators Search for books in calibre Library, via on-device metadata (as setup by Calibre's 'Send To Device').
                        text = _("Find books"),
                        enabled = true,
                        callback = function()
                            self.search_value = self.search_dialog:getInputText()
                            if self.search_value == dummy and self.lastsearch == "find" then
                                 self.use_previous_search_results = true
                            else
                                 self.use_previous_search_results = false
                            end
                            self.lastsearch = "find"
                            self:close()
                        end,
                    },
                },
            },
            width = Screen:getWidth() * 0.8,
            height = Screen:getHeight() * 0.2,
        }
        UIManager:show(self.search_dialog)
        self.search_dialog:onShowKeyboard()
    else
        if self.error then
            UIManager:show(InfoMessage:new{
                text = ("%s\n%s"):format(
                    self.error,
                    _("Unable to find a calibre metadata file.")),
            })
        end
    end

end

function Search:init()
    self.error = nil
    self.data = {}
    self.results = {}
end

function Search:close()
    if self.search_value then
        self.search_dialog:onClose()
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 or self.lastsearch ~= "find" then
            self:find(self.lastsearch)
        end
    end
end

function Search:find(option)
    local f
    local line
    local i = 1
    local upsearch
    local firstrun

    -- removes leading and closing characters and converts hex-unicodes
    local ReplaceHexChars = function(s, n, j)
        local l=string.len(s)

        if string.sub(s, l, l) == "\"" then
            s=string.sub(s, n, string.len(s)-1)
        else
            s=string.sub(s, n, string.len(s)-j)
        end

        s=string.gsub(s, "\\u([a-f0-9][a-f0-9][a-f0-9][a-f0-9])", function(w) return util.unicodeCodepointToUtf8(tonumber(w, 16)) end)

        return s
    end

    -- ready entries with multiple lines from calibre
    local ReadMultipleLines = function(s)
        self.data[i][s] = ""
        if s == self.authors then
            self.data[i][self.authors2] = ""
        elseif s == self.tags then
            self.data[i][self.tags2] = ""
            self.data[i][self.tags3] = ""
        end
        while line ~= "    ], " and line ~= "    ]" do
            line = f:read()
            if line ~= "    ], " and line ~= "    ]" then
                self.data[i][s] = self.data[i][s] .. "," .. ReplaceHexChars(line, 8, 3)
                if s == self.authors then
                    self.data[i][self.authors2] = self.data[i][self.authors2] .. " & " .. ReplaceHexChars(line, 8, 3)
                elseif s == self.tags then
                    local tags_line = ReplaceHexChars(line, 8, 3)
                    self.data[i][self.tags2] = self.data[i][self.tags2] .. " & " .. tags_line
                    self.data[i][self.tags3] = self.data[i][self.tags3] .. "\t" .. tags_line
                    self.browse_tags[tags_line] = (self.browse_tags[tags_line] or 0) + 1
                end
            end
        end
        self.data[i][s] = string.sub(self.data[i][s], 2)
        if s == self.authors then
            self.data[i][self.authors2] = string.sub(self.data[i][self.authors2], 4)
        elseif s == self.tags then
            self.data[i][self.tags2] = string.sub(self.data[i][self.tags2], 4)
            self.data[i][self.tags3] = self.data[i][self.tags3] .. "\t"
        end
    end

    if not self.use_previous_search_results then
        self.results = {}
        self.data = {}
        self.browse_series = {}
        self.browse_tags = {}

        if SEARCH_CASESENSITIVE then
            upsearch = self.search_value or ""
        else
            upsearch = string.upper(self.search_value or "")
        end

        firstrun = true

        self.data[i] = {"-","-","-","-","-","-","-","-","-"}

        if self.use_own_metadata_file then
            local g = io.open(koreaderfile, "r")
            line = g:read()
            if line ~= "#metadata.Koreader Version 1.1" and line ~= "#metadata.koreader Version 1.1" then
                self.use_own_metadata_file = false
                g:close()
            else
                line = g:read()
            end
            if self.use_own_metadata_file then
                while line do

                    for j = 1,9 do
                        self.data[i][j] = line or ""
                        line = g:read()
                    end

                    local search_content = ""
                    if option == "find" and SEARCH_AUTHORS then
                        search_content = search_content .. self.data[i][self.authors] .. "\n"
                    end
                    if option == "find" and SEARCH_TITLE then
                        search_content = search_content .. self.data[i][self.title] .. "\n"
                    end
                    if option == "find" and SEARCH_PATH then
                        search_content = search_content .. self.data[i][self.path] .. "\n"
                    end
                    if (option == "series" or SEARCH_SERIES) and self.data[i][self.series] ~= "-" then
                        search_content = search_content .. self.data[i][self.series] .. "\n"
                        self.browse_series[self.data[i][self.series]] = (self.browse_series[self.data[i][self.series]] or 0) + 1
                    end
                    if option == "tags" or SEARCH_TAGS then
                        search_content = search_content .. self.data[i][self.tags] .. "\n"
                    end
                    if not SEARCH_CASESENSITIVE then search_content = string.upper(search_content) end

                    for j in string.gmatch(self.data[i][self.tags3],"\t[^\t]+") do
                        if j~="\t" then
                            self.browse_tags[string.sub(j, 2)] = (self.browse_tags[string.sub(j, 2)] or 0) + 1
                        end
                    end
                    -- NOTE: This skips kePubs downloaded by nickel, because they don't have a file extension,
                    --       they're stored as .kobo/kepub/<UUID>
                    if DocumentRegistry:hasProvider(self.data[i][self.path]) then
                        if upsearch ~= "" then
                            if string.find(search_content, upsearch, nil, true) then
                                i = i + 1
                            end
                        else
                            if option == "series" then
                                if self.browse_series[self.data[i][self.series]] then
                                    i = i + 1
                                end
                            elseif option == "tags" then
                                local found = false
                                for j in string.gmatch(self.data[i][self.tags3],"\t[^\t]+") do
                                    if j~="\t" and self.browse_tags[string.sub(j, 2)] then
                                        found = true
                                    end
                                end
                                if found then
                                    i = i + 1
                                end
                            end
                        end
                    end
                    self.data[i] = {"-","-","-","-","-","-","-","-","-"}
                end
                g.close()
            end
        end
        if not self.use_own_metadata_file then
            logger.info("FMSearch: Writing our own simplified metadata file . . .")
            local g = io.open(koreaderfile, "w")
            g:write("#metadata.koreader Version 1.1\n")

            f = io.open(self.metafile_1, "r")
            line = f:read()
            while line do
                if line == "  }, " or line == "  }" then
                    -- new calibre data set

                    local search_content = ""
                    if option == "find" and SEARCH_AUTHORS then search_content = search_content .. self.data[i][self.authors] .. "\n" end
                    if option == "find" and SEARCH_TITLE then search_content = search_content .. self.data[i][self.title] .. "\n"  end
                    if option == "find" and SEARCH_PATH then search_content = search_content .. self.data[i][self.path] .. "\n"  end
                    if (option == "series" or SEARCH_SERIES) and self.data[i][self.series] ~= "-" then
                        search_content = search_content .. self.data[i][self.series] .. "\n"
                        self.browse_series[self.data[i][self.series]] = (self.browse_series[self.data[i][self.series]] or 0) + 1
                    end
                    if option == "tags" or SEARCH_TAGS then search_content = search_content .. self.data[i][self.tags] .. "\n" end
                    if not SEARCH_CASESENSITIVE then search_content = string.upper(search_content) end

                    for j = 1,9 do
                        g:write(self.data[i][j] .. "\n")
                    end

                    if upsearch ~= "" then
                        if string.find(search_content, upsearch, nil, true) then
                            i = i + 1
                        end
                    else
                        if option == "series" then
                            if self.browse_series[self.data[i][self.series]] then
                                i = i + 1
                            end
                        elseif option == "tags" then
                            local found = false
                            for j in string.gmatch(self.data[i][self.tags3], "\t[^\t]+") do
                                if j~="\t" and self.browse_tags[string.sub(j, 2)] then
                                    found = true
                                end
                            end
                            if found then
                                i = i + 1
                            end
                        end
                    end

                    self.data[i] = {"-","-","-","-","-","-","-","-","-"}

                elseif line == "    \"authors\": [" then -- AUTHORS
                    ReadMultipleLines(self.authors)
                elseif line == "    \"tags\": [" then -- TAGS
                    ReadMultipleLines(self.tags)
                elseif string.sub(line, 1, 11) == "    \"title\"" then -- TITLE
                    self.data[i][self.title] = ReplaceHexChars(line, 15, 3)
                elseif string.sub(line, 1, 11) == "    \"lpath\"" then -- LPATH
                    self.data[i][self.path] = ReplaceHexChars(line, 15, 3)
                    if firstrun then
                        self.data[i][self.path] = SEARCH_LIBRARY_PATH .. self.data[i][self.path]
                    else
                        self.data[i][self.path] = SEARCH_LIBRARY_PATH2 .. self.data[i][self.path]
                    end
                elseif string.sub(line, 1, 12) == "    \"series\"" and line ~= "    \"series\": null, " then -- SERIES
                    self.data[i][self.series] = ReplaceHexChars(line, 16, 3)
                elseif string.sub(line, 1, 18) == "    \"series_index\"" and line ~= "    \"series_index\": null, " then -- SERIES_INDEX
                    self.data[i][self.series_index] = ReplaceHexChars(line, 21, 2)
                end
                line = f:read()

                if not line and firstrun then
                    if f ~= nil then f:close() end
                    firstrun = false

                    if self.metafile_2 then
                        f = io.open(self.metafile_2, "r")
                        line = f:read()
                    end
                end
            end
            g.close()
            if lfs.attributes(koreaderfile, "modification") < lfs.attributes(self.metafile_1, "modification") then
                lfs.touch(koreaderfile,
                          lfs.attributes(self.metafile_1, "modification") + 1,
                          lfs.attributes(self.metafile_1, "modification") + 1)
            end
            if self.metafile_2 then
                if lfs.attributes(koreaderfile, "modification") < lfs.attributes(self.metafile_2, "modification") then
                    lfs.touch(koreaderfile, lfs.attributes(self.metafile_2, "modification") + 1, lfs.attributes(self.metafile_2, "modification") + 1)
                end
            end
        end
        i = i - 1
        self.count = i
    end
    if self.count > 0 then
        self.data[self.count + 1] = nil
        if option == "find" then
            self:showresults()
        else
            self:browse(option,1)
        end
    else
        UIManager:show(InfoMessage:new{
            text = T(_("No match for %1."), self.search_value)
        })
    end
end

function Search:onMenuHold(item)
    if not item.info or item.info:len() <= 0 then return end

    if item.notchecked then
        item.info = item.info .. item.path
        local f = io.open(item.path, "r")
        if f == nil then
            item.info = item.info .. "\n" .. _("File not found.")
        else
            item.info = item.info .. "\n" .. _("Size:") .. " " .. string.format("%4.1fM", lfs.attributes(item.path, "size")/1024/1024)
            f:close()
        end
        item.notchecked = false
    end
    local thumbnail
    local doc = DocumentRegistry:openDocument(item.path)
    if doc then
        if doc.loadDocument then -- CreDocument
            doc:loadDocument(false) -- load only metadata
        end
        thumbnail = doc:getCoverPageImage()
        doc:close()
    end
    local thumbwidth = math.min(240, Screen:getWidth()/3)
    UIManager:show(InfoMessage:new{
        text = item.info,
        image = thumbnail,
        image_width = thumbwidth,
        image_height = thumbwidth/2*3
    })
end

function Search:showresults()
    local ReaderUI = require("apps/reader/readerui")
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    if not self.use_previous_search_results then
        self.results = {}
        local i = 1
        while i <= self.count do
            local dummy = T(_("Title: %1"), (self.data[i][self.title] or "-")) .. "\n \n" ..
                          T(_("Author(s): %1"), (self.data[i][self.authors2] or "-")) .. "\n \n" ..
                          T(_("Tags: %1"), (self.data[i][self.tags2] or "-")) .. "\n \n" ..
                          T(_("Series: %1"), (self.data[i][self.series] or "-"))
            if self.data[i][self.series] ~= "-" then
                dummy = dummy .. " (" .. tostring(self.data[i][self.series_index]):gsub(".0$","") .. ")"
            end
            dummy = dummy .. "\n \n" .. _("Path: ")
            local book = self.data[i][self.path]
            table.insert(self.results, {
               info = dummy,
               notchecked = true,
               path = self.data[i][self.path],
               text = self.data[i][self.authors] .. ": " .. self.data[i][self.title],
               callback = function()
                   ReaderUI:showReader(book)
                   self.search_menu:onClose()
               end
            })
            i = i + 1
        end
    end
    table.sort(self.results, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:switchItemTable(_("Search Results"), self.results)
    UIManager:show(menu_container)
end

function Search:browse(option, run, chosen)
    local ReaderUI = require("apps/reader/readerui")
    local restart_me = false
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)

    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
        if restart_me then
            if string.len(self.search_value) > 0 or self.lastsearch ~= "find" then
                self.use_previous_search_results = true
                self:getCalibre(1)
                self:find(self.lastsearch)
            end
        end

    end
    local upsearch
    local dummy
    if SEARCH_CASESENSITIVE then
        upsearch = self.search_value or ""
    else
        upsearch = string.upper(self.search_value or "")
    end

    if run == 1 then
        self.results = {}
        if option == "series" then
            for v,n in FFIUtil.orderedPairs(self.browse_series) do
                dummy = v
                if not SEARCH_CASESENSITIVE then dummy = string.upper(dummy) end
                if string.find(dummy, upsearch, nil, true) then
                    table.insert(self.results, {
                        text = v .. " (" .. tostring(self.browse_series[v]) .. ")",
                        callback = function()
                            self:browse(option,2,v)
                        end
                    })
                end
           end
        else
            for v,n in FFIUtil.orderedPairs(self.browse_tags) do
                dummy = v
                if not SEARCH_CASESENSITIVE then dummy = string.upper(dummy) end
                if string.find(dummy, upsearch, nil, true) then
                    table.insert(self.results, {
                        text = v .. " (" .. tostring(self.browse_tags[v]) .. ")",
                        callback = function()
                            self:browse(option,2,v)
                        end
                    })
                end
            end
        end
    else
        restart_me = true
        self.results = {}
        local i = 1
        while i <= self.count do
            if (option == "tags" and self.data[i][self.tags3]:find("\t" .. chosen .. "\t",nil,true)) or (option == "series" and chosen == self.data[i][self.series]) then
                local entry = T(_("Title: %1"), (self.data[i][self.title] or "-")) .. "\n \n" ..
                              T(_("Author(s): %1"), (self.data[i][self.authors2] or "-")) .. "\n \n" ..
                              T(_("Tags: %1"), (self.data[i][self.tags2] or "-")) .. "\n \n" ..
                              T(_("Series: %1"), (self.data[i][self.series] or "-"))
                if self.data[i][self.series] ~= "-" then
                    entry = entry .. " (" .. tostring(self.data[i][self.series_index]):gsub(".0$","") .. ")"
                end
                entry = entry .. "\n \n" .. _("Path: ")
                local book = self.data[i][self.path]
                local text
                if option == "series" then
                    if self.data[i][self.series_index] == "0.0" then
                        text = self.data[i][self.title] .. " (" .. self.data[i][self.authors] .. ")"
                    else
                        text = string.format("%6.1f", self.data[i][self.series_index]:gsub(".0$","")) .. ": " .. self.data[i][self.title] .. " (" .. self.data[i][self.authors] .. ")"
                    end
                else
                    text = self.data[i][self.authors] .. ": " .. self.data[i][self.title]
                end
                table.insert(self.results, {
                   text = text,
                   info = entry,
                   notchecked = true,
                   path = self.data[i][self.path],
                   callback = function()
                       ReaderUI:showReader(book)
                       self.search_menu:onClose()
                   end
                })
            end
            i = i + 1
        end
    end

    local menu_title
    if run == 1 then
        menu_title = _("Browse") .. " " .. option
    else
        menu_title = chosen
    end

    table.sort(self.results, function(v1,v2) return v1.text < v2.text end)

    self.search_menu:switchItemTable(menu_title, self.results)
    UIManager:show(menu_container)
end

return Search
