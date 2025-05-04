local DataStorage = require("datastorage")
local json = require("json")
local logger = require("logger")
local SQ3 = require("lua-ljsqlite3/init")

local function getBookAuthor(book_json)
    local contributors = book_json["ContributorRoles"]

    local authors = {}
    for _, contributor in ipairs(contributors) do
        local role = contributor["Role"]
        if role == "Author" then
            local name = contributor["Name"]
            if name ~= nil then
                table.insert(authors, contributor["Name"])
            end
        end
    end

    -- Unfortunately the role field is not filled out in the data returned by the "library_sync" endpoint, so we only
    -- use the first author and hope for the best. Otherwise we would get non-main authors too. For example Christopher
    -- Buckley beside Joseph Heller for the -- terrible -- novel Catch-22.
    if #authors == 0 and #contributors > 0 then
        local name = contributors[1]["Name"]
        if name ~= nil then
            table.insert(authors, name)
        end
    end

    return table.concat(authors, " & ")
end

local function getReadingState(reading_state_json)
    local book_read = 0
    local last_time_finished = nil
    local status_info = reading_state_json["StatusInfo"]
    if status_info ~= nil and status_info["Status"] == "Finished" then
        book_read = 1
        last_time_finished = status_info["LastTimeFinished"]
    end
    return book_read, last_time_finished
end

local function synchronizeBooksInDatabaseNewEntitlement(new_entitlement, statement)
    local book_entitlement = new_entitlement["BookEntitlement"]
    if book_entitlement == nil then
        if new_entitlement["AudiobookEntitlement"] == nil then
            logger.warn("KoboDb: missing BookEntitlement from JSON: ", json.encode(new_entitlement))
        end
        return
    end

    local entitlement_id = book_entitlement["Id"]
    if entitlement_id == nil or #entitlement_id == 0 then
        logger.warn("KoboDb: missing EntitlementId from JSON: ", json.encode(new_entitlement))
        return
    end

    local book_metadata = new_entitlement["BookMetadata"]
    if book_metadata == nil then
        logger.warn("KoboDb: missing BookMetadata from JSON: ", json.encode(new_entitlement))
        return
    end

    local title = book_metadata["Title"]
    if title == nil or #title == 0 then
        logger.warn("KoboDb: missing Title from JSON: ", json.encode(new_entitlement))
        return
    end

    local reading_state = new_entitlement["ReadingState"]
    local reading_state_json_text = ""
    local book_read = 0
    local last_time_finished = nil
    if reading_state ~= nil then
        reading_state_json_text = json.encode(reading_state)
        book_read, last_time_finished = getReadingState(reading_state)
    end

    local archived = 0
    if book_entitlement["IsRemoved"] then
        if book_entitlement["IsHiddenFromArchive"] then
            archived = 2
        else
            archived = 1
        end
    end

    local book_entitlement_json_text = json.encode(book_entitlement)
    local book_metadata_json_text = json.encode(book_metadata)

    if entitlement_id ~= nil and #entitlement_id > 0 and title ~= nil and #title > 0 then
		local author = getBookAuthor(book_metadata)
        statement:reset():bind(entitlement_id, book_entitlement_json_text, reading_state_json_text, book_metadata_json_text, title, author, archived, book_read, last_time_finished):step()
    end
end

local function synchronizeBooksInDatabaseChangedEntitlement(changed_entitlement, statement)
    local book_entitlement = changed_entitlement["BookEntitlement"]
    if book_entitlement == nil then
        if changed_entitlement["AudiobookEntitlement"] == nil then
            logger.warn("KoboDb: missing BookEntitlement from JSON: ", json.encode(changed_entitlement))
        end
        return
    end

    local entitlement_id = book_entitlement["Id"]
    if entitlement_id == nil or #entitlement_id == 0 then
        logger.warn("KoboDb: missing Id from JSON: ", json.encode(changed_entitlement))
        return
    end

    -- TODO: Kobo: when a book gets unarchived then its reading state remains stuck as finished. There is no
    -- ChangedReadingState in library_sync item...
    local archived = 0
    if book_entitlement["IsRemoved"] then
        if book_entitlement["IsHiddenFromArchive"] then
            archived = 2
        else
            archived = 1
        end
    end

    local book_entitlement_json_text = json.encode(book_entitlement)
    statement:reset():bind(book_entitlement_json_text, archived, entitlement_id):step()
end

local function synchronizeBooksInDatabaseChangedReadingState(changed_reading_state, statement)
    local reading_state = changed_reading_state["ReadingState"]
    if reading_state == nil then
        logger.warn("KoboDb: missing ReadingState from JSON: ", json.encode(changed_reading_state))
        return
    end

    local entitlement_id = reading_state["EntitlementId"]
    if entitlement_id == nil or #entitlement_id == 0 then
        logger.warn("KoboDb: missing EntitlementId from JSON: ", json.encode(changed_reading_state))
        return
    end

    local reading_state_json_text = json.encode(reading_state)
    local book_read, last_time_finished = getReadingState(reading_state)
    statement:reset():bind(reading_state_json_text, book_read, last_time_finished, entitlement_id):step()
