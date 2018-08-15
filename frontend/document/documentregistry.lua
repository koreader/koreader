--[[--
This is a registry for document providers
]]--

local ConfirmBox = require("ui/widget/confirmbox")
local OpenWithDialog = require("ui/widget/openwithdialog")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local DocumentRegistry = {
    registry = {},
    providers = {},
    filetype_provider = {},
}

function DocumentRegistry:addProvider(extension, mimetype, provider, weight)
    table.insert(self.providers, {
        extension = extension,
        mimetype = mimetype,
        provider = provider,
        weight = weight or 100,
    })
    self.filetype_provider[extension] = true
end

function DocumentRegistry:getRandomFile(dir, opened, extension)
    local DocSettings = require("docsettings")
    if string.sub(dir, string.len(dir)) ~= "/" then
        dir = dir .. "/"
    end
    local files = {}
    local i = 0
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for entry in iter, dir_obj do
            if lfs.attributes(dir .. entry, "mode") == "file" and self:hasProvider(dir .. entry)
                and (opened == nil or DocSettings:hasSidecarFile(dir .. entry) == opened)
                and (extension == nil or extension[util.getFileNameSuffix(entry)]) then
                i = i + 1
                files[i] = entry
            end
        end
        if i == 0 then
            return nil
        end
    else
        return nil
    end
    math.randomseed(os.time())
    return dir .. files[math.random(i)]
end

--- Returns true if file has provider.
-- @string file
-- @treturn boolean
function DocumentRegistry:hasProvider(file)
    local filename_suffix = util.getFileNameSuffix(file)

    if self.filetype_provider[filename_suffix] then
        return true
    end
    return false
end

--- Returns the preferred registered document handler.
-- @string file
-- @treturn table provider, or nil
function DocumentRegistry:getProvider(file)
    local providers = self:getProviders(file)

    if providers then
        -- provider for document
        local DocSettings = require("docsettings")
        if DocSettings:hasSidecarFile(file) then
            local doc_settings_provider = DocSettings:open(file):readSetting("provider")
            if doc_settings_provider then
                for _, provider in ipairs(providers) do
                    if provider.provider.provider == doc_settings_provider then
                        return provider.provider
                    end
                end
            end
        end

        -- global provider for filetype
        local filename_suffix = util.getFileNameSuffix(file)
        local g_settings_provider = G_reader_settings:readSetting("provider")

        if g_settings_provider and g_settings_provider[filename_suffix] then
            for _, provider in ipairs(providers) do
                if provider.provider.provider == g_settings_provider[filename_suffix] then
                    return provider.provider
                end
            end
        end

        -- highest weighted provider
        return providers[1].provider
    end
end

--- Returns the registered document handlers.
-- @string file
-- @treturn table providers, or nil
function DocumentRegistry:getProviders(file)
    local providers = {}

    -- TODO: some implementation based on mime types?
    for _, provider in ipairs(self.providers) do
        local suffix = string.sub(file, -string.len(provider.extension) - 1)
        if string.lower(suffix) == "."..provider.extension then
        -- if extension == provider.extension then
            -- stick highest weighted provider at the front
            if #providers >= 1 and provider.weight > providers[1].weight then
                table.insert(providers, 1, provider)
            else
                table.insert(providers, provider)
            end
        end
    end

    if #providers >= 1 then
        return providers
    end
end

--- Sets the preferred registered document handler.
-- @string file
-- @bool all
function DocumentRegistry:setProvider(file, provider, all)
    local _, filename_suffix = util.splitFileNameSuffix(file)

    -- per-document
    if not all then
        local DocSettings = require("docsettings"):open(file)
        DocSettings:saveSetting("provider", provider.provider)
        DocSettings:flush()
    -- global
    else
        local filetype_provider = G_reader_settings:readSetting("provider") or {}
        filetype_provider[filename_suffix] = provider.provider
        G_reader_settings:saveSetting("provider", filetype_provider)
    end
end

function DocumentRegistry:showSetProviderButtons(file, filemanager_instance,  ui, reader_ui)
    local __, filename_pure = util.splitFilePathName(file)
    local filename_suffix = util.getFileNameSuffix(file)

    local buttons = {}
    local radio_buttons = {}
    local providers = self:getProviders(file)

    for ___, provider in ipairs(providers) do
        -- we have no need for extension, mimetype, weights, etc. here
        provider = provider.provider
        table.insert(radio_buttons, {
            {
                text = provider.provider_name,
                checked = self:getProvider(file) == provider,
                provider = provider,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.set_provider_dialog)
            end,
        },
        {
            text = _("Open"),
            is_enter_default = true,
            callback = function()
                local provider = self.set_provider_dialog.radio_button_table.checked_button.provider

                -- always for this file
                if self.set_provider_dialog._check_file_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open '%2' with %1?"),
                                         provider.provider_name, filename_pure),
                        ok_text = _("Always"),
                        ok_callback = function()
                            self:setProvider(file, provider, false)

                            filemanager_instance:onClose()
                            reader_ui:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                -- always for all files of this file type
                elseif self.set_provider_dialog._check_global_button.checked then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Always open %2 files with %1?"),
                                         provider.provider_name, filename_suffix),
                        ok_text = _("Always"),
                        ok_callback = function()
                            self:setProvider(file, provider, true)

                            filemanager_instance:onClose()
                            reader_ui:showReader(file, provider)
                            UIManager:close(self.set_provider_dialog)
                        end,
                    })
                else
                    -- just once
                    filemanager_instance:onClose()
                    reader_ui:showReader(file, provider)
                    UIManager:close(self.set_provider_dialog)
                end
            end,
        },
    })

    self.set_provider_dialog = OpenWithDialog:new{
        title = T(_("Open %1 with:"), filename_pure),
        radio_buttons = radio_buttons,
        buttons = buttons,
    }
    UIManager:show(self.set_provider_dialog)
end

function DocumentRegistry:openDocument(file, provider)
    -- force a GC, so that any previous document used memory can be reused
    -- immediately by this new document without having to wait for the
    -- next regular gc. The second call may help reclaming more memory.
    collectgarbage()
    collectgarbage()
    if not self.registry[file] then
        provider = provider or self:getProvider(file)

        if provider ~= nil then
            local ok, doc = pcall(provider.new, provider, {file = file})
            if ok then
                self.registry[file] = {
                    doc = doc,
                    refs = 1,
                }
            else
                logger.warn("cannot open document", file, doc)
            end
        end
    else
        self.registry[file].refs = self.registry[file].refs + 1
    end
    if self.registry[file] then
        return self.registry[file].doc
    end
end

function DocumentRegistry:closeDocument(file)
    if self.registry[file] then
        self.registry[file].refs = self.registry[file].refs - 1
        if self.registry[file].refs == 0 then
            self.registry[file] = nil
            return 0
        else
            return self.registry[file].refs
        end
    else
        error("Try to close unregistered file.")
    end
end

-- load implementations:

require("document/credocument"):register(DocumentRegistry)
require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)

return DocumentRegistry
