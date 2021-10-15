local BD = require("ui/bidi")
local DownloadBackend = require("epubdownloadbackend")
local NewsHelpers = require("http_utilities")
local dateparser = require("lib.dateparser")
local logger = require("logger")
local md5 = require("lib.md5")
local util = require("util")
local _ = require("gettext")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template

local FeedSource = {
    download_dir = nil,
    file_extension = ".epub"
}

function FeedSource:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

--
function FeedSource:getInitializedFeeds(feed_list, progress_callback, error_callback)
    local UI = require("ui/trapper")
    local initialized_feeds = {}
    local unsupported_feeds_urls = {}
    local total_feed_entries = #feed_list
    local feed_message

    for idx, feed in ipairs(feed_list) do
        local url = feed[1]
        -- Show a UI update
        progress_callback(T(
            _("Initializing feed %1 of %2"),
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
            table.insert(
                initialized_feeds,
                {
                    config = feed,
                    document = response
                }
            )
        else
            logger.dbg("FeedSource: Unsupported feed ", response)
            table.insert(
                unsupported_feeds_urls,
                {
                    url .. ": " .. response
                }
            )
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
            T(_([[Could not initialize some feeds\n\n %1 \n\nPlease review your feed configuration file after this process concludes.]]),
              unsupported_urls)
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
                error("Failed to download content for url:", url)
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
            error("(Reason: Failed to download feed document)")
        else
            error("(Reason: Error during feed document deserialization)")
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
--                    total_items = (limit == 0)
--                        and #document.rss.channel.item
--                        or limit
                end,
                function()
                    -- Atom callback
                    feed_title = FeedSource:getFeedTitle(document.feed.title)
                    feed_items = document.feed.entry
                    total_items = #document.feed.entry
                end
            )
    end)
    if ok then
        document.title = feed_title
        document.items = feed_items
        document.total_items = total_items
        return document
    else
        error("Could not initialize feed document")
    end
end
--
function FeedSource:getItemsContent(feed, progress_callback, error_callback)
    local limit = tonumber(feed.config.limit)
    local total_items = (limit == 0)
        and feed.document.total_items
        or limit

    local initialized_feed_items = {}
    -- Download each ite0m in the feed
    for index, item in pairs(feed.document.items) do
        -- If limit has been met, stop downloading feed.
        if limit ~= 0 and index - 1 == limit then
            break
        end
        -- Display feedback to user.
        progress_callback(T(
            _("Getting item %1 of %2 from %3"),
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
            table.insert(
                initialized_feed_items,
                {
                    html = response.html,
                    images = response.images,
                    item_slug = FeedSource:getTitleWithDate(item),
                    item_title = item.title,
                    md5 = md5.sumhexa(item.title),
                    feed_title = feed.document.title
                }
            )
        else
            error_callback(
                T(_("Could not get content for: %1"),
                  feed.document.title
                )
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
    local download_full_article = feed.config.download_full_article ~= false
    local include_images = not never_download_images and
        feed.config.include_images
    local filter_element = feed.config.filter_element or
        feed.config.filter_element == nil
    local enable_filter = feed.config.enable_filter ~= false
    local images, html = DownloadBackend:getImagesAndHtml(
        html,
        url,
        include_images,
        enable_filter,
        filter_element
    )
    return {
        html = html,
        images = images
    }
end

   -- self:outputEpub(feed_html[0], feed_output_dir, '')
--    self:outputEpub(html, feed_output_dir, article_message)
--

function FeedSource:getFeedType(document, rss_cb, atom_cb)
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
    if is_atom then
        return atom_cb()
    elseif is_rss then
        return rss_cb()
    end
    -- Return the values through our callback, or call an
    -- error message if the feed wasn't RSS or Atom
    if not is_rss or not is_atom then
        local error_message
        if not is_rss then
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

function FeedSource:createEpubFromFeeds(epub_items, download_dir, progress_callback, error_callback)
    -- Collect HTML
    for index, feed in pairs(epub_items) do

        for jndex, item in pairs(feed) do

            local feed_output_dir = ("%s%s/"):format(
                download_dir,
                util.getSafeFilename(util.htmlEntitiesToUtf8(item.feed_title)))
            -- Create the output directory if it doesn't exist.
            if not lfs.attributes(feed_output_dir, "mode") then
                lfs.mkdir(feed_output_dir)
            end

            logger.dbg("Creating EPUB titled: ", item.item_title)

            local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                                     item.item_title,
                                                     self.file_extension)
            local file_mode = lfs.attributes(news_file_path, "mode")

            DownloadBackend:createEpub(
                news_file_path,
                item.html,
                item.images,
                "message?"
            )
        end
    end
end

function FeedSource:createEpub(title, chapters, abs_output_path, progress_callback, error_callback)
    -- Collect HTML
    local images = {}

    if #chapters == 0 then
        error("Error: chapters contains 0 items")
    end

    for index, chapter in ipairs(chapters) do
        for jndex, image in ipairs(chapter.images) do
            table.insert(
                images,
                image
            )
        end
    end

    local epub = DownloadBackend:new{
        title = title
    }

    progress_callback("Building EPUB: " .. title)

    epub:addToc(chapters)
    epub:addManifest(chapters, images)
    epub:addContents(chapters)
    epub:addImages(images)
    epub:build(abs_output_path)

    local file_mode = lfs.attributes(abs_output_path, "mode")


end

function FeedSource:outputEpub(html, feed_output_dir, article_message)
    local title_with_date = FeedSource:getTitleWithDate('KO Volume 1')
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                             title_with_date,
                                             self.file_extension)
    local html
    local file_mode = lfs.attributes(news_file_path, "mode")
    if file_mode == "file" then
        logger.dbg("FeedSource:", news_file_path, "already exists. Skipping")
    else
        logger.dbg("FeedSource: News file will be stored to :", news_file_path)
        DownloadBackend:createEpub(news_file_path, html, '', false, article_message, '')
    end
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
function FeedSource:getTitleWithDate(feed)
    local title = util.getSafeFilename(FeedSource:getFeedTitle(feed.title))
    if feed.updated then
        title = parseDate(feed.updated) .. title
    elseif feed.pubDate then
        title = parseDate(feed.pubDate) .. title
    elseif feed.published then
        title = parseDate(feed.published) .. title
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
