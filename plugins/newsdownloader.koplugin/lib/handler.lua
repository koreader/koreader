---
--  Overview:
--  =========
--      Standard XML event handler(s) for XML parser module (xml.lua)
--
--  Features:
--  =========
--      printHandler        - Generate XML event trace
--      domHandler          - Generate DOM-like node tree
--      simpleTreeHandler   - Generate 'simple' node tree
--
--  API:
--  ====
--      Must be called as handler function from xmlParser
--      and implement XML event callbacks (see xmlParser.lua
--      for callback API definition)
--
--      printHandler:
--      -------------
--
--      printHandler prints event trace for debugging
--
--      domHandler:
--      -----------
--
--      domHandler generates a DOM-like node tree  structure with
--      a single ROOT node parent - each node is a table comprising
--      fields below.
--
--      node = { _name = <Element Name>,
--              _type = ROOT|ELEMENT|TEXT|COMMENT|PI|DECL|DTD,
--              _attr = { Node attributes - see callback API },
--              _parent = <Parent Node>
--              _children = { List of child nodes - ROOT/NODE only }
--            }
--
--      The dom structure is capable of representing any valid XML document
--
--      simpleTreeHandler
--      -----------------
--
--      simpleTreeHandler is a simplified handler which attempts
--      to generate a more 'natural' table based structure which
--      supports many common XML formats.
--
--      The XML tree structure is mapped directly into a recursive
--      table structure with node names as keys and child elements
--      as either a table of values or directly as a string value
--      for text. Where there is only a single child element this
--      is inserted as a named key - if there are multiple
--      elements these are inserted as a vector (in some cases it
--      may be preferable to always insert elements as a vector
--      which can be specified on a per element basis in the
--      options).  Attributes are inserted as a child element with
--      a key of '_attr'.
--
--      Only Tag/Text & CDATA elements are processed - all others
--      are ignored.
--
--      This format has some limitations - primarily
--
--      * Mixed-Content behaves unpredictably - the relationship
--        between text elements and embedded tags is lost and
--        multiple levels of mixed content does not work
--      * If a leaf element has both a text element and attributes
--        then the text must be accessed through a vector (to
--        provide a container for the attribute)
--
--      In general however this format is relatively useful.
--
--      It is much easier to understand by running some test
--      data through 'textxml.lua -simpletree' than to read this)
--
--  Options
--  =======
--      simpleTreeHandler.options.noReduce = { <tag> = bool,.. }
--
--          - Nodes not to reduce children vector even if only
--            one child
--
--      domHandler.options.(comment|pi|dtd|decl)Node = bool
--
--          - Include/exclude given node types
--
--  Usage
--  =====
--      Parsed as delegate in xmlParser constructor and called
--      as callback by xmlParser:parse(xml) method.
--
--      See textxml.lua for examples
--  License:
--  ========
--
--      This code is freely distributable under the terms of the Lua license
--      (<a href="http://www.lua.org/copyright.html">http://www.lua.org/copyright.html</a>)
--
--  History
--  =======
--  $Id: handler.lua,v 1.1.1.1 2001/11/28 06:11:33 paulc Exp $
--
--  $Log: handler.lua,v $
--  Revision 1.1.1.1  2001/11/28 06:11:33  paulc
--  Initial Import
--@author Paul Chakravarti (paulc@passtheaardvark.com)<p/>


---Handler to generate a string prepresentation of a table
--Convenience function for printHandler (Does not support recursive tables).
--@param t Table to be parsed
--@returns Returns a string representation of table
local function showTable(t)
    local sep = ''
    local res = ''
    if type(t) ~= 'table' then
        return t
    end
    for k,v in pairs(t) do
        if type(v) == 'table' then
            v = showTable(v)
        end
        res = res .. sep .. string.format("%s=%s",k,v)
        sep = ','
    end
    res = '{'..res..'}'
    return res
end

---Handler to generate a simple event trace
local printHandler = function()
    local obj = {}
    obj.starttag = function(self,t,a,s,e)
        io.write("Start    : "..t.."\n")
        if a then
            for k,v in pairs(a) do
                io.write(string.format(" + %s='%s'\n",k,v))
            end
        end
    end
    obj.endtag = function(self,t,s,e)
        io.write("End      : "..t.."\n")
    end
    obj.text = function(self,t,s,e)
        io.write("Text     : "..t.."\n")
    end
    obj.cdata = function(self,t,s,e)
        io.write("CDATA    : "..t.."\n")
    end
    obj.comment = function(self,t,s,e)
        io.write("Comment  : "..t.."\n")
    end
    obj.dtd = function(self,t,a,s,e)
        io.write("DTD      : "..t.."\n")
        if a then
            for k,v in pairs(a) do
                io.write(string.format(" + %s='%s'\n",k,v))
            end
        end
    end
    obj.pi = function(self,t,a,s,e)
        io.write("PI       : "..t.."\n")
        if a then
            for k,v in pairs(a) do
               io. write(string.format(" + %s='%s'\n",k,v))
            end
        end
    end
    obj.decl = function(self,t,a,s,e)
        io.write("XML Decl : "..t.."\n")
        if a then
            for k,v in pairs(a) do
                io.write(string.format(" + %s='%s'\n",k,v))
            end
        end
    end
    return obj
end


--Obtém a primeira chave de uma tabela
--@param Tabela de onde deverá ser obtido o primeiro elemento
--@return Retorna a primeira chave da tabela
local function getFirstKey(tb)
   if type(tb) == "table" then
       --O uso da função next não funciona para pegar o primeiro elemento. Trava aqui
      --k, v = next(tb)
      --return k
      for k, v in pairs(tb) do
          return k
      end
      return nil
   else
     return tb
   end
end

---Handler to generate a lua table from a XML content string
local function simpleTreeHandler()
    local obj = {}

    obj.root = {}
    obj.stack = {obj.root;n=1}
    obj.options = {noreduce = {}}

    obj.reduce = function(self,node,key,parent)
        -- Recursively remove redundant vectors for nodes
        -- with single child elements
        for k,v in pairs(node) do
            if type(v) == 'table' then
                self:reduce(v,k,node)
            end
        end
        if #node == 1 and not self.options.noreduce[key] and
            node._attr == nil then
            parent[key] = node[1]
        else
            node.n = nil
        end
    end

    --@param t Table that represents a XML tag
    --@param a Attributes table (_attr)
    obj.starttag = function(self,t,a)
        local node = {}
        if self.parseAttributes == true then
           node._attr=a
        end

        local current = self.stack[#self.stack]
        if current[t] then
            table.insert(current[t],node)
        else
            current[t] = {node;n=1}
        end
        table.insert(self.stack,node)
    end

    --@param t Tag name
    obj.endtag = function(self,t,s)
        --Tabela que representa a tag atualmente sendo processada
        local current = self.stack[#self.stack]
        --Tabela que representa a tag na qual a tag
        --atual está contida.
        local prev = self.stack[#self.stack-1]
        if not prev[t] then
            error("XML Error - Unmatched Tag ["..s..":"..t.."]\n")
        end
        if prev == self.root then
            -- Once parsing complete recursively reduce tree
            self:reduce(prev,nil,nil)
        end

        local firstKey = getFirstKey(current)
        --Se a primeira chave da tabela que representa
        --a tag  atual não possui nenhum elemento,
        --é porque não há nenhum valor associado à tag
        -- (como nos casos de tags automaticamente fechadas como <senha />).
        --Assim, atribui uma string vazia a mesma para
        --que seja retornado vazio no lugar da tag e não
        --uma tabela. Retornando uma string vazia
        --simplifica para as aplicações NCLua
        --para imprimir tal valor.
        if firstKey == nil then
           current[t] = ""
           prev[t] = ""
        end

        table.remove(self.stack)
    end

    obj.text = function(self,t)
        local current = self.stack[#self.stack]
        table.insert(current,t)
    end

    obj.cdata = obj.text

    return obj
end

--- domHandler
local function domHandler()
    local obj = {}
    obj.options = {commentNode=1,piNode=1,dtdNode=1,declNode=1}
    obj.root = { _children = {n=0}, _type = "ROOT" }
    obj.current = obj.root
    obj.starttag = function(self,t,a)
            local node = { _type = 'ELEMENT',
                           _name = t,
                           _attr = a,
                           _parent = self.current,
                           _children = {n=0} }
            table.insert(self.current._children,node)
            self.current = node
    end
    obj.endtag = function(self,t,s)
            if t ~= self.current._name then
                error("XML Error - Unmatched Tag ["..s..":"..t.."]\n")
            end
            self.current = self.current._parent
    end
    obj.text = function(self,t)
            local node = { _type = "TEXT",
                           _parent = self.current,
                           _text = t }
            table.insert(self.current._children,node)
    end
    obj.comment = function(self,t)
            if self.options.commentNode then
                local node = { _type = "COMMENT",
                               _parent = self.current,
                               _text = t }
                table.insert(self.current._children,node)
            end
    end
    obj.pi = function(self,t,a)
            if self.options.piNode then
                local node = { _type = "PI",
                               _name = t,
                               _attr = a,
                               _parent = self.current }
                table.insert(self.current._children,node)
            end
    end
    obj.decl = function(self,t,a)
            if self.options.declNode then
                local node = { _type = "DECL",
                               _name = t,
                               _attr = a,
                               _parent = self.current }
                table.insert(self.current._children,node)
            end
    end
    obj.dtd = function(self,t,a)
            if self.options.dtdNode then
                local node = { _type = "DTD",
                               _name = t,
                               _attr = a,
                               _parent = self.current }
                table.insert(self.current._children,node)
            end
    end
    obj.cdata = obj.text
    return obj
end

return { simpleTreeHandler = simpleTreeHandler }
