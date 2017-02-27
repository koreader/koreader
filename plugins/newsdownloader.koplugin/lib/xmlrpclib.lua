---XMLRPC serialiser/deserialiser<br/>
--
-- XXXX Incomplete/Deprecated - DO NOT USE<br/>
--
-- $Id: xmlrpclib.lua,v 1.1.1.1 2001/11/28 06:11:33 paulc Exp $<br/>
--
-- $Log: xmlrpclib.lua,v $<br/>
-- Revision 1.1.1.1  2001/11/28 06:11:33  paulc<br/>
-- Initial Import
--

---xmlrpclib
xmlrpclib = function()
    obj = {}

    obj._BOOL = type(true)

    obj._FROMXML = { i4 = tonumber,
                     int = tonumber,
                     boolean = function(x) return x ~= '0' end,
                     string = function(x) return x end,
                     double = tonumber,
                     base64 = function(x) return x end,
                     ['dateTime.iso8601'] = function(x) return x end,
                     ['nil'] = function(x) return nil end,
                   }

    obj._TOXML = { table = function(self,x) 
                                local res = ""
                                if tag(x) == self._BOOL then
                                    return "<value><boolean>"..x[1].."</boolean></value>"
                                elseif table.getn(x) > 0 then
                                    res = res.."<value><array><data>"
                                    for i=1,table.getn(x) do
                                        res = res..self._TOXML[type(x[i])](self,x[i])
                                    end
                                    res = res.."</data></array></value>"
                                    return res
                                else
                                    res = res.."<value><struct>"
                                    for k,v in x do
                                        res = res.."<member><name>"..k.."</name>"
                                        res = res..self._TOXML[type(v)](self,v).."</member>".."\n"
                                    end
                                    res = res.."</struct></value>"
                                end
                                return res
                            end,
                   number = function(self,x) 
                                if x==ceil(x) then
                                    return "<value><int>"..tostring(x).."</int></value>"
                                else
                                    return "<value><double>"..tostring(x).."</double></value>"
                                end
                            end,
                   string = function(self,x)
                                return "<value><string>"..x.."</string></value>"
                            end,
                   ['nil'] = function(self,x)
                                return "<value><nil/></value>"
                             end,
                  }

    function obj:bool(x)
        local res = {}
        if x then
            res[1] = 1
        else
            res[1] = 0 
        end
        return res
    end

    function obj:serialise(t)
        local res = ""
        if type(t) ~= 'table' then
            t = {t}
        end
        for i=1,table.getn(t) do
            res = res.."<param>"..self._TOXML[type(t[i])](self,t[i]).."</param>".."\n"
        end
        return res
    end

    function obj:methodResponse(t)
        local res = "<?xml version=\"1.0\"?>\n"
        res = res.."<methodResponse><params>\n"
        res = res..self:serialise(t)
        res = res.."</params></methodResponse>\n"
        return res
    end

    function obj:parseParam(param)
        local element = param.value
        if type(value) == 'string' then
            return value
        elseif element.struct then
            local struct = {}
            if element.struct.member then
                for i=1,table.getn(element.struct.member) do
                    local name = element.struct.member[i].name
                    local value = self:parseParam(element.struct.member[i])
                    struct[name] = value
                end
            end
            return struct
        elseif element.array then
            local array = {}
            local values
            if element.array.data.value then
                if table.getn(element.array.data.value) == 0 then
                    values = {element.array.data.value}
                else
                    values = element.array.data.value
                end
                for i=1,table.getn(values) do
                    table.insert(array,self:parseParam({value = values[i]}))
                end
                array.n = nil
            end
            return array
        elseif type(element) == 'table' then
            local dtype,dval = next(element)
            if not self._FROMXML[dtype] then
                error("Unknown Datatype:")
            end
            return self._FROMXML[dtype](dval)    
        else
            error("Unknown Datatype:")
        end
    end

    function obj:parseMethodCall(root)
        local methodCall = root.methodCall
        if not methodCall then
            error("Invalid RPC Message")
        end
        local methodName = methodCall.methodName
        local params = {}
        if methodCall.params then
            for i=1,table.getn(methodCall.params.param) do 
                table.insert(params,self:parseParam(methodCall.params.param[i]))
            end
        end
        params.n = nil
        return methodName,params
    end

    return obj
end

