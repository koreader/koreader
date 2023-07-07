local http = require("socket.http")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local logger = require("logger")
local ltn12 = require("ltn12")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local socket = require("socket")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")
local url = require("socket.url")
local _ = require("gettext")
local T = require("ffi/util").template

local OPDSPSE = {}

-- This function attempts to pull chapter progress from Kavita.
function OPDSPSE:getLastPage(remote_url, username, password)
    local last_page = 0

    -- create URL's and reference vars
    local chapter = string.match(remote_url, "chapterId=(%w+)")
    local api_key = string.match(remote_url, "opds/(.+)/image")
    local progress_url = string.match(remote_url, "(.+)/api").."/api/Reader/get-progress?chapterId="..chapter
    local auth_url = string.match(remote_url, "(.+)/api").."/api/Plugin/authenticate?apiKey="..api_key.."&pluginName=KOReader-OPDS"

    -- Do an HTTP POST to get the Bearer Token for authentication of the /api/Reader/get-progress endpoint
    local auth_parsed = url.parse(auth_url)
    local auth_data = {}
    local auth_code, auth_headers, auth_status
    if auth_parsed.scheme == "http" or auth_parsed.scheme == "https" then
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        auth_code, auth_headers, auth_status = socket.skip(1, http.request {
            method = "POST",
            url         = auth_url,
            headers     = {
                ["Accept-Encoding"] = "identity",
                ["Authentication"] = api_key,
            },
            sink        = ltn12.sink.table(auth_data),
            user        = username,
            password    = password,
        })
        socketutil:reset_timeout()
    else
        UIManager:show(InfoMessage:new {
            text = T(_("Invalid protocol:\n%1"), auth_parsed.scheme),
        })
    end

    if auth_code == 200 then
        -- if http request for bearer token was successful, pull bearer token from response and
        -- attempt to pull progress for chapterId in remote_url
        local bearer_token = auth_data[1]:match("\"token\":\"(.+)\",\"refresh")

        -- Do HTTP GET request for chapter progress
        local progress_parsed = url.parse(progress_url)
        local progress_data = {}
        local progress_code, progress_headers, progress_status
        if progress_parsed.scheme == "http" or progress_parsed.scheme == "https" then
            socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
            progress_code, progress_headers, progress_status = socket.skip(1, http.request {
                url         = progress_url,
                headers     = {
                    ["Accept-Encoding"] = "identity",
                    ["Authorization"] = "Bearer "..bearer_token,
                },
                sink        = ltn12.sink.table(progress_data),
                user        = username,
                password    = password,
            })
            socketutil:reset_timeout()
        else
            UIManager:show(InfoMessage:new {
                text = T(_("Invalid protocol:\n%1"), progress_parsed.scheme),
            })
        end

        if progress_code == 200 then
            -- if HTTP GET was successful, pull page number from response
            last_page = progress_data[1]:match("\"pageNum\":(.+),\"seriesId")
        else
            logger.dbg("OPDSPSE:getLastPage: Progress Request failed:", progress_status or progress_code)
            logger.dbg("OPDSPSE:getLastPage: Progress Response headers:", progress_headers)
        end
    else
        logger.dbg("OPDSPSE:getLastPage: Authentication Request failed:", auth_status or auth_code)
        logger.dbg("OPDSPSE:getLastPage: Authentication Response headers:", auth_headers)
    end

    -- returns page number. If the HTTP Requests were unsuccessful, defaults to 0.
    return last_page;
end

function OPDSPSE:streamPages(remote_url, count, continue, username, password)
    -- attempt to pull chapter progress from Kavita if user pressed
    -- "Page Stream" button.
    -- We have to pull the progress here, otherwise the creation of the page_table
    -- will overwrite the book progress before we pull it, making it always 0.
    local ok, last_page = pcall(function() return self:getLastPage(remote_url, username, password) end)
    if not ok then
        logger.warn("Couldn't pull progress, defaulting to Page 0.")
        last_page = 0
    end
    local page_table = {image_disposable = true}
    setmetatable(page_table, {__index = function (_, key)
        if type(key) ~= "number" then
            local error_bb = RenderImage:renderImageFile("resources/koreader.png", false)
            return error_bb
        else
            local index = key - 1
            local page_url = remote_url:gsub("{pageNumber}", tostring(index))
            page_url = page_url:gsub("{maxWidth}", tostring(Screen:getWidth()))
            local page_data = {}

            logger.dbg("Streaming page from", page_url)
            local parsed = url.parse(page_url)

            local code, headers, status
            if parsed.scheme == "http" or parsed.scheme == "https" then
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
                code, headers, status = socket.skip(1, http.request {
                    url         = page_url,
                    headers     = {
                        ["Accept-Encoding"] = "identity",
                    },
                    sink        = ltn12.sink.table(page_data),
                    user        = username,
                    password    = password,
                })
                socketutil:reset_timeout()
            else
                UIManager:show(InfoMessage:new {
                    text = T(_("Invalid protocol:\n%1"), parsed.scheme),
                })
            end

            local data = table.concat(page_data)
            if code == 200 then
                local page_bb = RenderImage:renderImageData(data, #data, false)
                             or RenderImage:renderImageFile("resources/koreader.png", false)
                return page_bb
            else
                logger.dbg("OPDSBrowser:streamPages: Request failed:", status or code)
                logger.dbg("OPDSBrowser:streamPages: Response headers:", headers)
                local error_bb = RenderImage:renderImageFile("resources/koreader.png", false)
                return error_bb
            end
        end
    end})
    local ImageViewer = require("ui/widget/imageviewer")
    local viewer = ImageViewer:new{
        image = page_table,
        fullscreen = true,
        with_title_bar = false,
        image_disposable = false, -- instead set page_table image_disposable to true
        images_list_nb = count,
    }
    UIManager:show(viewer)
    if continue then
        self:jumpToPage(viewer, count)
    else
        -- add 1 since Kavita's Page count is zero based
        -- and ImageViewer is not.
        viewer:switchToImageNum(last_page+1)
    end
end

-- Shows a page number dialog for page streaming.
function OPDSPSE:jumpToPage(viewer, count)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Enter page number"),
        input_type = "number",
        input_hint = "(" .. "1 - " .. count .. ")",
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
                    text = _("Stream"),
                    is_enter_default = true,
                    callback = function()
                        local page_num = input_dialog:getInputValue()
                        if page_num then
                            UIManager:close(input_dialog)
                            viewer:switchToImageNum(math.min(math.max(1, page_num), count))
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return OPDSPSE
