local gemini = require("gemini")
local Identities = require("identities")
local SchemeProxies = require("schemeproxies")

local BD = require("ui/bidi")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local Device = require("device")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local FileManager = require("apps/filemanager/filemanager")
local DocSettings = require("docsettings")
local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local Trapper = require("ui/trapper")
local InfoMessage = require("ui/widget/infomessage")
local CheckButton = require("ui/widget/checkbutton")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local SpinWidget = require("ui/widget/spinwidget")
local Menu = require("ui/widget/menu")
local Persist = require("persist")
local NetworkMgr = require("ui/network/manager")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local TextViewer = require("ui/widget/textviewer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local Screen = require("device").screen
local Version = require("version")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local url = require("socket.url")
local sha256 = require("ffi/sha2").sha256
local util = require("util")
local ffiutil = require("ffi/util")
local _ = require("gettext")
local T = require("ffi/util").template

local gemini_dir = DataStorage:getDataDir() .. "/gemini"
local history_dir = "/tmp/gemini-history"
local queue_dir = "/tmp/gemini-queue"
local marks_path = gemini_dir .. "/bookmarks.gmi"
--local cafile_path = DataStorage:getDataDir() .. "/data/ca-bundle.crt"

local function getDefaultSavesDir()
    local dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    if dir:sub(-1) ~= "/" then
        dir = dir .. "/"
    end
    return dir .. "downloaded"
end
local save_dir = G_reader_settings:readSetting("gemini_save_dir") or getDefaultSavesDir()

local queue_persist = Persist:new{ path = gemini_dir .. "/queue.lua" }
local trust_store_persist = Persist:new{ path = gemini_dir .. "/known_hosts.lua" }

local Client = WidgetContainer:extend{
    active = false,     -- are we currently browsing gemini
    activated = false,  -- are we about to be browsing gemini at next init

    hold_pan = false,

    repl_purl = nil,    -- parsed URL to request input at after init

    history = {},
    unhistory = {},
    trust_overrides = {},

    max_input_history = 10,
    input_history = {},

    queue = queue_persist:load() or {},
    trust_store = trust_store_persist:load() or {},
}

local default_max_cache_history_items = 20
local max_cache_history_items = G_reader_settings:readSetting("gemini_max_cache_history_items") or default_max_cache_history_items


-- Parsed URL of current item
function Client:purl()
    if #self.history > 0 then
        return self.history[1].purl
    end
end

function Client:init(ui)
    self.ui = ui
    self.active = self.activated
    self.activated = false
    if self.active then
        assert(self:purl())
        local postcb = self.ui.registerPostReaderReadyCallback or
            self.ui.registerPostReadyCallback
            -- Name for the callback in versions <= 2024.04
        if postcb then
            if self.ui.document.file then
                -- Keep gemini history files out of reader history
                postcb(self.ui, function ()
                    ReadHistory:removeItemByPath(self.ui.document.file)
                end)
            end
            if self.repl_purl then
                local local_repl_purl = self.repl_purl
                postcb(self.ui, function ()
                    -- XXX: Input widget painted over without this delay. Better way?
                    UIManager:scheduleIn(0.1, function ()
                        self:promptInput(local_repl_purl, "[Repeating]", false, true)
                    end)
                end)
            end
        end
    end
    self.repl_purl = nil

    if self.ui and self.ui.link then
        if self.ui.link.registerScheme then
            for _,scheme in ipairs(SchemeProxies:supportedSchemes()) do
                self.ui.link:registerScheme(scheme)
            end
            if self.active then
                self.ui.link:registerScheme("")
            end
        end
        self.ui.link:addToExternalLinkDialog("23_gemini", function(this, link_url)
            return {
                text = _("Open via Gemini"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("FollowGeminiLink", link_url))
                end,
                show_in_dialog_func = function(u)
                    local scheme = u:match("^(%w[%w+%-.]*):") or ""
                    if scheme == "" and self.active then
                        return true
                    end
                    return util.arrayContains(SchemeProxies:supportedSchemes(), scheme)
                end,
            }
        end)
    end

    self.ui.menu:registerToMainMenu(self)

    if self.ui and self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("20_queue_links", function(this)
            return {
                text = _("Add links to queue"),
                show_in_highlight_dialog_func = function()
                    return self.active
                end,
                callback = function()
                    self:queueLinksInSelected(this.selected_text)
                    this:onClose()
                end,
            }
        end)
    end

    if self.active and Device:isTouchDevice() then
        self.ui:registerTouchZones({
            {
                id = "tap_link_gemini",
                ges = "tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    -- Tap on gemini links has priority over everything
                    "tap_link",
                    "readerhighlight_tap",
                    "tap_top_left_corner",
                    "tap_top_right_corner",
                    "tap_left_bottom_corner",
                    "tap_right_bottom_corner",
                    "readerfooter_tap",
                    "readerconfigmenu_ext_tap",
                    "readerconfigmenu_tap",
                    "readermenu_ext_tap",
                    "readermenu_tap",
                    "tap_forward",
                    "tap_backward",
                },
                handler = function(ges) return self:onTap(nil, ges) end,
            },
            {
                id = "hold_release_link_gemini",
                ges = "hold_release",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    "readerhighlight_hold_release",
                },
                handler = function(ges) return self:onHoldRelease(nil, ges) end,
            },
            {
                id = "hold_pan_link_gemini",
                ges = "hold_pan",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    "readerhighlight_hold_pan",
                },
                handler = function(ges) return self:onHoldPan(nil, ges) end,
            },
            {
                id = "double_tap_link_gemini",
                ges = "double_tap",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                overrides = {
                    "double_tap_top_left_corner",
                    "double_tap_top_right_corner",
                    "double_tap_bottom_left_corner",
                    "double_tap_bottom_right_corner",
                    "double_tap_left_side",
                    "double_tap_right_side",
                },
                handler = function(ges) return self:onDoubleTap(nil, ges) end,
            },
            {
                id = "swipe_gemini",
                ges = "swipe",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0,
                    ratio_w = 1, ratio_h = 1,
                },
                handler = function(ges) return self:onSwipe(nil, ges) end,
            },
        })
    end
