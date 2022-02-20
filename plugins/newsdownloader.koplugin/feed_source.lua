local BD = require("ui/bidi")
local DownloadBackend = require("epubdownloadbackend")
local NewsHelpers = require("http_utilities")
local dateparser = require("lib.dateparser")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local FFIUtil = require("ffi/util")
local T = FFIUtil.template

local FeedSource = {
    file_extension = ".epub"
}

function FeedSource:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function FeedSource:getInitializedFeeds(feed_list, progress_callback, error_callback)
    local initialized_feeds = {}
    local unsupported_feeds_urls = {}

    for idx, feed in ipairs(feed_list) do
        local url = feed[1]
        -- Show a UI update
        progress_callback(T(
            _("Setting up feed %1 of %2."),
            idx,
            url
        ))
        -- Initialize the feed
        local ok, response = pcall(function()
            return self:initializeDocument(
                self:fetchDocumentByUrl(url)
            )
        end)
        -- If the initialization worked, add the feed
        -- to a list of initialized feeds
        if ok and response then
            table.insert(initialized_feeds, {
                config = feed,
                document = response,
            })
        else
            table.insert(unsupported_feeds_urls, {
                url .. ": " .. response
            })
        end
    end

    if #unsupported_feeds_urls > 0 then
        -- When some errors are present, we get a sour message that includes
        -- information about the source of the error.
        local unsupported_urls = ""
        for key, value in pairs(unsupported_feeds_urls) do
            -- Create the error message.
            --            unsupported_urls = unsupported_urls .. " " .. value[1] .. " " .. value[2]
            unsupported_urls = value[1] .. "\n\n"
            -- Not sure what this does.
            if key ~= #unsupported_feeds_urls then
                unsupported_urls = BD.url(unsupported_urls) .. ", "
            end
        end
        error_callback(
            T(N_("Could not initialize a feed:\n\n%2\n\nPlease review your feed configuration.", "Could not initialize %1 feeds:\n\n%2\n\nPlease review your feed configurations.", #unsupported_feeds_urls),
                #unsupported_feeds_urls, unsupported_urls)
        )
    end

    return initialized_feeds
end

-- This function contacts the feed website and attempts to get
-- the RSS/Atom document with a list of the latest items.
function FeedSource:fetchDocumentByUrl(url)
    local document
    -- Get the XML document representing the feed
    local ok, response = pcall(function()
            local success, content = NewsHelpers:getUrlContent(url)
            if (success) then
                return content
            else
                error("Failed to download content for url: " .. url, 0)
            end
    end)
    -- Check to see if a response is available to deserialize.
    if ok then
        -- Deserialize the XML document into something Lua can use
        document = NewsHelpers:deserializeXMLString(response)
    end
    -- Return the document or any errors that may have occured
    if ok or document then
        return document
    else
        if not ok then
            error("(Reason: Failed to download feed document)", 0)
        else
            error("(Reason: Error during feed document deserialization)", 0)
        end
    end
end

-- Supply this method with the XML document returned by the feed,
-- and it will initialized the document by extracting the feed title,
-- feed items, and items count.
function FeedSource:initializeDocument(document)
    local feed_title
    local feed_items
    local total_items

    local ok = pcall(function()
            return self:getFeedType(
                document,
                function()
                    -- RSS callback
                    feed_title = util.htmlEntitiesToUtf8(document.rss.channel.title)
                    feed_items = document.rss.channel.item
                    total_items = #document.rss.channel.item
                end,
                function()
                    -- Atom callback
                    feed_title = FeedSource:getFeedTitle(document.feed.title)
                    feed_items = document.feed.entry
                    total_items = #document.feed.entry
                end,
                function()
                    -- RDF callback
                    feed_title = util.htmlEntitiesToUtf8(document["rdf:RDF"].channel.title)
                    feed_items = document["rdf:RDF"].item
                    total_items = #document["rdf:RDF"].item
                end
            )
    end)

    if ok then
        document.title = feed_title
        document.items = feed_items
        document.total_items = total_items
        return document
    else
        error(_("Could not initialize feed document"), 0)
    end
end

function FeedSource:getItemsContent(feed, progress_callback, error_callback)
    local limit = tonumber(feed.config.limit)
    local total_items = (limit == 0) and
        feed.document.total_items or
        limit
    local initialized_feed_items = {}
    -- Download each ite0m in the feed
    for index, item in pairs(feed.document.items) do
        -- If limit has been met, stop downloading feed.
        if limit ~= 0 and index - 1 == limit then
            break
        end
        -- Display feedback to user.
        progress_callback(T(
            _("%3\n Downloading item %1 of %2"),
            index,
            total_items,
            feed.document.title
        ))
        -- Download the article's HTML.
        local ok, response = pcall(function()
                return self:initializeItemHtml(
                    feed,
                    self:getItemHtml(
                        item,
                        feed.config.download_full_article
                    )
                )
        end)

        -- Add the result to our table, or send a
        -- result to the error callback.
        if ok then
            table.insert(initialized_feed_items, {
                html = response.html,
                images = response.images,
                item_slug = FeedSource:getItemTitleWithDate(item),
                item_title = item.title,
                md5 = md5(item.title),
                feed_title = feed.document.title,
            })
        else
            error_callback(
                T(_("Could not get content for: %1"), feed.document.title)
            )
        end

    end

    if #initialized_feed_items > 0 then
        return initialized_feed_items
    else
        return nil
    end
end

function FeedSource:initializeItemHtml(feed, html)
    local url = feed.config[1]
    -- local download_full_article = feed.config.download_full_article ~= false
    local include_images = feed.config.include_images ~= false
    local filter_element = feed.config.filter_element or
        feed.config.filter_element == nil
    local enable_filter = feed.config.enable_filter ~= false
    local item_images, item_html = DownloadBackend:getImagesAndHtml(
        html,
        url,
        include_images,
        enable_filter,
        filter_element
    )
    return {
        html = item_html,
        images = item_images
    }
end

function FeedSource:getFeedType(document, rss_cb, atom_cb, rdf_cb)
    -- Check to see if the feed uses RSS.
    local is_rss = document.rss and
        document.rss.channel and
        document.rss.channel.title and
        document.rss.channel.item and
        document.rss.channel.item[1] and
        document.rss.channel.item[1].title and
        document.rss.channel.item[1].link
    -- Check to see if the feed uses Atom.
    local is_atom = document.feed and
        document.feed.title and
        document.feed.entry[1] and
        document.feed.entry[1].title and
        document.feed.entry[1].link
    -- Setup the feed values based on feed type
    local is_rdf = document["rdf:RDF"] and
        document["rdf:RDF"].channel and
        document["rdf:RDF"].channel.title
    if is_atom then
        return atom_cb()
    elseif is_rss then
        return rss_cb()
    elseif is_rdf then
        return rdf_cb()
    end
    -- Return the values through our callback, or call an
    -- error message if the feed wasn't RSS or Atom
    if not is_rss or not is_atom or not is_rdf then
        local error_message
        if not is_rss or not is_rdf then
            error_message = _("(Reason: Couldn't process RSS)")
        elseif not is_atom then
            error_message = _("(Reason: Couldn't process Atom)")
        end
        error(error_message)
    end
end

function FeedSource:getItemHtml(item, download_full_article)
    if download_full_article then
        return NewsHelpers:loadPage(
            FeedSource:getFeedLink(item.link)
        )
    else
        local feed_description = item.description or item.summary
        local footer = _("This is just a description of the feed. To download the full article instead, go to the News Downloader settings and change 'download_full_article' to 'true'.")
        return string.format([[<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'><title>%s</title></head>
<body><header><h2>%s</h2></header><article>%s</article>
<br><footer><small>%s</small></footer>
</body>
</html>]], item.title, item.title, feed_description, footer)
    end
end

-- @todo: move this elsewhere
function FeedSource:getEpubOutputDir(download_dir, sub_dir, epub_title)

    local feed_output_dir = ("%s%s/"):format(
        download_dir,
        util.getSafeFilename(util.htmlEntitiesToUtf8(sub_dir)))

    -- Create the output directory if it doesn't exist.
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    local file_name = FeedSource:getFeedTitle(epub_title)

    return ("%s%s%s"):format(
        feed_output_dir,
        file_name,
        self.file_extension
    )
end

function FeedSource:createEpub(title, chapters, abs_output_path, progress_callback, error_callback)

    local file_exists = lfs.attributes(abs_output_path, "mode")

    if file_exists then
        logger.dbg("NewsDownloader: Skipping. EPUB file already exists", abs_output_path)
        return true
    end

    if #chapters == 0 then
        error(_("Error: chapters contains 0 items"), 0)
    end

    local images = {}

    for index, chapter in ipairs(chapters) do
        for jndex, image in ipairs(chapter.images) do
            table.insert(
                images,
                image
            )
        end
    end

    local epub = DownloadBackend:new{}

    progress_callback(T(_("Building EPUB %1"), title))
    epub:setTitle(title)
    epub:addToc(chapters)
    epub:addManifest(chapters, images)

    progress_callback(T(_("Building EPUB %1: %2"), title, _("Adding contents")))
    epub:addContents(chapters)

    progress_callback(T(_("Building EPUB %1: %2"), title, _("Adding images")))
    epub:addImages(images)

    progress_callback(T(_("Building EPUB %1: %2"), title, _("Writing EPUB to disk")))
    local ok = pcall(function()
        return epub:build(abs_output_path)
    end)

    if ok then
        if lfs.attributes(abs_output_path, "mode") then
            return true
        end
    end

    return false
end

local function parseDate(dateTime)
    -- Uses lua-feedparser https://github.com/slact/lua-feedparser
    -- feedparser is available under the (new) BSD license.
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENCE_lua-feedparser
    local date = dateparser.parse(dateTime)
    return os.date("%y-%m-%d_%H-%M_", date)
end

function FeedSource:getFeedTitleWithDate(feed)
    local title = util.getSafeFilename(FeedSource:getFeedTitle(feed.document.title))
    return os.date("%y-%m-%d_%H-%M_") .. title
end

-- Creates a title with date from a feed item.
function FeedSource:getItemTitleWithDate(item)
    local title = util.getSafeFilename(FeedSource:getFeedTitle(item.title))
    if item.updated then
        title = parseDate(item.updated) .. title
    elseif item.pubDate then
        title = parseDate(item.pubDate) .. title
    elseif item.published then
        title = parseDate(item.published) .. title
    end
    return title
end

-- If a title looks like <title>blabla</title> it'll just be feed.title.
-- If a title looks like <title attr="alb">blabla</title> then we get a table
-- where [1] is the title string and the attributes are also available.
function FeedSource:getFeedTitle(possible_title)
    if type(possible_title) == "string" then
        return util.htmlEntitiesToUtf8(possible_title)
    elseif possible_title[1] and type(possible_title[1]) == "string" then
        return util.htmlEntitiesToUtf8(possible_title[1])
    end
end
-- There can be multiple links.
-- For now we just assume the first link is probably the right one.
--- @todo Write unit tests.
-- Some feeds that can be used for unit test.
-- http://fransdejonge.com/feed/ for multiple links.
-- https://github.com/koreader/koreader/commits/master.atom for single link with attributes.
function FeedSource:getFeedLink(possible_link)
    local E = {}
    if type(possible_link) == "string" then
        return possible_link
    elseif (possible_link._attr or E).href then
        return possible_link._attr.href
    elseif ((possible_link[1] or E)._attr or E).href then
        return possible_link[1]._attr.href
    end
end


return FeedSource
