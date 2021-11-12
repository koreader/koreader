local NewsHelpers = require("http_utilities")
local Version = require("version")
local logger = require("logger")
local socket_url = require("socket.url")
local _ = require("gettext")

local EpubBuilder = {
   -- Can be set so HTTP requests will be done under Trapper and
   -- be interruptible
   trap_widget = nil,
   -- For actions done with Trapper:dismissable methods, we may throw
   -- and error() with this code. We make the value of this error
   -- accessible here so that caller can know it's a user dismiss.
   dismissed_error_code = "Interrupted by user",
   title = nil,
   ncx_toc = nil,
   ncx_manifest = nil,
   ncx_contents = nil,
   ncx_images = nil,
}

function EpubBuilder:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

function EpubBuilder:build(abs_output_path)
    -- Open the zip file (with .tmp for now, as crengine may still
    -- have a handle to the final epub_path, and we don't want to
    -- delete a good one if we fail/cancel later)
    local tmp_path = abs_output_path .. ".tmp"
    local ZipWriter = require("ffi/zipwriter")
    local epub = ZipWriter:new{}

    if not epub:open(tmp_path) then
        logger.dbg("Failed to open tmp_path")
        return false
    end

    epub:add("mimetype", "application/epub+zip")
    epub:add("META-INF/container.xml", [[
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]])

    -- Add the manifest.
    if not self.ncx_manifest or #self.ncx_manifest == 0 then
        error("EPUB does not contain a valid manifest.")
    end
    --logger.dbg("Adding Manifest:", self.ncx_manifest)
    epub:add("OEBPS/content.opf", table.concat(self.ncx_manifest))

    -- Add the table of contents.
    if not self.ncx_toc or #self.ncx_toc == 0 then
        error("EPUB does not contain a valid table of contents.")
    end
    --logger.dbg("Adding TOC:", self.ncx_toc)
    epub:add("OEBPS/toc.ncx", table.concat(self.ncx_toc))

    -- Add the contents.
    if not self.ncx_contents or #self.ncx_manifest == 0 then
        error("EPUB does not contain any content.")
    end
    --logger.dbg("Adding Content:", self.ncx_contents)

    for index, content in ipairs(self.ncx_contents) do
        epub:add("OEBPS/" .. content.filename, content.html)
    end

    -- Add the images.
    --logger.dbg("Adding Images:", self.ncx_images)
    if self.ncx_images then
        for index, image in ipairs(self.ncx_images) do
            epub:add(
                "OEBPS/" .. image.path,
                image.content,
                image.no_compression
            )
        end
    end

    epub:close()
    os.rename(tmp_path, abs_output_path)

    collectgarbage()

end

function EpubBuilder:release()
    -- Stub for cleanup methods
end

-- filter HTML using CSS selector
local function filter(text, element)
    local htmlparser = require("htmlparser")
    local root = htmlparser.parse(text, 5000)
    local filtered = nil
    local selectors = {
        "main",
        "article",
        "div#main",
        "#main-article",
        ".main-content",
        "#body",
        "#content",
        ".content",
        "div#article",
        "div.article",
        "div.post",
        "div.post-outer",
        ".l-root",
        ".content-container",
        ".StandardArticleBody_body",
        "div#article-inner",
        "div#newsstorytext",
        "div.general",
        }
    if element and element ~= "" then
        table.insert(selectors, 1, element)
    end
    for _, sel in ipairs(selectors) do
       local elements = root:select(sel)
       if elements then
           for _, e in ipairs(elements) do
               filtered = e:getcontent()
               if filtered then
                   break
               end
           end
           if filtered then
               break
           end
       end
    end
    if not filtered then
        return text
    end
    return "<!DOCTYPE html><html><head></head><body>" .. filtered .. "</body></html>"
end

function EpubBuilder:getResponseAsString(url)
    logger.dbg("EpubBuilder:getResponseAsString(", url, ")")
    local success, content = NewsHelpers:getUrlContent(url)
    if (success) then
        return content
    else
        error("Failed to download content for url:", url)
    end
end

function EpubBuilder:setTrapWidget(trap_widget)
    self.trap_widget = trap_widget
end

function EpubBuilder:resetTrapWidget()
    self.trap_widget = nil
end

