local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")

local Screensaver = {
}

function Screensaver:getCoverPicture(file)
    local contentopf
    local contentpath
    local epub_folder = "temp/epub"

    local function check_extension(cover)
        if cover then
            local itype = string.lower(string.match(cover, ".+%.([^.]+)") or "")
            if not (itype == "png" or itype == "jpg" or itype == "jpeg") then
                cover = nil
            end
         end
         return cover
    end

    local function getValue(zipfile,which_line,to_find,excludecheck)
        local f = io.open(zipfile,"r")
        local i

        if f then
            local line = f:read()
            while line and not i do
                i = line:lower():find(which_line:lower()) -- found something
                if i then
                    f.close()
                    line = line:match(to_find .. "\"([^\"]+)\".*")
                    if not excludecheck then line = check_extension(line) end
                    if line then
                        return line
                    else
                        i = nil
                    end
                end
                if not i then line = f:read() end
            end
            f.close()
        end
    end

    local function guess(extension)
        local cover = contentpath .. "Images/cover." .. extension
        pcall(os.execute("unzip \"" .. file .. "\" \"" .. cover .. "\" -oq -d " .. epub_folder))
        cover = epub_folder .. "/" .. cover
        if not io.open(cover,"r") then
            cover = nil
        end
        return cover
    end

    local function try_content_opf(which_line,to_find,addimage)
        local cover = getValue(epub_folder .. "/" .. contentopf,which_line,to_find)
        local imageadd
        if cover then
            if addimage then
                imageadd = "Images/"
            else
                imageadd = ""
            end
            cover = contentpath .. imageadd .. cover
            pcall(os.execute("unzip \"" .. file .. "\" \"" .. cover .. "\" -oq -d " .. epub_folder))
            cover = epub_folder .. "/" .. cover
            if not io.open(cover,"r") then cover = nil end
        end
        return check_extension(cover)
    end

    local function checkoldfile(cover)
        if io.open(cover) then
            return cover
        end
    end

    local cover

    local oldfile = "temp/" .. file:gsub("/","#") .. "."

    cover = checkoldfile(oldfile .. "jpg")
    if not cover then cover = checkoldfile(oldfile .. "jpeg") end
    if not cover then cover = checkoldfile(oldfile .. "png") end

    if not cover then

        if file then
            pcall(lfs.mkdir("temp"))
            pcall(os.execute("rm -rf " .. epub_folder))
            pcall(lfs.mkdir(epub_folder))
            pcall(os.execute("unzip \"" .. file .. "\" cover.jpeg -oq -d " .. epub_folder))
            if io.open(epub_folder .. "/cover.jpeg","r") then                                          -- picture in main folder
                cover = epub_folder .. "/cover.jpeg"                                                    -- found one
            else
                pcall(os.execute("unzip \"" .. file .. "\" \"META-INF/container.xml\" -oq -d " .. epub_folder)) -- read container.xml
                contentopf = getValue(epub_folder .. "/META-INF/container.xml","^%s*<rootfile ","full[-]path=",true)
                if contentopf then
                    contentpath = contentopf:match("(.*)[/][^/]+")
                    if contentpath then
                        contentpath = contentpath .. "/"
                    else
                        contentpath = ""
                    end
                    pcall(os.execute("unzip \"" .. file .. "\" \"" .. contentopf .. "\" -oq -d " .. epub_folder))  -- read content.opf

                    cover = try_content_opf("^%s*<meta name=\"cover\"","content=",true)  -- Make Room
                    if not cover then cover = try_content_opf('id="cover',"item href=",false) end -- Kishon
                    if not cover then cover = try_content_opf("cover","href=",true) end
                    if not cover then cover = try_content_opf("cover","=",true) end
                    if not cover then cover = try_content_opf("cover","=",false) end

                    if not cover then guess("jpg") end
                    if not cover then guess("jpeg") end
                    if not cover then guess("png") end
                end
            end
        end
        cover=check_extension(cover)
        if cover then
            oldfile = oldfile .. string.lower(string.match(cover, ".+%.([^.]+)"))
            pcall(os.execute('mv "' .. cover .. '" "' .. oldfile .. '"'))
            cover = oldfile
            pcall(os.execute('find temp/#mnt#* -mtime +30 -exec rm -v {} \\;'))
        end
        pcall(os.execute("rm -rf " .. epub_folder))
    end
    return cover
end

function Screensaver:getRandomPicture(dir)
    local pics = {}
    local i = 0
    math.randomseed(os.time())
    for entry in lfs.dir(dir) do
        if lfs.attributes(dir .. entry, "mode") == "file" then
            local extension = string.lower(string.match(entry, ".+%.([^.]+)") or "")
            if extension == "jpg" or extension == "jpeg" or extension == "png" then
                i = i + 1
                pics[i] = entry
            end
        end
    end
    return pics[math.random(i)]
end

function Screensaver:show()
    DEBUG("show screensaver")
    local InfoMessage = require("ui/widget/infomessage")
    local ImageWidget = require("ui/widget/imagewidget")
    local file = nil
    -- first check book cover image
    if KOBO_SCREEN_SAVER_LAST_BOOK then
        file = self:getCoverPicture(G_reader_settings:readSetting("lastfile"))
    -- then screensaver image
    elseif type(KOBO_SCREEN_SAVER) == "string" then
        file = KOBO_SCREEN_SAVER
        if lfs.attributes(file, "mode") == "directory" then
            if string.sub(file,string.len(file)) ~= "/" then
                file = file .. "/"
            end
            local dummy = self:getRandomPicture(file)
            if dummy then file = file .. dummy end
        end
    end
    if file and lfs.attributes(file, "mode") == "file" then
        self.suspend_msg = ImageWidget:new{
            file = file,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
        }
    end
    -- fallback to suspended message
    if not self.suspend_msg then
        self.suspend_msg = InfoMessage:new{ text = _("Suspended") }
    end
    UIManager:show(self.suspend_msg)
end

function Screensaver:close()
    DEBUG("close screensaver")
    if self.suspend_msg then
        UIManager:close(self.suspend_msg)
        self.suspend_msg = nil
    end
end

return Screensaver
