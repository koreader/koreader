local CreDocument = require("document/credocument")
local FileManager = require("apps/filemanager/filemanager")
local url = require("socket.url")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local GeminiDocument = CreDocument:extend{}

local function convertGmi(i, o)
    local pre = false
    local function parseLine(line)
        -- strip ANSI CSI sequences (used in some gemtext documents for
        -- colour, which we do not try to support)
        line = line:gsub("%\x1b%[[ -?]*[@-~]","")

        local alt = line:match("^```%s*(.*)$")
        if alt then
            if not pre then
                pre = true
                -- use <small> to improve chance that wide ascii art will fit
                -- on the screen
                return "<small><pre>", false
            else
                pre = false
                return "</pre></small>", false
            end
        end
        if pre then
            return util.htmlEscape(line), false
        end

        if line:match("^%s*$") then
            return "<br/>", false
        end

        local link, desc
        link = line:match('^=>%s*([^%s]+)%s*$')
        if not link then
            link,desc = line:match('^=>%s*([^%s]+)%s+(.+)$')
        end
        if link then
            local purl = url.parse(link)
            desc = desc or link
            desc = util.htmlEscape(desc)
            if purl.scheme and purl.scheme ~= "gemini" then
                desc = desc .. T(" <em>[%1]</em>", purl.scheme)
            end
            return '<li><a href="' .. link .. '">' .. desc .. '</a></li>', true
        end

        local headers, text
        headers,text = line:match('^(#+)%s*(.*)$')
        if headers then
            local level = headers:len()
            if level <= 3 then
                return "<h" .. level .. ">" .. util.htmlEscape(text) .. "</h" .. level .. ">", false
            end
        end

        text = line:match("^%*%s+(.*)$")
        if text then
            return "<li>" .. util.htmlEscape(text) .. "</li>", true
        end

        text = line:match('^>(.*)$')
        if text then
            return "<blockquote>" .. util.htmlEscape(text) .. "</blockquote>", true
        end

        return "<p>" .. util.htmlEscape(line) .. "</p>"
    end

    o:write("<html>\n")
    -- Override css to not require page breaks on headers,
    -- and improve contrast for links.
    o:write([[
<head><style>
h1, h2, h3 {
    page-break-before: auto;
}
a {
    text-decoration: underline; color: #505050;
}
</style></head>
]])
    o:write("<body>\n")
    local in_list = false
    local list
    local written_line = false
    for line in i:lines() do
        line, list = parseLine(line)
        if list and not in_list then
            line = "<ul>" .. line
        elseif in_list and not list then
            line = "</ul>\n" .. line
        end
        in_list = list
        o:write(line .. "\n")
        written_line = true
    end
    i:close()
    if not written_line then
        -- work around CRE not rendering empty html documents properly
        o:write(_("[Empty gemini document]\n"))
    end
    o:write("</body></html>")
end

function GeminiDocument:init()
    self.tmp_html_file = os.tmpname() .. ".html"
    if not self.tmp_html_file then
        error(_("Failed to create temporary file for gmi -> html conversion."))
    end
    local i = io.open(self.file, "r")
    local o = io.open(self.tmp_html_file, "w")
    convertGmi(i, o)
    o:close()
    local gemfile = self.file
    self.file = self.tmp_html_file
    CreDocument.init(self)
    self.file = gemfile

    -- XXX: hack; uses that only these methods read self.file
    for _i,method in ipairs({"loadDocument","getNativePageDimensions","_readMetadata","getFullPageHash","renderPage"}) do
        self[method] = function(slf, ...)
            slf.file = slf.tmp_html_file
            local ok, re = pcall(CreDocument[method], slf, ...)
            slf.file = gemfile
            if ok then
                return re
            else
                logger.err("wrapped credocument call failed", method, re)
                return false
            end
        end
    end
end

function GeminiDocument:close()
    CreDocument.close(self)
    FileManager:deleteFile(self.tmp_html_file, true)
end

return GeminiDocument
