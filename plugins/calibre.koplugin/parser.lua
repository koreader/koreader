-- A parser for metadata.calibre

local lj = require("lunajson")

local field = ""
local wanted = false
local wanted_array = false

local result = {}
local t = {}

local all_fields = {
   "publisher",
   "title_sort",
   "author_sort",
   "link_maps",
   "identifiers",
   "mobi-asin",
   "cover",
   "db_id",
   "book_producer",
   "pubdate",
   "series",
   "thumbnail",
   "lpath",
   "author_sort_map",
   "application_id",
   "series_index",
   "authors",
   "comments",
   "rating",
   "rights",
   "publication_type",
   "mime",
   "languages",
   "size",
   "tags",
   "timestamp",
   "uuid",
   "last_modified",
   "user_categories",
   "user_metadata",
   "title",
}

local used_fields = {
   "uuid",
   "lpath",
   "last_modified",
   "size",
   "title",
   "authors",
   "tags",
   "series",
   "series_index"
}

local function isField(s)
   for _, v in ipairs(all_fields) do
      if s == v then
         field = v
         return true
      end
   end
   return false
end

local function isRequiredField(s)
   for _, v in ipairs(used_fields) do
      if s == v then
         return true
      end
   end
   return false
end

local function isArrayField()
   return field == "authors" or
      field == "tags" or
      field == "series"
end

local function append(s)
   if isField(s) then
      wanted = false
      if isRequiredField(s) then
         wanted = true
      end
   else
      if wanted_array then
         table.insert(t[field], s)
      elseif wanted then
         t[field] = s
         -- this ugly hack assumes fields are always in the same order.
         -- C.f https://www.mobileread.com/forums/showthread.php?t=361567
         if field == all_fields[#all_fields] then
            table.insert(result, t)
            t = {}
         end
      end
   end
end

local saxtbl = {
   startarray = function()
      if isArrayField() then
         wanted_array = true
         t[field] = {}
      end
   end,
   endarray = function()
      if isArrayField() then
         wanted_array = false
      end
   end,
   key = function(s)
      append(s)
   end,
   string = function(s)
      append(s)
   end,
   number = function(n)
      append(n)
   end,
   boolean = function(b)
      append(b)
   end,
   null = function()
      append()
   end,
}

local parser = {}
function parser.parseFile(file)
    result = {}
    local p = lj.newfileparser(file, saxtbl)
    p.run()
    return result
end

return parser