end

local function synchronizeBooksInDatabaseChangedProductMetadata(changed_product_metadata, statement)
    local book_metadata = changed_product_metadata["BookMetadata"]
    if book_metadata == nil then
        logger.warn("KoboDb: missing BookMetadata from JSON: ", json.encode(changed_product_metadata))
        return
    end

    local entitlement_id = book_metadata["EntitlementId"]
    if entitlement_id == nil or #entitlement_id == 0 then
        logger.warn("KoboDb: missing EntitlementId from JSON: ", json.encode(changed_product_metadata))
        return
    end

    local title = book_metadata["Title"]
    if title == nil or #title == 0 then
        logger.warn("KoboDb: missing Title from JSON: ", json.encode(changed_product_metadata))
        return
    end

    local author = getBookAuthor(book_metadata)
    local book_metadata_json_text = json.encode(book_metadata)
    statement:reset():bind(book_metadata_json_text, title, author, entitlement_id):step()
end

local function synchronizeBooksInDatabaseDeletedEntitlement(deleted_entitlement, statement)
    local entitlement_id = deleted_entitlement["EntitlementId"]
    if entitlement_id == nil or #entitlement_id == 0 then
        logger.warn("KoboDb: missing EntitlementId from JSON: ", json.encode(deleted_entitlement))
        return
    end

    statement:reset():bind(entitlement_id):step()
end

local function refreshWishlistInDatabaseNewItem(item, statement)
    local product_metadata = item["ProductMetadata"]
    if product_metadata == nil then
        logger.warn("KoboDb: missing ProductMetadata from JSON: ", json.encode(item))
        return
    end

    local book = product_metadata["Book"]
    if book == nil then
        logger.warn("KoboDb: missing Book from JSON: ", json.encode(item))
        return
    end

    local cross_revision_id = book["CrossRevisionId"]
    if cross_revision_id == nil or #cross_revision_id == 0 then
        logger.warn("KoboDb: missing CrossRevisionId from JSON: ", json.encode(item))
        return
    end

    local title = book["Title"]
    if title == nil or #title == 0 then
        logger.warn("KoboDb: missing Title from JSON: ", json.encode(item))
        return
    end

    local author = getBookAuthor(book)
    local item_json_text = json.encode(item)
    local date_added = item["DateAdded"]
    statement:reset():bind(cross_revision_id, item_json_text, title, author, date_added):step()
end

local function addDownloadInfo(download_info_list, json_source, format, platform, display_format, file_extension)
    for _, json_item in ipairs(json_source) do
        if json_item["Format"] == format and json_item["Platform"] == platform then
            local url = json_item["Url"]
            if url ~= nil and #url > 0 then
                local download_item = {
                    url = url,
                    display_format = display_format,
                    file_extension = file_extension,
                }
                table.insert(download_info_list, download_item)
                return true
            end
        end
    end

    return false
end

local KoboDb = {
	db = nil,
	db_path =  DataStorage:getDataDir() .. "/cache/kobo-store.sqlite",
}

function KoboDb:openDb()
	if self.db ~= nil then
		return
	end

    self.db = SQ3.open(self.db_path)

    self.db:exec([[
        CREATE TABLE IF NOT EXISTS "books" (
            "entitlement_id"	TEXT NOT NULL UNIQUE COLLATE NOCASE,
            "book_entitlement_json"	TEXT NOT NULL,
            "reading_state_json"	TEXT NOT NULL,
            "book_metadata_json"	TEXT NOT NULL,
            "title"	TEXT NOT NULL,
            "author"	TEXT NOT NULL,
            "archived"	INTEGER NOT NULL,
            "read"	INTEGER NOT NULL,
            "last_time_finished"	TEXT,
            PRIMARY KEY("entitlement_id")
        );

        CREATE TABLE IF NOT EXISTS "settings" (
            "key"	TEXT NOT NULL UNIQUE,
            "value"	TEXT NOT NULL,
            PRIMARY KEY("key")
        );

        CREATE TABLE IF NOT EXISTS "wishlist" (
            "cross_revision_id"	TEXT NOT NULL UNIQUE COLLATE NOCASE,
            "item_json"	TEXT NOT NULL,
            "title"	TEXT NOT NULL,
            "author"	TEXT NOT NULL,
            "date_added"	TEXT,
            PRIMARY KEY("cross_revision_id")
        );
    ]]);
end

