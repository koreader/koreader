describe("NewsDownloader URL normalization", function()
    setup(function()
        require("commonrequire")
    end)

    local NewsDownloader
    local DownloadBackend
    local socket_http

    local lorem_rss_xml = [=[
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Lorem Ipsum Feed</title>
    <link>https://koreader.rocks</link>
    <description>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</description>
    <atom:link href="https://koreader.rocks/lorem-feed/rss" rel="self" type="application/rss+xml"/>
    <item>
      <title><![CDATA[Lorem Ipsum Article]]></title>
      <link>https://koreader.rocks/lorem-feed/redirect/https%3A%2F%2Fkoreader.rocks%2Florem%2Fipsum%2Farticle</link>
      <pubDate>Sat, 14 Feb 2026 00:00:00 GMT</pubDate>
      <guid isPermaLink="false">https://koreader.rocks/lorem/ipsum/article</guid>
      <description><![CDATA[Lorem ipsum dolor sit amet, consectetur adipiscing elit.]]></description>
      <content:encoded><![CDATA[Lorem ipsum dolor sit amet, consectetur adipiscing elit.]]></content:encoded>
    </item>
  </channel>
</rss>
]=]

    local function with_mock(target, field, replacement, callback)
        local old = target[field]
        target[field] = replacement
        local ok, err = pcall(callback)
        target[field] = old
        if not ok then
            error(err)
        end
    end

    setup(function()
        local plugin_path = "plugins/newsdownloader.koplugin"
        package.path = plugin_path .. "/?.lua;" .. package.path
        NewsDownloader = require("main")
        NewsDownloader.path = plugin_path
        DownloadBackend = require("epubdownloadbackend")
        socket_http = require("socket.http")
    end)

    it("parses a valid RSS fixture", function()
        local feeds, err = NewsDownloader:deserializeXMLString(lorem_rss_xml)
        assert.truthy(feeds, err)
        assert.truthy(feeds.rss)
        assert.truthy(feeds.rss.channel)
        assert.equals("Lorem Ipsum Feed", feeds.rss.channel.title)

        local item = feeds.rss.channel.item
        assert.truthy(item)
        local first_item = item[1] or item
        assert.equals("Lorem Ipsum Article", first_item.title)
        assert.equals(
            "https://koreader.rocks/lorem-feed/redirect/https%3A%2F%2Fkoreader.rocks%2Florem%2Fipsum%2Farticle",
            first_item.link
        )
    end)

    it("preserves path separators while encoding spaces", function()
        local url = "https://koreader.rocks/lorem/feed/blog path/ipsum article"
        local requested_url

        with_mock(socket_http, "request", function(request)
            requested_url = request.url
            return 1, 200, { ["content-length"] = "0" }, "HTTP/1.1 200 OK"
        end, function()
            DownloadBackend:getResponseAsString(url, nil, false, nil)
        end)

        assert.equals("https://koreader.rocks/lorem/feed/blog%20path/ipsum%20article", requested_url)
        assert.is_true(requested_url ~= url)
    end)

    it("preserves existing percent-encoded octets in path", function()
        local url = "https://koreader.rocks/lorem/feed/redirect/https%3A%2F%2Fkoreader.rocks%2Florem%2Fipsum%2Farticle"
        local requested_url

        with_mock(socket_http, "request", function(request)
            requested_url = request.url
            return 1, 200, { ["content-length"] = "0" }, "HTTP/1.1 200 OK"
        end, function()
            DownloadBackend:getResponseAsString(url, nil, false, nil)
        end)

        assert.equals(url, requested_url)
    end)
end)
