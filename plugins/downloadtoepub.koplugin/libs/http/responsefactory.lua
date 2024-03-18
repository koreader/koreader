local Response = require("libs/http/response")

local ResponseFactory = {

}

function ResponseFactory:make(code, headers, status, content)
    return Response:new{
        code = code,
        headers = headers,
        status = status,
        content = content
    }
end

return ResponseFactory