function KoboDb:closeDb()
	if self.db == nil then
		return
	end

	self.db:close()
	self.db = nil
end

function KoboDb:loadApiSettings()
	local api_settings = {}
    local db_items = self.db:exec([[
		SELECT key, value
		FROM settings
		WHERE KEY IN ('access_token', 'device_id', 'refresh_token', 'serial_number', 'user_id', 'user_key', 'library_sync_token');
	]])

    if db_items ~= nil then
        for i, key in ipairs(db_items.key) do
            api_settings[key] = db_items.value[i]
        end
    end

	return api_settings
end

function KoboDb:saveApiSettings(new_api_settings)
	local old_api_settings = self:loadApiSettings()
    local statement = self.db:prepare([[
        INSERT OR REPLACE INTO settings
            (key, value)
        VALUES (?, ?);
    ]])

	for key in pairs(new_api_settings) do
		if new_api_settings[key] ~= old_api_settings[key] then
			local value = new_api_settings[key]
            statement:reset():bind(key, value):step()
		end
	end

    statement:close()
end

function KoboDb:getBookInfo(entitlement_id)
    local statement = self.db:prepare([[
        SELECT title, author, archived, read, last_time_finished, book_metadata_json
        FROM books
        WHERE entitlement_id = ?;
    ]])

    local db_result = statement:reset():bind(entitlement_id):step()
    statement:close()

    local title = db_result[1]
    local author = db_result[2]
    local archived = db_result[3]
    local read = db_result[4]
    local last_time_finished = db_result[5] or ""
    local _, book_metadata_json = pcall(json.decode, db_result[6])

    local description = book_metadata_json["Description"] or ""
    local isbn = book_metadata_json["Isbn"] or ""
    local language = book_metadata_json["Language"] or ""
    local publication_date = book_metadata_json["PublicationDate"] or ""

    local download_info_list = {}
    local json_download_urls = book_metadata_json["DownloadUrls"]
    if json_download_urls ~= nil then
        if not addDownloadInfo(download_info_list, json_download_urls, "EPUB3", "Generic", "EPUB 3", "epub") then
            addDownloadInfo(download_info_list, json_download_urls, "KEPUB", "Android", "KEPUB", "epub")
        end
    end

    local publisher_name = ""
    local publisher_imprint = ""
    if book_metadata_json["Publisher"] ~= nil then
        publisher_name = book_metadata_json["Publisher"]["Name"] or ""
        publisher_imprint = book_metadata_json["Publisher"]["Imprint"] or ""
    end

    local series_name = ""
    local series_number = ""
    if book_metadata_json["Series"] ~= nil then
        series_name = book_metadata_json["Series"]["Name"] or ""
        series_number = book_metadata_json["Series"]["Number"] or ""
    end

    if archived ~= 0 then
        -- Downloading does not work for archived books.
        download_info_list = {}

        -- These are set in the StatusInfo but not valid if the book is archived.
        read = 0
        last_time_finished = ""
    end

    local book_info = {
        archived = archived,
        author = author,
        date_added_to_wishlist = "", -- to make it compatible with getWishlistItemInfo
        description = description,
        download_info_list = download_info_list,
        isbn = isbn,
        language = language,
        last_time_finished_reading = last_time_finished,
        publication_date = publication_date,
        publisher_name = publisher_name,
        publisher_imprint = publisher_imprint,
        read = read, -- 0 or 1
        series_name = series_name,
        series_number = series_number, -- text
        title = title,
    }

    return book_info
end

function KoboDb:getWishlistItemInfo(cross_revision_id)
    local statement = self.db:prepare([[
        SELECT title, author, date_added, item_json
        FROM wishlist
        WHERE cross_revision_id = ?;
    ]])

    local db_result = statement:reset():bind(cross_revision_id):step()
    statement:close()

    local title = db_result[1]
    local author = db_result[2]
    local date_added = db_result[3] or ""
    local _, item_json = pcall(json.decode, db_result[4])

    local product_metadata = item_json["ProductMetadata"] or {}
    local book = product_metadata["Book"] or {}
    local description = book["Description"] or ""
    local isbn = book["ISBN"] or ""
    local language = book["Language"] or ""
    local publication_date = book["PublicationDate"] or ""

    local download_info_list = {}
    local json_download_urls = book["RedirectPreviewUrls"]
    if json_download_urls ~= nil then
        if not addDownloadInfo(download_info_list, json_download_urls, "EPUB3_SAMPLE", "Generic", "Sample EPUB 3", "epub") then
            addDownloadInfo(download_info_list, json_download_urls, "EPUB_SAMPLE", "Android", "Sample EPUB", "epub")
        end
    end

    local publisher_name = book["PublisherName"] or ""
    local series_name = book["SeriesName"] or ""
    local series_number = book["SeriesNumber"] or ""

    local book_info = {
        author = author,
        date_added_to_wishlist = date_added,
        description = description,
        download_info_list = download_info_list,
        isbn = isbn,
        language = language,
        last_time_finished_reading = "", -- to make it compatible with getBookInfo
        publication_date = publication_date,
        publisher_name = publisher_name,
        publisher_imprint = "", -- to make it compatible with getBookInfo
        read = 0, -- to make it compatible with getBookInfo
        series_name = series_name,
        series_number = series_number, -- text
        title = title,
    }

    return book_info
