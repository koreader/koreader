return {
	-- list your feeds here:
	-- only supports http URL for now
    { "http://www.pcworld.com/index.rss", limit = 1 },
    { "http://feeds.reuters.com/Reuters/worldNews?format=xml", limit = 2},
	-- set limit to "0" means no download, "-1" no limit.
    { "http://www.football.co.uk/international/rss.xml", limit = 0 },
}
