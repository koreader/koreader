local Client = require("client")

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")
local DocumentRegistry = require("document/documentregistry")
local _ = require("gettext")

local GeminiPlugin = WidgetContainer:extend{
    name = "gemini",
    fullname = _("Gemini plugin"),
}

local done_setup = false
function GeminiPlugin:setup()
    if not done_setup then
        require("identities"):setup()
        self:onDispatcherRegisterActions()
        done_setup = true
        local GeminiDocument = require("geminidocument")
        DocumentRegistry:addProvider("gmi", "text/gemini", GeminiDocument, 100)
    end
end

function GeminiPlugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("browse_gemini", {category = "none", event = "BrowseGemini", title = _("Browse Gemini"), general = true, separator = true })
    Dispatcher:registerAction("gemini_back", {category = "none", event = "GeminiBack", title = _("Gemini: Back"), reader = true })
    Dispatcher:registerAction("gemini_unback", {category = "none", event = "GeminiUnback", title = _("Gemini: Unback"), reader = true })
    Dispatcher:registerAction("gemini_history", {category = "none", event = "GeminiHistory", title = _("Gemini: History"), reader = true })
    Dispatcher:registerAction("gemini_bookmarks", {category = "none", event = "GeminiBookmarks", title = _("Gemini: Bookmarks"), reader = true })
    Dispatcher:registerAction("gemini_mark", {category = "none", event = "GeminiMark", title = _("Gemini: Mark"), reader = true })
    Dispatcher:registerAction("gemini_next", {category = "none", event = "GeminiNext", title = _("Gemini: Next"), reader = true })
    Dispatcher:registerAction("gemini_add", {category = "none", event = "GeminiAdd", title = _("Gemini: Add"), reader = true })
    Dispatcher:registerAction("gemini_nav", {category = "none", event = "GeminiNav", title = _("Gemini: Open nav"), reader = true })
    Dispatcher:registerAction("gemini_input", {category = "none", event = "GeminiInput", title = _("Gemini: Input"), reader = true })
    Dispatcher:registerAction("gemini_reload", {category = "none", event = "GeminiReload", title = _("Gemini: Reload"), reader = true })
    Dispatcher:registerAction("gemini_up", {category = "none", event = "GeminiUp", title = _("Gemini: Up"), reader = true })
    Dispatcher:registerAction("gemini_goNew", {category = "none", event = "GeminiGoNew", title = _("Gemini: Enter URL"), reader = true, separator = true })
end

function GeminiPlugin:init()
    self:setup()

    -- A persistent Client instance handles events.
    Client:init(self.ui)
    table.insert(self, Client)
end

return GeminiPlugin
