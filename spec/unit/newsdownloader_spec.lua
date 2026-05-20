describe("NewsDownloader module", function()
    setup(function()
        require("commonrequire")
    end)

    local NewsDownloader

    setup(function()
        local plugin_path = "plugins/newsdownloader.koplugin"
        package.path = plugin_path.."/?.lua;" .. package.path
        NewsDownloader = require("main")
        NewsDownloader.path = plugin_path
        NewsDownloader:lazyInitialization()
    end)

    describe("RSS feed parsing", function()
        local rss_xml = [[
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
  <title>KOReader News</title>
  <link>https://github.com/koreader/koreader</link>
  <description>KOReader updates and release notes</description>
  <item>
    <title>KOReader v2023.05 released</title>
    <link>https://github.com/koreader/koreader/releases/tag/v2023.05</link>
    <description>New release with improved PDF rendering and UI enhancements</description>
  </item>
  <item>
    <title>KOReader v2023.04 released</title>
    <link>https://github.com/koreader/koreader/releases/tag/v2023.04</link>
    <description>&lt;p&gt;Bug fixes &amp; improved EPUB handling&lt;/p&gt;</description>
  </item>
</channel>
</rss>
]]

        it("should parse RSS feed titles correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(rss_xml)
            assert.truthy(feeds)
            assert.truthy(feeds.rss)
            assert.truthy(feeds.rss.channel)
            assert.truthy(feeds.rss.channel.title)
            assert.equals("KOReader News", feeds.rss.channel.title)

            -- Test item titles
            assert.truthy(feeds.rss.channel.item)
            assert.equals("KOReader v2023.05 released", feeds.rss.channel.item[1].title)
            assert.equals("KOReader v2023.04 released", feeds.rss.channel.item[2].title)
        end)

        it("should parse RSS feed descriptions correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(rss_xml)
            assert.truthy(feeds)

            -- Test channel description
            assert.equals("KOReader updates and release notes", feeds.rss.channel.description)

            -- Test item descriptions
            assert.equals("New release with improved PDF rendering and UI enhancements",
                          feeds.rss.channel.item[1].description)

            -- Test HTML entities handling in descriptions
            assert.equals("<p>Bug fixes & improved EPUB handling</p>",
                          require("util").htmlEntitiesToUtf8(feeds.rss.channel.item[2].description))
        end)

        it("should parse RSS feed links correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(rss_xml)
            assert.truthy(feeds)

            -- Test channel link
            assert.equals("https://github.com/koreader/koreader", feeds.rss.channel.link)

            -- Test item links
            assert.equals("https://github.com/koreader/koreader/releases/tag/v2023.05",
                          feeds.rss.channel.item[1].link)
            assert.equals("https://github.com/koreader/koreader/releases/tag/v2023.04",
                          feeds.rss.channel.item[2].link)

            -- Test getFeedLink function using the exposed module function
            assert.equals("https://github.com/koreader/koreader/releases/tag/v2023.05",
                          NewsDownloader.getFeedLink(feeds.rss.channel.item[1].link))
        end)
    end)

    describe("Atom feed parsing", function()
        local atom_xml = [[
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>KOReader GitHub Commits</title>
  <link href="https://github.com/koreader/koreader/commits/master.atom"/>
  <updated>2023-05-15T12:00:00Z</updated>
  <entry>
    <title>Fix PDF rendering issue</title>
    <link href="https://github.com/koreader/koreader/commit/abc123"/>
    <id>https://github.com/koreader/koreader/commit/abc123</id>
    <updated>2023-05-15T12:00:00Z</updated>
    <content type="html">
      &lt;pre&gt;This commit fixes the PDF rendering issue on eInk screens&lt;/pre&gt;
    </content>
  </entry>
  <entry>
    <title type="html">Improve EPUB &amp; FB2 support</title>
    <link href="https://github.com/koreader/koreader/commit/def456"/>
    <id>https://github.com/koreader/koreader/commit/def456</id>
    <updated>2023-05-14T10:30:00Z</updated>
    <content type="html">
      &lt;pre&gt;Add better support for EPUB and FB2 formats&lt;/pre&gt;
    </content>
  </entry>
</feed>
]]

        it("should parse Atom feed titles correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(atom_xml)
            assert.truthy(feeds)
            assert.truthy(feeds.feed)
            assert.truthy(feeds.feed.title)
            assert.equals("KOReader GitHub Commits", NewsDownloader.getFeedTitle(feeds.feed.title))

            -- Test entry titles
            assert.truthy(feeds.feed.entry)
            assert.equals("Fix PDF rendering issue", NewsDownloader.getFeedTitle(feeds.feed.entry[1].title))

            -- Test HTML entities in titles
            assert.equals("Improve EPUB & FB2 support",
                          NewsDownloader.getFeedTitle(feeds.feed.entry[2].title))
        end)

        it("should parse Atom feed content correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(atom_xml)
            assert.truthy(feeds)

            -- Test entry content
            local expected_content1 = "<pre>This commit fixes the PDF rendering issue on eInk screens</pre>"
            assert.equals(expected_content1,
                         require("util").htmlEntitiesToUtf8(feeds.feed.entry[1].content[1]))

            local expected_content2 = "<pre>Add better support for EPUB and FB2 formats</pre>"
            assert.equals(expected_content2,
                         require("util").htmlEntitiesToUtf8(feeds.feed.entry[2].content[1]))
        end)

        it("should parse Atom feed links correctly", function()
            local feeds = NewsDownloader:deserializeXMLString(atom_xml)
            assert.truthy(feeds)

            -- Test feed link (with attributes)
            assert.equals("https://github.com/koreader/koreader/commits/master.atom",
                          NewsDownloader.getFeedLink(feeds.feed.link))

            -- Test entry links
            assert.equals("https://github.com/koreader/koreader/commit/abc123",
                          NewsDownloader.getFeedLink(feeds.feed.entry[1].link))
            assert.equals("https://github.com/koreader/koreader/commit/def456",
                          NewsDownloader.getFeedLink(feeds.feed.entry[2].link))
        end)
    end)

    describe("Special case handling", function()
        it("should handle single-item RSS feeds properly", function()
            local single_item_rss = [[
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
  <title>Single Item Feed</title>
  <item>
    <title>The Only Item</title>
    <link>https://example.com/only</link>
    <description>This is the only item in the feed</description>
  </item>
</channel>
</rss>
]]
            local feeds = NewsDownloader:deserializeXMLString(single_item_rss)
            assert.truthy(feeds)
            assert.equals("Single Item Feed", feeds.rss.channel.title)

            -- The plugin should normalize single items
            local processed = false
            -- Mock necessary functions to avoid creating files and whatnot
            local old_createFromDescription = NewsDownloader.createFromDescription
            NewsDownloader.createFromDescription = function(self, feed, title, desc, dir, img, msg)
                assert.equals("The Only Item", title)
                assert.equals("This is the only item in the feed", desc)
                processed = true
            end

            NewsDownloader:processFeed("rss", feeds, nil, nil, 1, false, false, "Testing", true, nil)

            assert.is_true(processed)

            NewsDownloader.createFromDescription = old_createFromDescription
        end)
        it("should handle single-item Atom feeds properly", function()
            local single_item_atom = [[
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Single Item Atom Feed</title>
  <link href="https://example.com/atom-feed"/>
  <updated>2023-06-15T09:00:00Z</updated>
  <author>
    <name>KOReader Team</name>
  </author>
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <entry>
    <title>The Only Atom Entry</title>
    <link href="https://example.com/only-entry"/>
    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
    <updated>2023-06-15T09:00:00Z</updated>
    <summary>This is the only entry in this Atom feed</summary>
    <content type="html">
      &lt;p&gt;This is the complete content of the only entry in this Atom feed&lt;/p&gt;
    </content>
  </entry>
</feed>
]]
            local feeds = NewsDownloader:deserializeXMLString(single_item_atom)
            assert.truthy(feeds)
            assert.equals("Single Item Atom Feed", feeds.feed.title)

            -- The plugin should normalize single items
            local processed = false
            -- Mock necessary functions to avoid creating files and whatnot
            local old_createFromDescription = NewsDownloader.createFromDescription
            NewsDownloader.createFromDescription = function(self, feed, title, desc, dir, img, msg)
                assert.equals("The Only Atom Entry", title)
                assert.equals("<p>This is the complete content of the only entry in this Atom feed</p>", desc)
                processed = true
            end

            NewsDownloader:processFeed("atom", feeds, nil, nil, 1, false, false, "Testing", true, nil)

            assert.is_true(processed)

            NewsDownloader.createFromDescription = old_createFromDescription
        end)
    end)

    describe("parseMaxAge", function()
        local parseMaxAge

        setup(function()
            parseMaxAge = NewsDownloader._parseMaxAge
            assert.is_function(parseMaxAge)
        end)

        it("returns (nil, nil) for nil (disabled)", function()
            local s, err = parseMaxAge(nil)
            assert.is_nil(s)
            assert.is_nil(err)
        end)

        it("returns (nil, nil) for empty string (disabled)", function()
            local s, err = parseMaxAge("")
            assert.is_nil(s)
            assert.is_nil(err)
        end)

        it("parses seconds", function()
            assert.equals(1, parseMaxAge("1s"))
        end)

        it("parses minutes (lowercase m)", function()
            assert.equals(1800, parseMaxAge("30m"))
        end)

        it("parses hours", function()
            assert.equals(43200, parseMaxAge("12h"))
        end)

        it("parses days", function()
            assert.equals(604800, parseMaxAge("7d"))
        end)

        it("parses weeks", function()
            assert.equals(1209600, parseMaxAge("2w"))
        end)

        it("parses months (uppercase M, 30d)", function()
            assert.equals(2592000, parseMaxAge("1M"))
        end)

        it("parses years (365d)", function()
            assert.equals(31536000, parseMaxAge("1y"))
        end)

        it("rejects bare number", function()
            local s, err = parseMaxAge("7")
            assert.is_nil(s)
            assert.is_string(err)
        end)

        it("rejects 7days", function()
            local s, err = parseMaxAge("7days")
            assert.is_nil(s)
            assert.is_string(err)
        end)

        it("rejects uppercase D (case-sensitive)", function()
            local s, err = parseMaxAge("7D")
            assert.is_nil(s)
            assert.is_string(err)
        end)

        it("rejects negative duration", function()
            local s, err = parseMaxAge("-1d")
            assert.is_nil(s)
            assert.is_string(err)
        end)

        it("rejects pure garbage", function()
            local s, err = parseMaxAge("abc")
            assert.is_nil(s)
            assert.is_string(err)
        end)

        it("rejects non-string types", function()
            local s, err = parseMaxAge(7)
            assert.is_nil(s)
            assert.is_string(err)
        end)
    end)

    describe("getFeedItemTimestamp", function()
        local getFeedItemTimestamp

        setup(function()
            getFeedItemTimestamp = NewsDownloader._getFeedItemTimestamp
            assert.is_function(getFeedItemTimestamp)
        end)

        it("parses RSS pubDate", function()
            local ts = getFeedItemTimestamp({ pubDate = "Mon, 01 Jan 2024 00:00:00 GMT" })
            assert.is_number(ts)
        end)

        it("parses Atom updated", function()
            local ts = getFeedItemTimestamp({ updated = "2024-01-01T00:00:00Z" })
            assert.is_number(ts)
        end)

        it("parses Atom published", function()
            local ts = getFeedItemTimestamp({ published = "2024-01-01T00:00:00Z" })
            assert.is_number(ts)
        end)

        it("returns nil when no date fields present", function()
            assert.is_nil(getFeedItemTimestamp({ title = "no date here" }))
        end)

        it("returns nil for unparseable date string", function()
            assert.is_nil(getFeedItemTimestamp({ pubDate = "not a date" }))
        end)

        it("prefers updated over pubDate and published", function()
            local ts = getFeedItemTimestamp({
                updated = "2024-01-01T00:00:00Z",
                pubDate = "garbage",
                published = "garbage",
            })
            assert.is_number(ts)
        end)
    end)

    describe("getFeedItemTimestamp publisher quirk", function()
        local getFeedItemTimestamp

        setup(function()
            getFeedItemTimestamp = NewsDownloader._getFeedItemTimestamp
        end)

        it("returns nil for an item missing all date fields, so the for-loop processes it without filtering", function()
            -- The for-loop in processFeed treats `ts == nil` as "no age check"
            -- once the first-item probe has succeeded. This test locks in the
            -- nil contract that the loop relies on.
            assert.is_nil(getFeedItemTimestamp({ title = "x", link = "y" }))
        end)
    end)
end)