end

function Client:mimeToExt(mimetype)
    return (mimetype == "text/plain" and "txt")
        or DocumentRegistry:mimeToExt(mimetype)
        or (mimetype and mimetype:find("^text/") and "txt")
end

local function writeBodyToFile(body, path)
    local o = io.open(path, "w")
    if o then
        if type(body) == "string" then
            o:write(body)
            o:close()
            return true
        else
            local chunk, aborted = body:read(256)
            while chunk and chunk ~= "" do
                o:write(chunk)
                chunk, aborted = body:read(256)
            end
            body:close()
            o:close()
            return not aborted
        end
    else
        return false
    end
end

function Client:saveBody(body, mimetype, purl)
    self:getSavePath(purl, mimetype, function(path)
        if not writeBodyToFile(body, path) then
            -- clear up partial write
            FileManager:deleteFile(path, true)
        end
    end)
end

function Client:openBody(body, mimetype, purl, cert_info, replace_history)
    util.makePath(history_dir)

    local function get_ext(p)
        if p.path then
            local ext, m = p.path:gsub(".*%.","",1)
            if m == 1 and ext:match("^%w*$") then
                return ext
            end
        end
    end
    local hn = #self.history
    if replace_history then
        hn = hn - 1
    end
    local tn = history_dir .. "/Gemini " .. hn
    local ext = self:mimeToExt(mimetype) or get_ext(purl)
    if ext then
        tn = tn .. "." .. ext
    end

    if not DocumentRegistry:hasProvider(tn) then
        UIManager:show(ConfirmBox:new{
            text = T(_("Can't view file (%1). Save it instead?"), mimetype or "unknown mimetype"),
            ok_text = _("Save file"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                self:saveBody(body, mimetype, purl)
            end,
        })
        return
    end

    if not replace_history then
        -- Delete history tail
        local ok, iter, dir_obj = pcall(lfs.dir, history_dir)
        if not ok then
            UIManager:show(InfoMessage:new{text = _("Failed to list history directory")})
            return
        end

        for f in iter, dir_obj do
            local path = history_dir.."/"..f
            local attr = lfs.attributes(path) or {}
            if attr.mode == "file" or attr.mode == "link" then
                local n = tonumber(f:match("^Gemini (%d+)%f[^%d]"))
                if n and (n >= #self.history or n <= #self.history - max_cache_history_items) then
                    FileManager:deleteFile(path, true)
                    local h = self.history[#self.history - n]
                    if h and h.path == path then
                        h.path = nil
                    end
                end
            end
        end
        while table.remove(self.unhistory) do end
    end

    if not writeBodyToFile(body, tn) then
        return
    end

    local history_item = { purl = purl, path = tn, mimetype = mimetype, cert_info = cert_info }
    if replace_history then
        self.history[1] = history_item
    else
        table.insert(self.history, 1, history_item)
    end

    self:openCurrent()
end

function Client:openCurrent()
    if not (self.history[1].path and util.fileExists(self.history[1].path)) then
        return self:openUrl(self.history[1].purl, { replace_history = true })
    end

    -- as in ReaderUI:switchDocument, but with seamless option
    local function switchDocumentSeamlessly(new_file)
        -- Mimic onShowingReader's refresh optimizations
        self.ui.tearing_down = true
        self.ui.dithered = nil

        self.ui:handleEvent(Event:new("CloseReaderMenu"))
        self.ui:handleEvent(Event:new("CloseConfigMenu"))
        self.ui.highlight:onClose() -- close highlight dialog if any
        self.ui:onClose(false)

        self.ui:showReader(new_file, nil, true)
    end

    local open_msg = InfoMessage:new{
        text = T(_("%1\nOpening..."), gemini.showUrl(self.history[1].purl, true)),
    }
    UIManager:show(open_msg)

    self.activated = true

    if self.ui.name == "ReaderUI" then
        --self.ui:switchDocument(history[1].path)
        switchDocumentSeamlessly(self.history[1].path)
    else
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(self.history[1].path, nil, true)
    end
    UIManager:close(open_msg)
end

function Client:writeDefaultBookmarks()
    if not util.fileExists(marks_path) then
        local f = io.open(marks_path, "w")
        if f then
            f:write(require("staticgemtexts").default_bookmarks)
            f:close()
        end
    end
end

function Client:openUrl(article_url, opts)
    if type(article_url) ~= "string" then
        article_url = url.build(article_url)
    end
    opts = opts or {}
    local body_cb = opts.body_cb or function(f, mimetype, p, cert_info)
        self:openBody(f, mimetype, p, cert_info, opts.replace_history)
    end
    if self:purl() then
        article_url = url.absolute(self:purl(), article_url)
    end

    local function fail(msg)
        UIManager:show(InfoMessage:new{
            text = msg,
            dismiss_callback = opts.after_err_cb,
        })
    end

    local purl = url.parse(article_url, {port = "1965"})

    if purl and purl.scheme == "about" then
        local body
        if purl.path == "bookmarks" then
            self:writeDefaultBookmarks()
            G_reader_settings:makeTrue("gemini_initiated")
            body = io.open(marks_path, "r")
        else
            body = require("staticgemtexts")[purl.path]
        end
        if body then
            body_cb(body, "text/gemini", purl)
        else
            fail(T(_("Unknown \"about:\" URL: %1"), article_url))
        end
        return
    end

    if purl and purl.scheme == "file" then
        if purl.host and purl.host ~= "" and purl.host ~= "localhost" then
            return fail(T(_("Can't open file URI with non-local host %1."), purl.host))
        elseif not purl.path then
            return fail(_("Can't open file URI with empty path."))
        end
        local attr = lfs.attributes(purl.path) or {}
        if attr.mode ~= "file" and attr.mode ~= "link" then
            return fail(_("No such file."))
        end
        local body = io.open(purl.path, "r")
        if body then
            return body_cb(body, nil, purl)
        else
            return fail(T(_("Failed to open path %1"), purl.path))
        end
    end

    if not purl or not purl.host then
        return fail(T(_("Invalid URL: %1"), article_url))
    end

    local proxy = SchemeProxies:get(purl.scheme)
    if purl.scheme ~= "gemini" and purl.scheme ~= "titan" and not proxy then
        return fail(T(_("No proxy configured for scheme: %1"), purl.scheme))
    end

    if NetworkMgr:willRerunWhenConnected(function() self:openUrl(article_url, opts) end) then
        return
    end

    local success_cb
    if purl and purl.scheme == "titan" then
        -- Putting this after willRerunWhenConnected, because that seems not
        -- to be reliable and we don't want the user to lose what they
        -- composed while offline.
        local titan = require("titan")
        local function titan_cb(u, b, mimetype)
            opts.titan_body = b
            opts.after_err_cb = function()
                titan.doTitan(titan_cb, u, b, mimetype, true)
            end
            self:openUrl(u, opts)
        end
        -- Warning: url.parse follows RFC 2396 rather than 3986, so doesn't
        -- parse valueless parameters like ";edit".
        if purl.path and article_url:match(";edit$") then
            -- This implements the extension to the Titan protocol described
            -- at gemini://transjovian.org/titan/page/Edit%20Link
            success_cb = function(f, mimetype, params, cert_info)
                local b = f:read("a")
                f:close()
                titan.doTitan(titan_cb, url.build(purl), b, mimetype)
            end
        elseif not opts.titan_body then
            return titan.doTitan(titan_cb, article_url)
        end
    end

    local id, __, id_path = Identities:get(article_url)
    success_cb = success_cb or function(f, mimetype, params, cert_info)
        if opts.repl_purl then
            self.repl_purl = opts.repl_purl
        end
        body_cb(f, mimetype, purl, cert_info)
    end
    local function error_cb(msg, major, minor, meta)
        if major then
            if meta and #meta > 0 then
                msg = T(_("Server reports %1: %2"), msg, meta)
            else
                msg = T(_("Server reports %1"), msg)
            end
        end
        if major == "1" then
            self:promptInput(purl, meta, minor == "1", false, nil, opts)
        elseif major == "3" then
            opts.num_redirects = opts.num_redirects or 0
            if opts.num_redirects >= 5 then
                return fail(_("Too many redirects."))
            else
                local new_uri = url.absolute(purl, meta)
                local pnew = url.parse(new_uri)
                if not pnew then
                    return fail(T("BUG: Unparseable URI on redirection: %1"), meta)
                end
                -- TODO: automatically edit bookmarks file if permanent?
                opts.num_redirects = opts.num_redirects + 1
                opts.titan_body = nil
                local function confirm_redir(t)
                    UIManager:show(ConfirmBox:new{
                        text = t,
                        ok_text = _("Follow"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            self:openUrl(new_uri, opts)
                        end,
                    })
                end
                if pnew.scheme ~= purl.scheme and
                    not ((pnew.scheme == "gemini" and purl.scheme == "titan") or
                        (pnew.scheme == "titan" and purl.scheme == "gemini")) then
                    return confirm_redir(T(_("Follow cross-scheme redirect to %1?"), new_uri))
                end
                local new_id = Identities:get(new_uri)
                if new_id and id ~= new_id then
                    return confirm_redir(T(_("Follow redirect to %1 using identity %2?"), new_uri, new_id))
                end
                self:openUrl(new_uri, opts)
            end
        elseif major == "6" then
            UIManager:show(ConfirmBox:new{
                text = msg,
                ok_text = _("Set identity"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    Identities:confAt(gemini.showUrl(purl), function(new_id)
                        if new_id then
                            self:openUrl(purl, opts)
                        end
                    end)
                end,
            })
        else
            fail(msg)
        end
    end
    local function check_trust_cb(host, new_fp, old_trusted_times, old_expiry, cb)
        if self.trust_overrides[new_fp] and os.time() < self.trust_overrides[new_fp] then
            cb("once")
        else
            self:promptUnexpectedCert(host, new_fp, old_trusted_times, old_expiry, cb)
        end
    end
    local function trust_modified_cb()
        trust_store_persist:save(self.trust_store)
    end
    local function info_cb(msg, fast)
        return Trapper:info(msg, fast)
    end

    Trapper:wrap(function()
        Trapper:setPausedText(T(_("Abort connection?")))
        gemini.makeRequest(gemini.showUrl(purl),
            id and id_path..".key",
            id and id_path..".crt",
            nil, -- disable CA-based verification
            self.trust_store,
            check_trust_cb,
            trust_modified_cb,
            success_cb,
            error_cb,
            info_cb,
            G_reader_settings:isTrue("gemini_confirm_tofu"),
            proxy and proxy.host,
            opts.titan_body)
        Trapper:reset()
    end)
end

-- Prompt user for input. May modify purl.
function Client:promptInput(purl, prompt, is_secret, repl, initial, openUrl_opts)
    local input_dialog
    local repl_button
    local multiline_button
    local function submit()
        local input = input_dialog:getInputText()
        purl.query = input
        gemini.escape(purl)
        if #url.build(purl) > 1024 then
            UIManager:show(InfoMessage:new{ text =
            T(_("Input too long (by %1 bytes)"), #url.build(purl) - 1024) })
        else
            UIManager:close(input_dialog)
            table.insert(self.input_history, 1, input)
            if #self.input_history > self.max_input_history then
                table.remove(self.input_history, #self.input_history)
            end
            local opts = openUrl_opts or {}
            opts.repl_purl = repl_button.checked and purl
            opts.after_err_cb = function()
                self:promptInput(purl, prompt, is_secret, repl_button.checked, input, openUrl_opts)
            end
            self:openUrl(purl, opts)
        end
    end
    local hi = 0
    local latest_input
    local function update_buttons()
        local prev_button = input_dialog.button_table:getButtonById("prev")
        prev_button:enableDisable(#self.input_history > hi)
        UIManager:setDirty(prev_button, "ui")
        local next_button = input_dialog.button_table:getButtonById("next")
        next_button:enableDisable(hi > 0)
        UIManager:setDirty(next_button, "ui")
    end
    local function to_hist(i)
        if hi == 0 then
            latest_input = input_dialog:getInputText()
        end
        hi = i
        input_dialog:setInputText(hi > 0 and self.input_history[hi] or latest_input, nil, false)
        update_buttons()
    end
    input_dialog = InputDialog:new{
        title = prompt,
        text_type = is_secret and "password",
        enter_callback = submit,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    icon = "move.up",
                    id = "prev",
                    callback = function() to_hist(hi+1) end,
                    hold_callback = function() to_hist(#self.input_history) end
                },
                {
                    icon = "move.down",
                    id = "next",
                    callback = function() to_hist(hi-1) end,
                    hold_callback = function() to_hist(0) end
                },
                {
                    text = _("Enter"),
                    callback = submit,
                },
            },
        },
    }
    if initial then
        input_dialog:setInputText(initial, nil, false)
    end
    update_buttons()

    -- read-eval-print-loop mode: keep presenting input dialog
    repl_button = CheckButton:new{
        text = _("Repeat"),
        checked = repl,
        parent = input_dialog,
    }
    multiline_button = CheckButton:new{
        text = _("Multiline input"),
        checked = false,
        callback = function()
            input_dialog.allow_newline = multiline_button.checked
            -- FIXME: less hacky way to do this?
            if multiline_button.checked then
                input_dialog._input_widget.enter_callback = nil
            else
                input_dialog._input_widget.enter_callback = submit
            end
        end,
        parent = input_dialog,
    }
    input_dialog:addWidget(multiline_button)
    input_dialog:addWidget(repl_button)

    local y_offset = 0
    if repl then
        -- Draw just above keyboard (in vertical mode),
        -- so we can see as much as possible of the newly loaded page
        y_offset = Screen:scaleBySize(120)
        if G_reader_settings:isTrue("keyboard_key_compact") then
            y_offset = y_offset + 50
        end
    end

    UIManager:show(input_dialog, nil, nil, nil, y_offset)
    input_dialog:onShowKeyboard()
    return true
end

function Client:userPromptInput(purl)
    self:promptInput(purl, "[Input]", false, false, url.unescape(purl.query or ""))
end

function Client:promptUnexpectedCert(host, new_fp, old_trusted_times, old_expiry, cb)
    local widget = MultiConfirmBox:new{
        text = old_trusted_times > 0 and
            T(_([[
The server identity presented by %1 does not match that previously trusted (%2 times).
Digest of received certificate: SHA256:%3
Previously trusted certificate expiry date: %4]]), host, old_trusted_times, new_fp, old_expiry) or
            T(_([[
No trusted server identity known for %1. Trust provided server identity?
Digest of received certificate: SHA256:%2]]), host, new_fp),
        face = Font:getFace("x_smallinfofont"),
        choice1_text = _("Trust new certificate"),
        choice1_callback = function()
            cb("always")
        end,
        choice2_text = _("Connect without trust"),
        choice2_callback = function()
            -- persist for 1h
            self.trust_overrides[new_fp] = os.time() + 3600
            cb("once")
        end,
        cancel_callback = function()
            cb()
        end,
    }
    UIManager:show(widget)
end

function Client:goBack(n)
    n = n or 1
    if n > #self.history-1 then
        n = #self.history-1
    elseif n < -#self.unhistory then
        n = -#self.unhistory
    end
    if n == 0 then
        return false
    end
    while n > 0 do
        table.insert(self.unhistory, 1, table.remove(self.history, 1))
        n = n-1
    end
    while n < 0 do
        table.insert(self.history, 1, table.remove(self.unhistory, 1))
        n = n+1
    end
    self:openCurrent()
    return true
end

function Client:clearHistory()
    local function delete_item(item)
        if item.path then
            FileManager:deleteFile(item.path, true)
        end
    end

    while #self.history > 1 do
        delete_item(table.remove(self.history, 2))
    end
    while #self.unhistory > 0 do
        delete_item(table.remove(self.unhistory, 1))
    end
end

function Client:onTap(_, ges)
    if self.active then
        return self:followGesLink(ges)
    end
end

function Client:onDoubleTap(_, ges)
    if self.active then
        return self:followGesLink(ges, true)
    end
end

function Client:onHoldPan(_, ges)
    self.hold_pan = true
end

function Client:onHoldRelease(_, ges)
    if self.active and not self.hold_pan then
        if self:followGesLink(ges, true) then
            if self.ui.highlight then
                self.ui.highlight:clear()
            end
            return true
        end
    end
    self.hold_pan = false
end

function Client:onSwipe(_, ges)
    if self.active then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "south" then
            return self:goBack()
        elseif direction == "north" then
            self:showNav()
            return true
        end
    end
end

function Client:followGesLink(ges, nav)
    local link = self.ui.link:getLinkFromGes(ges)
    if link and link.xpointer then
        local scheme = link.xpointer:match("^(%w[%w+%-.]*):") or ""
        if util.arrayContains(SchemeProxies:supportedSchemes(), scheme)
            or (scheme == "" and self.active) then
            if nav then
                self:showNav(link.xpointer)
            else
                self:openUrl(link.xpointer)
            end
            return true
        end
    end
end

function Client:onFollowGeminiLink(u)
    return self:showNav(u)
end

function Client:onEndOfBook()
    -- TODO: seems we can't override the usual reader onEndOfBook handling.
    -- Leaving this as a hidden option for now.
    if G_reader_settings:isTrue("gemini_next_on_end") then
        if self.active and #self.queue > 0 then
            self:openQueueItem()
            return true
        end
    end
end

function Client:queueLinksInSelected(selected)
    local html = self.ui.document:getHTMLFromXPointers(selected.pos0, selected.pos1, nil, true)
    if html then
        -- Following pattern isn't strictly correct in general,
        -- but is for the html generated from a gemini document.
        local n = 0
        for u in html:gmatch('<a[^>]*href="([^"]*)"') do
            self:queueLink(u)
            n = n + 1
        end
        UIManager:show(InfoMessage:new{ text =
            n == 0 and _("No links found in selected text.") or
            T(_("Added %1 links to queue."), n)
        })
    end
end

function Client:queueBody(body, u, mimetype, cert_info, existing_item, prepend)
    util.makePath(queue_dir)
    local path = queue_dir.."/"..sha256(u)
    if writeBodyToFile(body, path) then
        if existing_item then
            existing_item.path = path
            existing_item.mimetype = mimetype
            existing_item.cert_info = cert_info
        else
            self:queueItem({ url = u, path = path, mimetype = mimetype, cert_info = cert_info }, prepend)
        end
    elseif not existing_item then
        self:queueItem({ url = u }, prepend)
    end
end

function Client:queueCachedHistoryItem(h, prepend)
    local body = io.open(h.path, "r")
    if body then
        self:queueBody(body, gemini.showUrl(h.purl), h.mimetype, h.cert_info, nil, prepend)
    end
end

function Client:fetchLink(u, item, prepend)
    self:openUrl(u, { body_cb = function(body, mimetype, purl, cert_info)
        self:queueBody(body, gemini.showUrl(purl), mimetype, cert_info, item, prepend)
    end})
end

function Client:fetchQueue()
    for _n,item in ipairs(self.queue) do
        if not item.path then
            self:fetchLink(item.url, item)
        end
    end
end

function Client:queueLink(u, prepend)
    local purl = url.parse(u)
    if purl and purl.scheme ~= "about" and
        not G_reader_settings:isTrue("gemini_no_fetch_on_add") and NetworkMgr:isConnected() then
        self:fetchLink(u, nil, prepend)
    else
        self:queueItem({ url = u }, prepend)
    end
end

function Client:queueItem(item, prepend)
    for k = #self.queue,1,-1 do
        if self.queue[k].url == item.url then
            table.remove(self.queue,k)
        end
    end
    if prepend then
        table.insert(self.queue, 1, item)
    else
        table.insert(self.queue, item)
    end
    queue_persist:save(self.queue)
end

function Client:openQueueItem(n)
    n = n or 1
    local item = self.queue[n]
    if item then
        if item.path then
            local f = io.open(item.path, "r")
            if not f then
                UIManager:show(InfoMessage:new{text = T(_("Failed to open %1 for reading."), item.path)})
            else
                self:openBody(f, item.mimetype, url.parse(item.url), item.cert_info)
                FileManager:deleteFile(item.path, true)
                self:popQueue(n)
            end
        elseif item.url:match("^about:") or NetworkMgr:isConnected() then
            self:openUrl(item.url)
            self:popQueue(n)
        else
            UIManager:show(InfoMessage:new{text = T(_("Need network connection to fetch %1"), item.url)})
        end
    end
end

function Client:popQueue(n)
    n = n or 1
    local item = table.remove(self.queue, n)
    queue_persist:save(self.queue)
    return item
end

function Client:clearQueue()
    while #self.queue > 0 do
        local item = table.remove(self.queue, 1)
        if item.path then
            FileManager:deleteFile(item.path, true)
        end
    end
    queue_persist:save(self.queue)
end

function Client:getSavePath(purl, mimetype, cb)
    local basename = ""
    local add_ext = false
    if purl.path then
        basename = purl.path:gsub("/+$","",1):gsub(".*/","",1)
        if basename == "" and purl.host then
            basename = purl.host
            add_ext = true
        end
        if add_ext or not basename:match(".+%..+") then
            local ext = self:mimeToExt(mimetype)
            if ext then
                basename = basename.."."..ext
            end
        end
    end

    local widget

    local function do_save()
        local fields = widget:getFields()
        local dir = fields[2]
        local bn = fields[1]
        if bn ~= "" then
            local path = dir.."/"..bn
            local tp = lfs.attributes(path, "mode")
            if tp == "directory" then
                UIManager:show(InfoMessage:new{text = _("Path is a directory")})
            elseif tp ~= nil then
                UIManager:show(ConfirmBox:new{
                    text = _("File exists. Overwrite?"),
                    ok_text = _("Overwrite"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        UIManager:close(widget)
                        cb(path)
                    end,
                })
            else
                UIManager:close(widget)
                util.makePath(dir)
                cb(path)
            end
        end
    end

    widget = MultiInputDialog:new{
        title = _("Save as"),
        fields = {
            {
                description = _("Filename"),
                text = basename,
            },
            {
                description = _("Directory to save under"),
                text = save_dir,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(widget)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = do_save,
                },
            },
        },
    }
    if widget.input_fields then
        widget.input_fields[1].enter_callback = do_save
        widget.input_fields[2].enter_callback = do_save
    elseif widget.input_field then
        -- backwards compatibility for <2024.07
        widget.input_field[1].enter_callback = do_save
        widget.input_field[2].enter_callback = do_save
    end
    UIManager:show(widget)
    widget:onShowKeyboard()
end

function Client:saveCurrent()
    self:getSavePath(self.history[1].purl, self.history[1].mimetype, function(path)
        ffiutil.copyFile(self.history[1].path, path)
        self.ui:saveSettings()
        if DocSettings.updateLocation then
            DocSettings.updateLocation(self.history[1].path, path, true)
        end
    end)
end

function Client:addMark(u, desc)
    if url.parse(u) then
        self:writeDefaultBookmarks()
        local line = "=> " .. u
        if desc and desc ~= "" then
            line = line .. " " .. desc
        end
        line = line .. "\n"
        local f = io.open(marks_path, "a")
        if f then
            f:write(line)
            f:close()
            return true
        end
    end
end

function Client:addMarkInteractive(uri)
    local widget
    local function add_mark()
        local fields = widget:getFields()
        if self:addMark(fields[2], fields[1]) then
            UIManager:close(widget)
        end
    end
    widget = MultiInputDialog:new{
        title = _("Add bookmark"),
        fields = {
            {
                description = _("Description (optional)"),
            },
            {
                description = _("URL"),
                text = gemini.showUrl(uri),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(widget)
                    end,
                },
                {
                    text = _("Add bookmark"),
                    is_enter_default = true,
                    callback = add_mark,
                },
            },
        },
    }
    if widget.input_fields then
        widget.input_fields[1].enter_callback = add_mark
        widget.input_fields[2].enter_callback = add_mark
    elseif widget.input_field then
        -- backwards compatibility for <2024.07
        widget.input_field[1].enter_callback = add_mark
        widget.input_field[2].enter_callback = add_mark
    end
    UIManager:show(widget)
    widget:onShowKeyboard()
end

function Client:showHistoryMenu(cb)
    cb = cb or function(n) self:goBack(n) end
    local menu
    local history_items = {}
    local function show_history_item(h)
        return gemini.showUrl(h.purl) ..
            (h.path and " " .. _("(fetched)") or "")
    end
    for n,h in ipairs(self.history) do
        table.insert(history_items, {
            text = T("%1 %2", n-1, show_history_item(h)),
            callback = function()
                cb(n-1)
                UIManager:close(menu)
            end,
            hold_callback = function()
                UIManager:close(menu)
                self:showNav(h.purl)
            end,
        })
    end
    for n,h in ipairs(self.unhistory) do
        table.insert(history_items, 1, {
            text = T("%1 %2", -n, show_history_item(h)),
            callback = function()
                cb(-n)
                UIManager:close(menu)
            end
        })
    end
    if #history_items > 1 then
        table.insert(history_items, {
            text = _("Clear all history"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Clear %1 history items?"), #history_items-1),
                    ok_text = _("Clear history"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        self:clearHistory()
                        UIManager:close(menu)
                    end,
                })
            end
        })
    end
    menu = Menu:new{
        title = _("History"),
        item_table = history_items,
        onMenuHold = function(_, item)
            if item.hold_callback then
                item.hold_callback()
            end
        end,
        width = Screen:getWidth(),   -- backwards compatibility;
        height = Screen:getHeight(), -- can delete for KOReader >= 2023.04
    }
    UIManager:show(menu)
end

function Client:viewCurrentAsText()
    local h = self.history[1]
    local f = io.open(h.path,"r")
    UIManager:show(TextViewer:new{
        title = gemini.showUrl(h.purl),
        text = f and f:read("a") or "[Error reading file]"
    })
    f:close()
end

function Client:showCurrentInfo()
    local h = self.history[1]
    local kv_pairs = {
        { _("URL"), gemini.showUrl(h.purl) },
        { _("Mimetype"), h.mimetype }
    }
    local widget
    if h.cert_info then
        table.insert(kv_pairs, "----")
        local cert_info = self.history[1].cert_info
        if cert_info.ca then
            table.insert(kv_pairs, { _("Trust type"), _("Chain to Certificate Authority") })
            for k, v in ipairs(cert_info.ca) do
                table.insert(kv_pairs, { v.name, v.value })
            end
        else
            if cert_info.trusted_times > 0 then
                table.insert(kv_pairs, { _("Trust type"), _("Trust On First Use"), callback = function()
                    UIManager:close(widget)
                    self:openUrl("about:tofu")
                end })
                table.insert(kv_pairs, { _("SHA256 digest"), cert_info.fp })
                table.insert(kv_pairs, { _("Times seen"), cert_info.trusted_times })
            else
                table.insert(kv_pairs, { _("Trust type"), _("Temporarily accepted") })
                table.insert(kv_pairs, { _("SHA256 digest"), cert_info.fp })
            end
            table.insert(kv_pairs, { _("Expiry date"), cert_info.expiry })
        end
    end
    table.insert(kv_pairs, "----")
    table.insert(kv_pairs, { "Source", _("Select to view page as text"), callback = function()
        self:viewCurrentAsText()
    end })
    widget = KeyValuePage:new{
        title = _("Page info"),
        kv_pairs = kv_pairs,
    }
    UIManager:show(widget)
end

function Client:editQueue()
    local menu
    local items = {}
    local function show_queue_item(item)
        return gemini.showUrl(item.url) ..
            (item.path and " " .. _("(fetched)") or "")
    end
    local unfetched = 0
    for n,item in ipairs(self.queue) do
        table.insert(items, {
            text = n .. " " .. show_queue_item(item),
            callback = function()
                UIManager:close(menu)
                self:openQueueItem(n)
            end,
            hold_callback = function()
                UIManager:close(menu)
                self:showNav(item.url)
            end,
        })
        if not item.path then
            unfetched = unfetched + 1
        end
    end
    if unfetched > 0 then
        table.insert(items, {
            text = T(_("Fetch %1 unfetched items"), unfetched),
            callback = function()
                self:fetchQueue()
                UIManager:close(menu)
                self:editQueue()
            end
        })
    end
    if #items > 0 then
        table.insert(items, {
            text = _("Clear queue"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Clear %1 items from queue?"), #self.queue),
                    ok_text = _("Clear queue"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        self:clearQueue()
                        UIManager:close(menu)
                    end,
                })
            end
        })
    end
    menu = Menu:new{
        title = _("Queue"),
        item_table = items,
        onMenuHold = function(_, item)
            if item.hold_callback then
                item.hold_callback()
            end
        end,
        width = Screen:getWidth(),   -- backwards compatibility;
        height = Screen:getHeight(), -- can delete for KOReader >= 2023.04
    }
    UIManager:show(menu)
end

function Client:showNav(uri, showKbd)
    if uri and type(uri) ~= "string" then
        uri = url.build(uri)
    end
    showKbd = showKbd or not uri or uri == ""
    if not uri then
        uri = gemini.showUrl(self:purl())
    elseif self:purl() and uri ~= "" then
        uri = url.absolute(self:purl(), uri)
    end

    local nav
    local advanced = false
    local function current_nav_url()
        local u = nav:getInputText()
        if u:match("^[./?]") then
            -- explicitly relative url
            if self:purl() then
                u = url.absolute(self:purl(), u)
            end
        else
            -- absolutise if necessary
            local purl = url.parse(u)
            if purl and purl.scheme == nil and purl.host == nil then
                u = "gemini://" .. u
            end
        end
        return u
    end
    local function current_input_nonempty()
        local purl = url.parse(current_nav_url())
        return purl and (purl.host or purl.path)
    end
    local function close_nav_keyboard()
        if nav.onCloseKeyboard then
            nav:onCloseKeyboard()
        elseif Version:getNormalizedCurrentVersion() < 202309010000 then
            -- backwards compatibility
            if nav._input_widget.onCloseKeyboard then
                nav._input_widget:onCloseKeyboard()
            end
        end
    end
    local function show_hist()
        close_nav_keyboard()
        self:showHistoryMenu(function(n)
            UIManager:close(nav)
            self:goBack(n)
        end)
    end
    local function queue_nav_url(prepend)
        if current_input_nonempty() then
            local u = current_nav_url()
            if u == gemini.showUrl(self:purl()) and self.history[1].path then
                self:queueCachedHistoryItem(self.history[1], prepend)
            else
                self:queueLink(u, prepend)
            end
            UIManager:close(nav)
        end
    end
    local function update_buttons()
        local u = current_nav_url()
        local purl = url.parse(u)
        local id = Identities:get(u)
        local text = T(_("Identity: %1"), id or _("[none]"))
        local id_button = nav.button_table:getButtonById("ident")
        if not advanced then
            id_button:setText(text, id_button.width)
        end
        id_button:enableDisable(advanced or (purl and purl.scheme == "gemini" and purl.host ~= ""))
        UIManager:setDirty(id_button, "ui")

        local save_button = nav.button_table:getButtonById("save")
        save_button:enableDisable(purl and purl.scheme and purl.scheme ~= "about")
        UIManager:setDirty(save_button, "ui")

        local info_button = nav.button_table:getButtonById("info")
        info_button:enableDisable(u == gemini.showUrl(self:purl()))
        UIManager:setDirty(info_button, "ui")
    end
    local function toggle_advanced()
        advanced = not advanced
        for _,row in ipairs(nav.button_table.buttons_layout) do
            for _,button in ipairs(row) do
                if button.text_func and button.hold_callback then
                    button:setText(button.text_func(), button.width)
                    button.callback, button.hold_callback = button.hold_callback, button.callback
                end
            end
        end
        update_buttons()
        UIManager:setDirty(nav, "ui")
    end

    nav = InputDialog:new{
        title = _("Gemini navigation"),
        width = Screen:scaleBySize(550), -- in pixels
        input_type = "text",
        input = uri and gemini.showUrl(uri) or "gemini://",
        buttons = {
            {
                {
                    text_func = function() return advanced and _("Edit identity URLs") or _("Identity") end,
                    id = "ident",
                    callback = function()
                        close_nav_keyboard()
                        Identities:confAt(current_nav_url(), function()
                            update_buttons()
                        end)
                    end,
                    hold_callback = function()
                        close_nav_keyboard()
                        Identities:edit()
                    end,
                },
                {
                    text_func = function() return advanced and _("View as text") or _("Page info") end,
                    id = "info",
                    callback = function()
                        UIManager:close(nav)
                        self:showCurrentInfo()
                    end,
                    hold_callback = function()
                        UIManager:close(nav)
                        self:viewCurrentAsText()
                    end,
                },
            },
            {
                {
                    text_func = function() return advanced and _("History") or _("Back") end,
                    enabled = #self.history > 1,
                    callback = function()
                        UIManager:close(nav)
                        self:goBack()
                    end,
                    hold_callback = show_hist,
                },
                {
                    text_func = function() return advanced and _("History") or _("Unback") end,
                    enabled = #self.unhistory > 0,
                    callback = function()
                        UIManager:close(nav)
                        self:goBack(-1)
                    end,
                    hold_callback = show_hist,
                },
                {
                    text_func = function() return advanced and _("Edit queue") or _("Next") end,
                    enabled = #self.queue > 0,
                    callback = function()
                        UIManager:close(nav)
                        self:openQueueItem()
                    end,
                    hold_callback = function()
                        UIManager:close(nav)
                        self:editQueue()
                    end,
                },
                {
                    text_func = function() return advanced and _("Edit marks") or _("Bookmarks") end,
                    callback = function()
                        UIManager:close(nav)
                        self:openUrl("about:bookmarks")
                    end,
                    hold_callback = function()
                        if self.ui.texteditor and self.ui.texteditor.quickEditFile then
                            UIManager:close(nav)
                            self:writeDefaultBookmarks()
                            local function done_cb()
                                if self:purl() and url.build(self:purl()) == "about:bookmarks" then
                                    self:openUrl("about:bookmarks", { replace_history = true })
                                end
                            end
                            self.ui.texteditor:quickEditFile(marks_path, done_cb, true)
                        else
                            UIManager:show(InfoMessage:new{text = T(_([[
Can't load TextEditor: Plugin disabled or incompatible.
To edit bookmarks, please edit the file %1 in the koreader directory manually.
]]), marks_path)})
                        end
                    end,
                },
            },
            {
                {
                    text_func = function() return advanced and _("Root") or _("Up") end,
                    callback = function()
                        nav:setInputText(gemini.upUrl(current_nav_url()))
                        update_buttons()
                    end,
                    hold_callback = function()
                        nav:setInputText(url.absolute(current_nav_url(), "/"))
                        update_buttons()
                    end,
                },
                {
                    text = _("Save"),
                    id = "save",
                    callback = function()
                        local u = current_nav_url()
                        local purl = url.parse(u)
                        if purl and purl.scheme and purl.scheme == "about" then
                            UIManager:show(InfoMessage:new{text = _("Can't save about: pages")})
                        elseif u == gemini.showUrl(self:purl()) then
                            UIManager:close(nav)
                            self:saveCurrent()
                        else
                            UIManager:close(nav)
                            self:openUrl(u, { body_cb = function(f, mimetype, p2)
                                self:saveBody(f, mimetype, p2)
                            end })
                        end
                    end,
                },
                {
                    text_func = function() return advanced and _("Prepend") or _("Add") end,
                    callback = queue_nav_url,
                    hold_callback = function() queue_nav_url(true) end,
                },
                {
                    text_func = function() return advanced and _("Quick mark") or _("Mark") end,
                    callback = function()
                        if current_input_nonempty() then
                            self:addMarkInteractive(current_nav_url())
                            UIManager:close(nav)
                        end
                    end,
                    hold_callback = function()
                        if current_input_nonempty()
                            and self:addMark(current_nav_url()) then
                            UIManager:close(nav)
                        end
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(nav)
                    end,
                },
                {
                    text_func = function() return advanced and _("Input") or _("Go") end,
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(nav)
                        local u = current_nav_url()
                        self:openUrl(u, { after_err_cb = function() self:showNav(u, true) end})
                    end,
                    hold_callback = function()
                        local purl = url.parse(current_nav_url())
                        if purl then
                            self:userPromptInput(purl)
                            UIManager:close(nav)
                        end
                    end,
                },
            },
        },
    }
    update_buttons()
    -- FIXME: less hacky way to do this?
    nav._input_widget.edit_callback = function(edited)
        if edited then
            update_buttons()
        end
    end

    nav.title_bar.right_icon = "appbar.settings"
    nav.title_bar.right_icon_tap_callback = toggle_advanced
    nav.title_bar:init()

    UIManager:show(nav)
    if showKbd then
        nav:onShowKeyboard()
    end
end

function Client:onBrowseGemini()
    if self.active then
        self:showNav()
    elseif #self.history > 0 then
        self:openCurrent()
    elseif G_reader_settings:nilOrFalse("gemini_initiated") then
        self:openUrl("about:welcome")
    else
        self:openUrl("about:bookmarks")
    end
    return true
end

function Client:onGeminiBack()
    if self.active then
        self:goBack()
        return true
    end
end
function Client:onGeminiUnback()
    if self.active then
        self:goBack(-1)
        return true
    end
end
function Client:onGeminiHistory()
    if self.active then
        self:showHistoryMenu()
        return true
    end
end
function Client:onGeminiBookmarks()
    self:openUrl("about:bookmarks")
    return true
end
function Client:onGeminiMark()
    if self.active then
        self:addMarkInteractive(gemini.showUrl(self:purl()))
        return true
    end
end
function Client:onGeminiNext()
    self:openQueueItem()
    return true
end
function Client:onGeminiAdd()
    if self.active then
        self:queueCachedHistoryItem(self.history[1])
        return true
    end
end
function Client:onGeminiInput()
    if self.active then
        self:userPromptInput(self.history[1].purl)
        return true
    end
end
function Client:onGeminiReload()
    if self.active then
        self:openUrl(self.history[1].purl, { replace_history = true })
        return true
    end
end
function Client:onGeminiUp()
    if self.active then
        local u = gemini.showUrl(self:purl())
        local up = gemini.upUrl(u)
        if up ~= u then
            self:openUrl(up)
        end
        return true
    end
end
function Client:onGeminiGoNew()
    self:showNav("")
    return true
end
function Client:onGeminiNav()
    self:showNav()
    return true
end

function Client:addToMainMenu(menu_items)
    menu_items.gemini = {
        sorting_hint = "search",
        text = _("Browse Gemini"),
        callback = function()
            self:onBrowseGemini()
        end,
    }
    local hint = "search_settings"
    if Version:getNormalizedCurrentVersion() < 202305180000 then
        -- backwards compatibility
        hint = "search"
    end
    menu_items.gemini_settings = {
        text = _("Gemini settings"),
        sorting_hint = hint,
        sub_item_table = {
            {
                text = _("Show help"),
                callback = function()
                    self:openUrl("about:help")
                end,
            },
            {
                text = T(_("Max cached history items: %1"), max_cache_history_items),
                help_text = _("History items up to this limit will be stored on the filesystem and can be accessed offline with Back."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local widget = SpinWidget:new{
                        title_text =  _("Max cached history items"),
                        value = max_cache_history_items,
                        value_min = 0,
                        value_max = 200,
                        default_value = default_max_cache_history_items,
                        callback = function(spin)
                            max_cache_history_items = spin.value
                            G_reader_settings:saveSetting("gemini_max_cache_history_items", spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
            {
                text = _("Set directory for saved documents"),
                keep_menu_open = true,
                callback = function()
                    local title_header = _("Current directory for saved gemini documents:")
                    local current_path = save_dir
                    local default_path = getDefaultSavesDir()
                    local function caller_callback(path)
                        save_dir = path
                        G_reader_settings:saveSetting("gemini_save_dir", path)
                        if not util.pathExists(path) then
                            lfs.mkdir(path)
                        end
                    end
                    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
                end,
            },
            {
                text = _("Configure scheme proxies"),
                help_text = _("Configure proxy servers to use for non-gemini URL schemes."),
                callback = function()
                    SchemeProxies:edit()
                end,
            },
            {
                text = _("Disable fetch on add"),
                help_text = _("Disables immediately fetching URLs added to the queue when connected."),
                checked_func = function()
                    return G_reader_settings:isTrue("gemini_no_fetch_on_add")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("gemini_no_fetch_on_add")
                end,
            },
            {
                text = _("Confirm certificates for new hosts"),
                help_text = _("Overrides the default behaviour of silently trusting the first server identity seen for a host, allowing you to confirm the certificate hash out-of-band."),
                checked_func = function()
                    return G_reader_settings:isTrue("gemini_confirm_tofu")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("gemini_confirm_tofu")
                end,
            },
        },
    }
end

return Client