local ext_to_mimetype = {
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    svg = "image/svg+xml",
    html= "application/xhtml+xml",
    xhtml= "application/xhtml+xml",
    ncx = "application/x-dtbncx+xml",
    js = "text/javascript",
    css = "text/css",
    otf = "application/opentype",
    ttf = "application/truetype",
    woff = "application/font-woff",
}
-- GetPublishableHtml
function EpubBuilder:getImagesAndHtml(html, url, include_images, filter_enable, filter_element)
    local base_url = socket_url.parse(url)
    local images = {}
    local seen_images = {}
    local imagenum = 1
    local cover_imgid = nil -- best candidate for cover among our images
    html = filter_enable and filter(html, filter_element) or html

    local processImg = function(img_tag)
        local src = img_tag:match([[src="([^"]*)"]])
        if src == nil or src == "" then
            logger.dbg("no src found in ", img_tag)
            return nil
        end
        if src:sub(1,2) == "//" then
            src = "https:" .. src -- Wikipedia redirects from http to https, so use https
        elseif src:sub(1,1) == "/" then -- non absolute url
            src = socket_url.absolute(base_url, src)
        end
        local cur_image
        if seen_images[src] then -- already seen
            cur_image = seen_images[src]
        else
            local src_ext = src
            if src_ext:find("?") then -- "/w/extensions/wikihiero/img/hiero_D22.png?0b8f1"
                src_ext = src_ext:match("(.-)%?") -- remove ?blah
            end
            local ext = src_ext:match(".*%.(%S%S%S?%S?%S?)$") -- extensions are only 2 to 5 chars
            if ext == nil or ext == "" then
                -- we won't know what mimetype to use, ignore it
                logger.dbg("no file extension found in ", src)
                return nil
            end
            ext = ext:lower()
            local imgid = string.format("img%05d", imagenum)
            local imgpath = string.format("images/%s.%s", imgid, ext)
            local mimetype = ext_to_mimetype[ext] or ""
            local width = tonumber(img_tag:match([[width="([^"]*)"]]))
            local height = tonumber(img_tag:match([[height="([^"]*)"]]))
            -- Get higher resolution (2x) image url
            local src2x = nil
            local srcset = img_tag:match([[srcset="([^"]*)"]])
            if srcset then
                srcset = " "..srcset.. ", " -- for next pattern to possibly match 1st or last item
                src2x = srcset:match([[ (%S+) 2x, ]])
                if src2x then
                    if src2x:sub(1,2) == "//" then
                        src2x = "https:" .. src2x
                    elseif src2x:sub(1,1) == "/" then -- non absolute url
                        src2x = socket_url.absolute(base_url, src2x)
                    end
                end
            end
            cur_image = {
                imgid = imgid,
                imgpath = imgpath,
                src = src,
                src2x = src2x,
                mimetype = mimetype,
                width = width,
                height = height,
            }

            seen_images[src] = cur_image
            -- Use first image of reasonable size (not an icon) and portrait-like as cover-image
            if not cover_imgid and width and width > 50 and height and height > 50 and height > width then
                logger.dbg("Found a suitable cover image")
                cover_imgid = imgid
                cur_image["cover_image"] = true
            end

            table.insert(
                images,
                cur_image
            )

            imagenum = imagenum + 1
        end
        -- crengine will NOT use width and height attributes, but it will use
        -- those found in a style attribute.
        -- If we get src2x images, crengine will scale them down to the 1x image size
        -- (less space wasted by images while reading), but the 2x quality will be
        -- there when image is viewed full screen with ImageViewer widget.
        local style_props = {}
        if cur_image.width then
            table.insert(style_props, string.format("width: %spx", cur_image.width))
        end
        if cur_image.height then
            table.insert(style_props, string.format("height: %spx", cur_image.height))
        end
        local style = table.concat(style_props, "; ")
        return string.format([[<img src="%s" style="%s" alt=""/>]], cur_image.imgpath, style)
    end

    if include_images then
        html = html:gsub("(<%s*img [^>]*>)", processImg)
    else
        -- Remove img tags to avoid little blank squares of missing images
        html = html:gsub("<%s*img [^>]*>", "")
        -- We could remove the whole image container <div class="thumb"...> ,
        -- but it's a lot of nested <div> and not easy to do.
        -- So the user will see the image legends and know a bit about
        -- the images they chose to not get.
    end

    -- Force a GC to free the memory we used (the second call may help
    -- reclaim more memory).
    collectgarbage()
    collectgarbage()
    return images, html
end

function EpubBuilder:setTitle(title)
    self.title = title
end


function EpubBuilder:addToc(chapters)
    local toc_ncx_parts = {}
    local depth = 0
    local num = 0

    for index, chapter in ipairs(chapters) do
        -- Add nav part for each chapter.
        table.insert(
            toc_ncx_parts,
            string.format([[<navPoint id="navpoint-%s" playOrder="%s"><navLabel><text>%s</text></navLabel><content src="%s.html"/></navPoint>]],
                num,
                num,
                chapter.title,
                chapter.md5
            )
        )
        num = num + 1
    end
    -- Prepend NCX head.
    table.insert(
        toc_ncx_parts,
        1,
        string.format([[
<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="%s"/>
    <meta name="dtb:depth" content="%s"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>%s</text>
  </docTitle>
  <navMap>
]],
"placeholder_bookid",
depth,
self.title
        )
    )
    -- Append NCX tail.
    table.insert(
        toc_ncx_parts,
        [[
  </navMap>
</ncx>
]]
    )
    self.ncx_toc = toc_ncx_parts
end

function EpubBuilder:addManifest(chapters, images)
    local content_opf_parts = {}
    local spine_parts = {}
    local meta_cover = "<!-- no cover image -->"

    if #images > 0 then
        for inum, image in ipairs(images) do
            table.insert(
                content_opf_parts,
                string.format([[<item id="%s" href="%s" media-type="%s"/>%s]],
                    image.imgid,
                    image.imgpath,
                    image.mimetype,
                    "\n"
                )
            )
            -- See if the image has the tag we previously set indicating
            -- it can be used as a cover image.
            if image.cover_image then
                meta_cover = string.format([[<meta name="cover" content="%s"/>]], image.imgid)
            end
        end
    end

    if #chapters > 0 then
        for index, chapter in ipairs(chapters) do
            table.insert(
                content_opf_parts,
                string.format([[<item id="%s" href="%s.html" media-type="application/xhtml+xml"/>%s]],
                    chapter.md5,
                    chapter.md5,
                    "\n"
                )
            )
            table.insert(
                spine_parts,
                string.format([[<itemref idref="%s"/>%s]],
                    chapter.md5,
                    "\n"
                )
            )
        end
    end

    logger.dbg("meta_cover:", meta_cover)

    table.insert(
        content_opf_parts,
        1,
        string.format([[<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        unique-identifier="bookid" version="2.0">
  <metadata>
    <dc:title>%s</dc:title>
    <dc:publisher>KOReader %s</dc:publisher>
    %s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
]], self.title, Version:getCurrentRevision(), meta_cover)
    )
    -- tail
    table.insert(
        content_opf_parts,
        string.format([[
  </manifest>
  <spine toc="ncx">
%s
  </spine>
</package>
]], table.concat(spine_parts)
        )
    )

    self.ncx_manifest = content_opf_parts
end

function EpubBuilder:addContents(chapters)
    local contents = {}

    for index, chapter in ipairs(chapters) do
        table.insert(
            contents,
            {
                filename = chapter.md5 .. ".html",
                html = chapter.html,
            }
        )
    end

    self.ncx_contents = contents
end

function EpubBuilder:addImages(images)
    local images_table = {}

    for index, image in ipairs(images) do
        if not image.src then
            return
        end

        local src = image.src
        local success, content = NewsHelpers:getUrlContent(src)
        -- success, content = NewsHelpers:getUrlContent(src..".unexistant") -- to simulate failure
        if success then
            logger.dbg("EpubBuilder:addImages = success, size:", #content)
        else
            logger.dbg("EpubBuilder:addImages = failure fetching:", src)
        end

        if success then
            -- Images do not need to be compressed, so spare some cpu cycles
            local no_compression = true
            if image.mimetype == "image/svg+xml" then -- except for SVG images (which are XML text)
                no_compression = false
            end
            table.insert(
                images_table,
                {
                    path = image.imgpath,
                    content = content,
                    compression = no_compression
                }
            )
        end
    end

    self.ncx_images = images_table

end

-- There can be multiple links.
-- For now we just assume the first link is probably the right one.
--- @todo Write unit tests.
-- Some feeds that can be used for unit test.
-- http://fransdejonge.com/feed/ for multiple links.
-- https://github.com/koreader/koreader/commits/master.atom for single link with attributes.
function EpubBuilder:getFeedLink(possible_link)
    local E = {}
    logger.dbg("Possible link", possible_link)
    if type(possible_link) == "string" then
        return possible_link
    elseif (possible_link._attr or E).href then
        return possible_link._attr.href
    elseif ((possible_link[1] or E)._attr or E).href then
        return possible_link[1]._attr.href
    end
end


return EpubBuilder
