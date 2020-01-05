return {--do NOT change this line

 --HELP:
 -- use syntax: {"http://your-url.com", limit=max_number_of_items_to_be_created, download_full_article=true/false},

 -- remember to put coma at the end of each line!

 -- you can also edit this file in external text editor. Config file is located under:
 -- <your_download_directory>/feed_config.lua
 -- default: <koreader_dir>/news/feed_config.lua


 -- DETAILS:
 -- set 'limit' to "0" means no limit.

 -- 'download_full_article=true' - means download full article (may not always work correctly)
 -- 'download_full_article=false' - means use only feed description to create feeds (usually only beginning of the article)
 -- default value is 'true' (if no 'download_full_article' entry)

 -- 'include_images=true' - means download any images on the page and inlude them in the article
 -- 'include_images=false' - means ignore any images, only download the text (faster download, smaller file sizes)
 -- default value is 'false' (if no 'include_images' entry)

 -- comment out line ("--" at line start) to stop downloading source


 -- LIST YOUR FEEDS HERE:

 { "http://feeds.reuters.com/Reuters/worldNews?format=xml", limit = 2, download_full_article=true},

 { "https://www.pcworld.com/index.rss", limit = 7 , download_full_article=false},

-- { "http://www.football.co.uk/international/rss.xml", limit = 2},

}--do NOT change this line
