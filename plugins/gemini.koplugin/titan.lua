local InputDialog = require("ui/widget/inputdialog")
local DocumentRegistry = require("document/documentregistry")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local _ = require("gettext")
local T = require("ffi/util").template

local titan = {}

local function extToMime(ext)
    for mime, e in pairs(DocumentRegistry.mimetype_ext) do
        if e == ext then
            return mime
        end
    end
end

local function build_titan_uri(u, size, mimetype, token)
    local pchar = "%w%-._~" .. "!$&'()*+,;=" .. ":@"
    local unescaped = pchar .. "/"
    local function escape(s)
        return s:gsub("[^"..unescaped.."]", function(c)
            return string.format("%%%x",c:byte(1))
        end)
    end
    return u .. ";size=" .. size
        .. (mimetype and mimetype ~= "" and mimetype ~= "text/gemini" and (";mime=" .. escape(mimetype)) or "")
        .. (token and token ~= "" and (";token=" .. escape(token)) or "")
end

function titan.doTitan(cb, u, edit_body, edit_mimetype, repeating)
    u = u:match("^([^;]*);?")

    local function uploadBody(body, mimetype)
        local widget
        widget = MultiInputDialog:new{
            title = #body > 0 and T(_("Upload %1 bytes"), #body) or _("Delete remote file"),
            fields = {
                {
                    description = _("Mimetype"),
                    text = mimetype,
                },
                {
                    description = _("Token"),
                    hint = _("(Fill in if the server directed you to)"),
                },
            },
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(widget)
                            titan.doTitan(cb, u, body, mimetype)
                        end
                    },
                    {
                        text = #body > 0 and _("Upload") or _("Delete"),
                        callback = function()
                            local fields = widget:getFields()
                            UIManager:close(widget)
                            local titan_uri = build_titan_uri(u, #body, fields[1], fields[2])
                            cb(titan_uri, body, fields[1])
                        end
                    },
                },
            }
        }
        UIManager:show(widget)
        widget:onShowKeyboard()
    end

    if repeating then
        return uploadBody(edit_body, edit_mimetype)
    end

    if edit_mimetype and not edit_mimetype:match("^text/") then
        edit_body = nil
    end

    local dialog
    dialog = InputDialog:new{
        title = T(edit_body and _("Edit at %1") or _("Upload to %1"), u),
        input = edit_body,
        input_hint = _("Enter text to upload, or select Upload File"),
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = edit_body and function()
            return edit_body
        end,
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
                    text = _("Upload File"),
                    callback = function()
                        local default_path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
                        local PathChooser = require("ui/widget/pathchooser")
                        local path_chooser = PathChooser:new{
                            select_directory = false,
                            select_file = true,
                            show_files = true,
                            file_filter = nil,
                            path = default_path,
                            onConfirm = function(path)
                                local f = io.open(path, "r")
                                if f then
                                    local b = f:read("a")
                                    f:close()
                                    local ext = path:match(".*%.([^%.]*)$")
                                    UIManager:close(dialog)
                                    uploadBody(b, ext and extToMime(ext) or "application/octet-stream")
                                end
                            end,
                        }
                        dialog:onCloseKeyboard()
                        UIManager:show(path_chooser)
                    end,
                },
                {
                    text = _("Upload Text"),
                    callback = function()
                        local b = dialog:getInputText()
                        UIManager:close(dialog)
                        uploadBody(b, "text/gemini")
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return titan
