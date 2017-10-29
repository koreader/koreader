return {
	-- list your feeds here:

    { "http://feeds.reuters.com/Reuters/worldNews?format=xml", limit = 2, download_full_article=true},

    { "https://www.pcworld.com/index.rss", limit = 7 , download_full_article=false},

		-- comment out line ("--" at line start) to stop downloading source
    --{ "http://www.football.co.uk/international/rss.xml", limit = 0 , download_full_article=false},







		--HELP:
		-- use syntax: {"your_url", limit= max_number_of_items_to_be_created, download_full_article=true/false}

		-- set 'limit' to change number of 'news' to be created
    -- 'limit' equal "0" means no limit.

		-- 'download_full_article=false' - means download full article using feed link (may not always work correctly)
		-- 'download_full_article=true' - means use only feed description to create feeds (usually only part of the article)


}
