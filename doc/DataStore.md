Data Store
==========

## LuaSettings ##

TODO


## DocSettings ##

TODO


## SQLite3 ##

KOReader ships with the SQLite3 library, which is a great embedded database for
desktop and mobile applications.

[lua-ljsqlite3][ljsq3] is used to export SQLite3 C interfaces as LUA functions.
Following is a quick example:

```lua
local SQ3 = require("lua-ljsqlite3/init")

local conn = SQ3.open("/path/to/database.sqlite3")

-- Execute SQL commands separated by the ';' character:
conn:exec([[
-- time is in unit of seconds
CREATE TABLE IF NOT EXISTS page_read_time(page INTEGER, time INTEGER);
CREATE TABLE IF NOT EXISTS book_property(title TEXT, author TEXT, language TEXT);
]])

-- Prepared statements are supported, with this you can bind different values
-- to the same statement. Let's set the read time for the first 10 pages in the
-- book to 5 seconds
local stmt = conn:prepare("INSERT INTO page_read_time VALUES(?, ?)")
for i=1,10 do
  stmt:reset():bind(i, 5):step()
end

-- Now we can retrieve all read time stats for the first 10 pages:
local results = conn:exec("SELECT * FROM page_read_time") -- Records are by column.
-- Access to results via column numbers or names:
assert(results[1] == results.page)
assert(results[2] == results.time)
-- Nested indexing corresponds to the record(row) number, access value for 4th page:
assert(results[1][4] == 4)
assert(results[2][4] == 5)
-- access value for 2nd page:
assert(results.page[2] == 2)
assert(results.time[2] == 5)

-- Convenience function returns multiple values for one record:
local page, time = conn:rowexec("SELECT * FROM page_read_time WHERE page==3")
print(page, time) --> 3 5

-- We can also use builtin aggregate functions to do simple analytic task
local total_time = conn:rowexec("SELECT SUM(time) FROM page_read_time")
print(total_time) --> 50

conn:close() -- Do not forget to close stmt after you are done
```

For more information on supported SQL queries, check out [SQLite3's official
documentation][sq3-doc].


[ljsq3]:http://scilua.org/ljsqlite3.html
[sq3-doc]:https://www.sqlite.org/docs.html
