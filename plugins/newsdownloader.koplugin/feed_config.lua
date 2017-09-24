return {
	-- list your feeds here:

	-- only supports http URL for now

    { "http://feeds.reuters.com/Reuters/worldNews?format=xml", limit = 2},
    -- set 'limit' to change number of 'news' to be downloaded from source
    -- 'limit' equal "0" means no limit.
    { "http://www.pcworld.com/index.rss", limit = 1 },

    -- comment out line to stop downloading source
    --{ "http://www.football.co.uk/international/rss.xml", limit = 0 },
}
