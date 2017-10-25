return {
	-- list your feeds here:

    { "http://feeds.reuters.com/Reuters/worldNews?format=xml", limit = 2, createNewsFromDescription=false},

    { "https://www.pcworld.com/index.rss", limit = 7 , createNewsFromDescription=true},

		-- comment out line ("--" at line start) to stop downloading source
    --{ "http://www.football.co.uk/international/rss.xml", limit = 0 , createNewsFromDescription=true},







		--HELP:
		-- use syntax: {"your_url", limit= max_number_of_items_to_be_created, createNewsFromDescription=true/false}

		-- set 'limit' to change number of 'news' to be created
    -- 'limit' equal "0" means no limit.

		-- 'createNewsFromDescription=false' - means download full article using feed link (may not always work correctly)
		-- 'createNewsFromDescription=true' - means use only feed description to create feeds (usually only part of the article)


}
