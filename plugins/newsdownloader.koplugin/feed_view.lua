local logger = require("logger")
local _ = require("gettext")

local FeedView = {
    URL = "url",
    LIMIT = "limit",
    DOWNLOAD_FULL_ARTICLE = "download_full_article",
    INCLUDE_IMAGES = "include_images",
    ENABLE_FILTER = "enable_filter",
    FILTER_ELEMENT = "filter_element",
    BLOCK_ELEMENT = "block_element",
    -- HTTP Basic Auth (optional)
    HTTP_AUTH_USERNAME = "http_auth_username",
    HTTP_AUTH_PASSWORD = "http_auth_password",
}

function FeedView:getList(feed_config, callback, edit_feed_attribute_callback, delete_feed_callback)
    local view_content = {}
    -- Loop through the feed.
    for idx, feed in ipairs(feed_config) do
        local feed_item_content = {}

        local vc_feed_item = FeedView:getItem(
            idx,
            feed,
            edit_feed_attribute_callback,
            delete_feed_callback
        )

        if not vc_feed_item then
            logger.warn('NewsDownloader: invalid feed config entry', feed)
        else
            feed_item_content = FeedView:flattenArray(feed_item_content, vc_feed_item)
            local url = feed[1]
            table.insert(
                view_content,
                {
                    url,
                    "",
                    callback = function()
                        -- Here is where we trigger the single feed item display
                        callback(feed_item_content)
                    end
                }
            )
            -- Insert a divider.
            table.insert(
                view_content,
                "---"
            )
        end
    end
    return view_content
end

function FeedView:getItem(id, feed, edit_feed_callback, delete_feed_callback)

    logger.dbg("NewsDownloader:", feed)

    local url = feed[1]
    local limit = feed.limit

    -- If there's no URL or limit we don't care about this
    -- because we can't use it.
    if not url and limit then
        return nil
    end

    -- Collect this stuff for later, with the single view.
    local download_full_article = feed.download_full_article or false
    local include_images = feed.include_images ~= false
    local enable_filter = feed.enable_filter ~= false
    local filter_element = feed.filter_element
    local block_element = feed.block_element
    local http_auth = feed.http_auth or { username = nil, password = nil }
    local http_auth_username = http_auth.username
    local http_auth_password_set = type(http_auth.password) == "string" and #http_auth.password > 0

    local vc = {
        {
            _("URL"),
            url,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.URL,
                    url
                )
            end
        },
        {
            _("Limit"),
            limit,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.LIMIT,
                    limit
                )
            end
        },
        {
            _("Download full article"),
            download_full_article,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.DOWNLOAD_FULL_ARTICLE,
                    download_full_article
                )
            end
        },
        {
            _("Include images"),
            include_images,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.INCLUDE_IMAGES,
                    include_images
                )
            end
        },
        {
            _("Enable filter"),
            enable_filter,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.ENABLE_FILTER,
                    enable_filter
                )
            end

        },
        {
            _("Filter element"),
            filter_element,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.FILTER_ELEMENT,
                    filter_element
                )
            end
        },
        {
            _("Block element"),
            block_element,
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.BLOCK_ELEMENT,
                    block_element
                )
            end
        },
        --- HTTP Basic auth fields (optional)
        "---",
        {
            _("HTTP auth username"),
            http_auth_username or "",
            callback = function()
                edit_feed_callback(
                    id,
                    FeedView.HTTP_AUTH_USERNAME,
                    http_auth_username
                )
            end
        },
        {
            _("HTTP auth password"),
            http_auth_password_set and "••••••" or "",
            callback = function()
                -- Do not prefill the password; let the user type a new value.
                edit_feed_callback(
                    id,
                    FeedView.HTTP_AUTH_PASSWORD,
                    ""
                )
            end
        },
    }

    -- We don't always display this. For instance: if a feed
    -- is being created, this button is not necessary.
    if delete_feed_callback then
        table.insert(
            vc,
            "---"
        )
        table.insert(
            vc,
            {
                _("Delete feed"),
                "",
                callback = function()
                    delete_feed_callback(
                        id
                    )
                end
            }
        )
    end

    return vc
end

--
-- KeyValuePage doesn't like to get a table with sub tables.
-- This function flattens an array, moving all nested tables
-- up the food chain, so to speak
--
function FeedView:flattenArray(base_array, source_array)
    for _, value in pairs(source_array) do
        if value[2] == nil then
            -- If the value is empty, then it's probably supposed to be a line
            table.insert(base_array, "---")
        else
            table.insert(base_array, {
                value[1],
                value[2],
                callback = value.callback,
            })
        end
    end
    return base_array
end

return FeedView
