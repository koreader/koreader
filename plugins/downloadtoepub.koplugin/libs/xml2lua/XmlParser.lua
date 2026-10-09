--- @module Class providing the actual XML parser.
--  Available options are:
--      * stripWS   
--        Strip non-significant whitespace (leading/trailing) 
--        and do not generate events for empty text elements
--  
--      * expandEntities 
--        Expand entities (standard entities + single char 
--        numeric entities only currently - could be extended 
--        at runtime if suitable DTD parser added elements
--        to table (see obj._ENTITIES). May also be possible
--        to expand multibyre entities for UTF-8 only
--  
--      * errorHandler
--        Custom error handler function 
--
--  NOTE: Boolean options must be set to 'nil' not '0'

---Converts the decimal code of a character to its corresponding char
--if it's a graphical char, otherwise, returns the HTML ISO code
--for that decimal value in the format &#code
--@param code the decimal value to convert to its respective character
local function decimalToHtmlChar(code)
    local num = tonumber(code)
    if num >= 0 and num < 256 then
        return string.char(num)
    end

    return "&#"..code..";"
end

---Converts the hexadecimal code of a character to its corresponding char
--if it's a graphical char, otherwise, returns the HTML ISO code
--for that hexadecimal value in the format &#xCode
--@param code the hexadecimal value to convert to its respective character
local function hexadecimalToHtmlChar(code)
    local num = tonumber(code, 16)
    if num >= 0 and num < 256 then
        return string.char(num)
    end

    return "&#x"..code..";"
end

local XmlParser = {
    -- Private attribures/functions
    _XML        = '^([^<]*)<(%/?)([^>]-)(%/?)>',
    _ATTR1      = '([%w-:_]+)%s*=%s*"(.-)"',
    _ATTR2      = '([%w-:_]+)%s*=%s*\'(.-)\'',
    _CDATA      = '<%!%[CDATA%[(.-)%]%]>',
    _PI         = '<%?(.-)%?>',
    _COMMENT    = '<!%-%-(.-)%-%->',
    _TAG        = '^(.-)%s.*',
    _LEADINGWS  = '^%s+',
    _TRAILINGWS = '%s+$',
    _WS         = '^%s*$',
    _DTD1       = '<!DOCTYPE%s+(.-)%s+(SYSTEM)%s+["\'](.-)["\']%s*(%b[])%s*>',
    _DTD2       = '<!DOCTYPE%s+(.-)%s+(PUBLIC)%s+["\'](.-)["\']%s+["\'](.-)["\']%s*(%b[])%s*>',
    --_DTD3       = '<!DOCTYPE%s+(.-)%s*(%b[])%s*>',
    _DTD3       = '<!DOCTYPE%s.->',
    _DTD4       = '<!DOCTYPE%s+(.-)%s+(SYSTEM)%s+["\'](.-)["\']%s*>',
    _DTD5       = '<!DOCTYPE%s+(.-)%s+(PUBLIC)%s+["\'](.-)["\']%s+["\'](.-)["\']%s*>',

    --Matches an attribute with non-closing double quotes (The equal sign is matched non-greedly by using =+?)
    _ATTRERR1   = '=+?%s*"[^"]*$',
    --Matches an attribute with non-closing single quotes (The equal sign is matched non-greedly by using =+?)
    _ATTRERR2   = '=+?%s*\'[^\']*$',
    --Matches a closing tag such as </person> or the end of a openning tag such as <person>
    _TAGEXT     = '(%/?)>',

    _errstr = { 
        xmlErr = "Error Parsing XML",
        declErr = "Error Parsing XMLDecl",
        declStartErr = "XMLDecl not at start of document",
        declAttrErr = "Invalid XMLDecl attributes",
        piErr = "Error Parsing Processing Instruction",
        commentErr = "Error Parsing Comment",
        cdataErr = "Error Parsing CDATA",
        dtdErr = "Error Parsing DTD",
        endTagErr = "End Tag Attributes Invalid",
        unmatchedTagErr = "Unbalanced Tag",
        incompleteXmlErr = "Incomplete XML Document",
    },

    _ENTITIES = { 
        ["&lt;"] = "<",
        ["&gt;"] = ">",
        ["&amp;"] = "&",
        ["&quot;"] = '"',
        ["&apos;"] = "'",
        ["&#(%d+);"] = decimalToHtmlChar,
        ["&#x(%x+);"] = hexadecimalToHtmlChar,
    },
}

--- Instantiates a XmlParser object.
--@param _handler Handler module to be used to convert the XML string
--               to another formats. See the available handlers at the handler directory.
--               Usually you get an instance to a handler module using, for instance:
--               local handler = require("xmlhandler/tree").
--@param _options Options for this XmlParser instance.
--@see XmlParser.options
function XmlParser.new(_handler, _options)
    local obj = {
        handler = _handler,
        options = _options,
        _stack  = {}
    }

    setmetatable(obj, XmlParser)
    obj.__index = XmlParser
    return obj;
end

---Checks if a function/field exists in a table or in its metatable
--@param table the table to check if it has a given function
--@param elementName the name of the function/field to check if exists
--@return true if the function/field exists, false otherwise
local function fexists(table, elementName)
    if table == nil then
        return false
    end

    if table[elementName] == nil then
        return fexists(getmetatable(table), elementName)
    else
        return true
    end
end

local function err(self, errMsg, pos)
    if self.options.errorHandler then
        self.options.errorHandler(errMsg,pos)
    end
end

--- Removes whitespaces
local function stripWS(self, s)
    if self.options.stripWS then
        s = string.gsub(s,'^%s+','')
        s = string.gsub(s,'%s+$','')
    end
    return s
end

local function parseEntities(self, s) 
    if self.options.expandEntities then
        for k,v in pairs(self._ENTITIES) do
            s = string.gsub(s,k,v)
        end
    end

    return s
end

--- Parses a string representing a tag.
--@param s String containing tag text
--@return a {name, attrs} table
-- where name is the name of the tag and attrs 
-- is a table containing the atributtes of the tag
local function parseTag(self, s)
    local tag = {
            name = string.gsub(s, self._TAG, '%1'),
            attrs = {}
          }            

    local parseFunction = function (k, v) 
            tag.attrs[k] = parseEntities(self, v)
            tag.attrs._ = 1 
          end
                          
    string.gsub(s, self._ATTR1, parseFunction) 
    string.gsub(s, self._ATTR2, parseFunction)

    if tag.attrs._ then
        tag.attrs._ = nil
    else 
        tag.attrs = nil
    end

    return tag
end

local function parseXmlDeclaration(self, xml, f)
    -- XML Declaration
    f.match, f.endMatch, f.text = string.find(xml, self._PI, f.pos)
    if not f.match then 
        err(self, self._errstr.declErr, f.pos)
    end 

    if f.match ~= 1 then
        -- Must be at start of doc if present
        err(self, self._errstr.declStartErr, f.pos)
    end

    local tag = parseTag(self, f.text) 
    -- TODO: Check if attributes are valid
    -- Check for version (mandatory)
    if tag.attrs and tag.attrs.version == nil then
        err(self, self._errstr.declAttrErr, f.pos)
    end

    if fexists(self.handler, 'decl') then 
        self.handler:decl(tag, f.match, f.endMatch)
    end    

    return tag
end

local function parseXmlProcessingInstruction(self, xml, f)
    local tag = {}

    -- XML Processing Instruction (PI)
    f.match, f.endMatch, f.text = string.find(xml, self._PI, f.pos)
    if not f.match then 
        err(self, self._errstr.piErr, f.pos)
    end 
    if fexists(self.handler, 'pi') then 
        -- Parse PI attributes & text
        tag = parseTag(self, f.text) 
        local pi = string.sub(f.text, string.len(tag.name)+1)
        if pi ~= "" then
            if tag.attrs then
                tag.attrs._text = pi
            else
                tag.attrs = { _text = pi }
            end
        end
        self.handler:pi(tag, f.match, f.endMatch) 
    end

    return tag
end

local function parseComment(self, xml, f)
    f.match, f.endMatch, f.text = string.find(xml, self._COMMENT, f.pos)
    if not f.match then 
        err(self, self._errstr.commentErr, f.pos)
    end 

    if fexists(self.handler, 'comment') then 
        f.text = parseEntities(self, stripWS(self, f.text))
        self.handler:comment(f.text, next, f.match, f.endMatch)
    end
end

local function _parseDtd(self, xml, pos)
    -- match,endMatch,root,type,name,uri,internal
    local dtdPatterns = {self._DTD1, self._DTD2, self._DTD3, self._DTD4, self._DTD5}

    for _, dtd in pairs(dtdPatterns) do
        local m,e,r,t,n,u,i = string.find(xml, dtd, pos)
        if m then
            return m, e, {_root=r, _type=t, _name=n, _uri=u, _internal=i} 
        end
    end

    return nil
end

local function parseDtd(self, xml, f)
    f.match, f.endMatch, _ = _parseDtd(self, xml, f.pos)
    if not f.match then 
        err(self, self._errstr.dtdErr, f.pos)
    end 

    if fexists(self.handler, 'dtd') then
        local tag = {name="DOCTYPE", value=string.sub(xml, f.match+10, f.endMatch-1)}
        self.handler:dtd(tag, f.match, f.endMatch)
    end
end

local function parseCdata(self, xml, f)
    f.match, f.endMatch, f.text = string.find(xml, self._CDATA, f.pos)
    if not f.match then 
        err(self, self._errstr.cdataErr, f.pos)
    end 

    if fexists(self.handler, 'cdata') then
        self.handler:cdata(f.text, nil, f.match, f.endMatch)
    end    
end

--- Parse a Normal tag
-- Need check for embedded '>' in attribute value and extend
-- match recursively if necessary eg. <tag attr="123>456"> 
local function parseNormalTag(self, xml, f)
    --Check for errors
    while 1 do
        --If there isn't an attribute without closing quotes (single or double quotes)
        --then breaks to follow the normal processing of the tag.
        --Otherwise, try to find where the quotes close.
        f.errStart, f.errEnd = string.find(f.tagstr, self._ATTRERR1)        

        if f.errEnd == nil then
            f.errStart, f.errEnd = string.find(f.tagstr, self._ATTRERR2)
            if f.errEnd == nil then
                break
            end
        end
        
        f.extStart, f.extEnd, f.endt2 = string.find(xml, self._TAGEXT, f.endMatch+1)
        f.tagstr = f.tagstr .. string.sub(xml, f.endMatch, f.extEnd-1)
        if not f.match then 
            err(self, self._errstr.xmlErr, f.pos)
        end 
        f.endMatch = f.extEnd
    end 

    -- Extract tag name and attrs
    local tag = parseTag(self, f.tagstr) 

    if (f.endt1=="/") then
        if fexists(self.handler, 'endtag') then
            if tag.attrs then
                -- Shouldn't have any attributes in endtag
                err(self, string.format("%s (/%s)", self._errstr.endTagErr, tag.name), f.pos)
            end
            if table.remove(self._stack) ~= tag.name then
                err(self, string.format("%s (/%s)", self._errstr.unmatchedTagErr, tag.name), f.pos)
            end
            self.handler:endtag(tag, f.match, f.endMatch)
        end
    else
        table.insert(self._stack, tag.name)

        if fexists(self.handler, 'starttag') then
            self.handler:starttag(tag, f.match, f.endMatch)
        end

        -- Self-Closing Tag
        if (f.endt2=="/") then
            table.remove(self._stack)
            if fexists(self.handler, 'endtag') then
                self.handler:endtag(tag, f.match, f.endMatch)
            end
        end
    end

    return tag
end

local function parseTagType(self, xml, f)
    -- Test for tag type
    if string.find(string.sub(f.tagstr, 1, 5), "?xml%s") then
        parseXmlDeclaration(self, xml, f)
    elseif string.sub(f.tagstr, 1, 1) == "?" then
        parseXmlProcessingInstruction(self, xml, f)
    elseif string.sub(f.tagstr, 1, 3) == "!--" then
        parseComment(self, xml, f)
    elseif string.sub(f.tagstr, 1, 8) == "!DOCTYPE" then
        parseDtd(self, xml, f)
    elseif string.sub(f.tagstr, 1, 8) == "![CDATA[" then
        parseCdata(self, xml, f)
    else
        parseNormalTag(self, xml, f)
    end
end

--- Get next tag (first pass - fix exceptions below).
--@return true if the next tag could be got, false otherwise
local function getNextTag(self, xml, f)
  f.match, f.endMatch, f.text, f.endt1, f.tagstr, f.endt2 = string.find(xml, self._XML, f.pos)
  if not f.match then 
      if string.find(xml, self._WS, f.pos) then
          -- No more text - check document complete
          if #self._stack ~= 0 then
              err(self, self._errstr.incompleteXmlErr, f.pos)
          else
              return false 
          end
      else
          -- Unparsable text
          err(self, self._errstr.xmlErr, f.pos)
      end
  end 

  f.text = f.text or ''
  f.tagstr = f.tagstr or ''
  f.match = f.match or 0
  
  return f.endMatch ~= nil
end

--Main function which starts the XML parsing process
--@param xml the XML string to parse
--@param parseAttributes indicates if tag attributes should be parsed or not. 
--       If omitted, the default value is true.
function XmlParser:parse(xml, parseAttributes)
    if type(self) ~= "table" or getmetatable(self) ~= XmlParser then
        error("You must call xmlparser:parse(parameters) instead of xmlparser.parse(parameters)")
    end

    if parseAttributes == nil then
       parseAttributes = true
    end

    self.handler.parseAttributes = parseAttributes

    --Stores string.find results and parameters
    --and other auxiliar variables
    local f = {
        --string.find return
        match = 0,
        endMatch = 0,
        -- text, end1, tagstr, end2,

        --string.find parameters and auxiliar variables
        pos = 1,
        -- startText, endText,
        -- errStart, errEnd, extStart, extEnd,
    }

    while f.match do
        if not getNextTag(self, xml, f) then
            break
        end
        
        -- Handle leading text
        f.startText = f.match
        f.endText = f.match + string.len(f.text) - 1
        f.match = f.match + string.len(f.text)
        f.text = parseEntities(self, stripWS(self, f.text))
        if f.text ~= "" and fexists(self.handler, 'text') then
            self.handler:text(f.text, nil, f.match, f.endText)
        end

        parseTagType(self, xml, f)
        f.pos = f.endMatch + 1
    end
end

XmlParser.__index = XmlParser
return XmlParser