end

function KoboDb:getBooks(include_read, include_unread, include_archived)
    -- NOTE: archived = 2 means hidden
	local where = "WHERE archived = 0"
    if include_archived then
        where = "WHERE archived = 1"
	elseif include_read and not include_unread then
		where = "WHERE read = 1 AND archived = 0"
	elseif not include_read and include_unread then
		where = "WHERE read = 0 AND archived = 0"
	elseif not include_read and not include_unread then
		return {}
	end

    local books = {}
    local db_books = self.db:exec(string.format("SELECT entitlement_id, title, author, read FROM books %s;", where))
    if db_books ~= nil then
        for i, entitlement_id in ipairs(db_books.entitlement_id) do
            local book = {
                entitlement_id = entitlement_id,
                title = db_books.title[i],
                author = db_books.author[i]
            }
            table.insert(books, book)
        end
    end

    return books
end

function KoboDb:getWishlist()
    local items = {}
    local db_items = self.db:exec("SELECT cross_revision_id, title, author FROM wishlist;")
    if db_items ~= nil then
        for i, cross_revision_id in ipairs(db_items.cross_revision_id) do
            local item = {
                cross_revision_id = cross_revision_id,
                title = db_items.title[i],
                author = db_items.author[i]
            }
            table.insert(items, item)
        end
    end

    return items
end

function KoboDb:applyLibrarySyncItems(library_sync_items)
    local new_statement = self.db:prepare([[
        INSERT OR REPLACE INTO books
            (entitlement_id, book_entitlement_json, reading_state_json, book_metadata_json, title, author, archived, read, last_time_finished)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ]])

    local change_entitlement_statement = self.db:prepare([[
        UPDATE books
        SET
            book_entitlement_json = ?,
            archived = ?
        WHERE entitlement_id = ?;
    ]])

    local change_reading_state_statement = self.db:prepare([[
        UPDATE books
        SET
            reading_state_json = ?,
            read = ?,
            last_time_finished = ?
        WHERE entitlement_id = ?;
    ]])

    local change_book_metadata_statement = self.db:prepare([[
        UPDATE books
        SET
            book_metadata_json = ?,
            title = ?,
            author = ?
        WHERE entitlement_id = ?;
    ]])

    local deleted_statement = self.db:prepare([[
        DELETE FROM books
        WHERE entitlement_id = ?;
    ]])

    for _, item in ipairs(library_sync_items) do
        if item["NewEntitlement"] ~= nil then
            synchronizeBooksInDatabaseNewEntitlement(item["NewEntitlement"], new_statement)
        elseif item["ChangedEntitlement"] ~= nil then
            synchronizeBooksInDatabaseChangedEntitlement(item["ChangedEntitlement"], change_entitlement_statement)
        elseif item["ChangedReadingState"] ~= nil then
            synchronizeBooksInDatabaseChangedReadingState(item["ChangedReadingState"], change_reading_state_statement)
        elseif item["ChangedProductMetadata"] ~= nil then
            synchronizeBooksInDatabaseChangedProductMetadata(item["ChangedProductMetadata"], change_book_metadata_statement)
        elseif item["DeletedEntitlement"] ~= nil then
            synchronizeBooksInDatabaseDeletedEntitlement(item["DeletedEntitlement"], deleted_statement)
        elseif item["NewTag"] == nil and item["ChangedTag"] == nil then
            -- TODO: Kobo: can NewTag and ChangedTag used to update the wishlist?
            logger.warn("KoboDb: unsupported library sync type: ", json.encode(item))
        end
    end

    new_statement:close()
    change_entitlement_statement:close()
    change_reading_state_statement:close()
    change_book_metadata_statement:close()
    deleted_statement:close()
end

function KoboDb:clearWishlist()
	self.db:exec("DELETE FROM wishlist;")
end

function KoboDb:refreshWishlist(wishlist_items)
    local statement = self.db:prepare([[
        INSERT OR REPLACE INTO wishlist
            (cross_revision_id, item_json, title, author, date_added)
        VALUES (?, ?, ?, ?, ?);
    ]])

    for _, item in ipairs(wishlist_items) do
        refreshWishlistInDatabaseNewItem(item, statement)
    end

    statement:close()
end

return KoboDb
