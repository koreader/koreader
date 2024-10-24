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

 -- 'include_images=true' - means download any images on the page and include them in the article
 -- 'include_images=false' - means ignore any images, only download the text (faster download, smaller file sizes)
 -- default value is 'false' (if no 'include_images' entry)

 -- 'enable_filter=true' - means filter using a CSS selector to delimit part of the page to just that (does not apply if download_full_article=false)
 -- 'enable_filter=false' - means no such filtering and including the full page
 -- default value is 'false'

 -- 'filter_element="name_of_css.element.class" - means to filter the chosen CSS selector, it can be easily picked using a modern web browser
 -- The default value is empty. The default list of common selectors is used as fallback if this value is set.

-- Optional 'credentials' element is used to authenticate on subscription based articles.
-- It is itself comprised of a 'url' strings, that is the url of the connexion form,
-- and an 'auth' table that contains form data used for user authentication {form_key = value, …}.
-- Exampple: credentials={url="https://secure.lemonde.fr/sfuser/connexion", auth={email="titi@gmouil.com", password="xxxx"}}

 -- comment out line ("--" at line start) to stop downloading source


 -- LIST YOUR FEEDS HERE:

 { "https://github.com/koreader/koreader/releases.atom", limit = 3, download_full_article=true, include_images=false, enable_filter=true, filter_element = "div.release-main-section"},
 { "https://ourworldindata.org/atom.xml", limit = 5 , download_full_article=true, include_images=true, enable_filter=false, filter_element = ""},

}--do NOT change this line
