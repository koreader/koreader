---@module Handler to generate a simple event trace which 
--outputs messages to the terminal during the XML
--parsing, usually for debugging purposes.
--
--  License:
--  ========
--
--      This code is freely distributable under the terms of the [MIT license](LICENSE).
--
--@author Paul Chakravarti (paulc@passtheaardvark.com)
--@author Manoel Campos da Silva Filho
local print = {}

---Parses a start tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:starttag(tag, s, e) 
    io.write("Start    : "..tag.name.."\n") 
    if tag.attrs then 
        for k,v in pairs(tag.attrs) do 
            io.write(string.format(" + %s='%s'\n", k, v))
        end 
    end
end

---Parses an end tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:endtag(tag, s, e) 
    io.write("End      : "..tag.name.."\n") 
end

---Parses a tag content.
-- @param text text to process
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:text(text, s, e)
    io.write("Text     : "..text.."\n") 
end

---Parses CDATA tag content.
-- @param text CDATA content to be processed
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:cdata(text, s, e)
    io.write("CDATA    : "..text.."\n") 
end

---Parses a comment tag.
-- @param text comment text
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:comment(text, s, e)
    io.write("Comment  : "..text.."\n") 
end

---Parses a DTD tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:dtd(tag, s, e)     
    io.write("DTD      : "..tag.name.."\n") 
    if tag.attrs then 
        for k,v in pairs(tag.attrs) do 
            io.write(string.format(" + %s='%s'\n", k, v))
        end 
    end
end

--- Parse a XML processing instructions (PI) tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:pi(tag, s, e) 
    io.write("PI       : "..tag.name.."\n")
    if tag.attrs then 
        for k,v in pairs(tag.attrs) do 
            io. write(string.format(" + %s='%s'\n",k,v))
        end 
    end
end

---Parse the XML declaration line (the line that indicates the XML version).
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
-- @param s position where the tag starts
-- @param e position where the tag ends
function print:decl(tag, s, e) 
    io.write("XML Decl : "..tag.name.."\n")
    if tag.attrs then 
        for k,v in pairs(tag.attrs) do 
            io.write(string.format(" + %s='%s'\n", k, v))
        end 
    end
end

return print
