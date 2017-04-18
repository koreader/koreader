return {
	-- list your feeds here:
	-- only supports http URL for now
	-- Atom is currently not supported, only RSS
    { "http://www.pcworld.com/index.rss", limit = 1 },
    { "http://www.economist.com/sections/science-technology/rss.xml", limit = 2},
	-- set limit to "0" means no download, "-1" no limit.
    { "http://www.economist.com/sections/culture/rss.xml", limit = 0 },
}