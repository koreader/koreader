-- Implementation of the Gemini protocol, following version 0.24.0 of the spec
-- gemini://geminiprotocol.net/docs/protocol-specification.gmi

local socket = require("socket")
local ssl = require("ssl")
local url = require("socket.url")
local sha256 = require("ffi/sha2").sha256
local _ = require("gettext")
local T = require("ffi/util").template

-- trusted_times_step: consider connections this far apart as separate enough to
-- reinforce TOFU-trust
local trusted_times_step = 3600
local default_port = "1965"

local gemini = {}

-- print url, stripping default port and, optionally, "gemini://"
function gemini.showUrl(u, strip_gemini_scheme)
    local copy = {}
    local purl = u
    if type(u) == "string" then
        purl = url.parse(u)
        if purl == nil then
            return u
        end
    end
    for k,v in pairs(purl) do
        copy[k] = v
    end
    if copy.port == "1965" then
        copy.port = nil
    end
    if strip_gemini_scheme and copy.scheme == "gemini" then
        copy.scheme = nil
    end
    return url.build(copy):gsub("^//","",1)
end

function gemini.upUrl(u)
    local up = url.absolute(u, ".")
    if up == u then
        up = url.absolute(u, "..")
    end
    return up
end

-- Does any necessary percent-escaping and stripping to make a
-- socket.url-parsed URL compliant with RFC 3986. '%' is encoded only where it
-- is not part of valid percent-encoding. Modifies purl in place.
function gemini.escape(purl)
    local function escape(s, unescaped)
        if s == nil then
            return nil
        end
        -- hairy encoding of '%' where not followed by two hex chars:
        s = s:gsub("%%%%","%%25%%"):gsub("%%%%","%%25%%"):gsub("%%%f[^%%%x]","%%25"):gsub("%%(%x)%f[%X]","%%25%1")
        return s:gsub("[^"..unescaped.."%%]", function(c)
            return string.format("%%%x",c:byte(1))
        end)
    end
    local unreserved = "%w%-._~"
    local subdelims = "!$&'()*+,;="
    local pchar = unreserved..subdelims..":@"
    purl.host = escape(purl.host, unreserved..subdelims)
    purl.path = escape(purl.path, pchar.."/")
    purl.query = escape(purl.query, pchar.."/?")
    purl.port = purl.port and purl.port:gsub("[^%d]","")
end

local errTexts = {
    ["40"] = _("temporary failure"),
    ["41"] = _("server unavailable"),
    ["42"] = _("CGI error"),
    ["43"] = _("proxy error"),
    ["44"] = _("too many requests"),
    ["50"] = _("permanent failure"),
    ["51"] = _("resource not found"),
    ["52"] = _("resource gone"),
    ["53"] = _("proxy request refused"),
    ["59"] = _("bad request"),
    ["60"] = _("client certificate required"),
    ["61"] = _("client certificate not authorised"),
    ["62"] = _("client certificate not valid"),
}

local ipv6_available = socket.tcp6() ~= nil

-- @table trust_store Opaque table to be stored and passed to subsequent calls
--
-- @param cafile CA certificates to use for CA-based trust. nil to disable.
-- WARNING: as of luasec-1.3.2, CA-based trust checking seems to be thoroughly
-- broken and should not be used:
-- https://github.com/lunarmodules/luasec/issues/161
--
-- @func check_trust_cb Callback to check for trust of a public key when we've
-- previously TOFU-trusted another;
-- parameters: fullhost, digest, trusted_times, expiry, cb;
-- callback should call cb("always") if the new pubkey should be added to
-- the trust store (replacing the old one),
-- or cb("once") to proceed with the connection without trusting the pubkey,
-- or else cb() to abort connection.
--
-- @func trust_modified_cb Callback called without params when trust_store is
-- modified (e.g. so it can be updated on disk)
--
-- @func success_cb Callback called on 20 (success) response;
-- parameters: peer_qfile, mimetype, params, cert_info;
-- peer_qfile is a quasi-file representing the body,
-- supporting :close, :read("l"), :read("a"), and :read(n), with read
-- calls returning nil,"aborted" if the connection is aborted via info_cb.
--
-- @func error_cb Callback called on connection error or error codes other
-- than 20;
-- parameters: errText, major, minor, meta;
-- errText describes the error; the rest are nil except on error code [13456],
-- then major and minor are the one-digit strings of the error code,
-- and meta is any text received in the response.
-- Should return nil.
--
-- @func info_cb Optional callback to present the progress message
-- given as its parameter. Return false to abort the connection.
--
-- @bool confirm_new_tofu Call check_trust_cb (with trusted_times = 0)
-- before trusting a key for a new host.
--
-- @string proxy Optional host to proxy request via.
--
-- @string titan_upload_body Optional body for upload via the Titan protocol,
-- following gemini://transjovian.org/titan/page/The%20Titan%20Specification
function gemini.makeRequest(u, key, cert, cafile, trust_store, check_trust_cb, trust_modified_cb, success_cb, error_cb, info_cb, confirm_new_tofu, proxy, titan_upload_body)
    info_cb = info_cb or function() return true end
    local purl = url.parse(u, {scheme = "gemini", port = default_port})
    if not purl then
        return error_cb(T(_("Failed to parse URL: %1"), u))
    end
    if purl.port == default_port then
        purl.port = nil
    end
    if purl.scheme == "gemini" then
        purl.fragment = nil
        purl.userinfo = nil
        purl.password = nil
        if not purl.path or purl.path == "" then
            purl.path = "/"
        end
    end
    gemini.escape(purl)
    u = url.build(purl)

    if #u > 1024 then
        return error_cb(T(_("URL too long: %1"), u))
    end

    local openssl_options = {"all", "no_tlsv1", "no_tlsv1_1"}
    if key then
        -- Do not allow connecting with a client certificate using TLSv1.2,
        -- which does not encrypt the certificate.
        -- (The gemini spec only says that we should warn the user before
        -- doing so, but that seems not to be possible with luasec.)
        table.insert(openssl_options, "no_tlsv1_2")
    end
    local context, err = ssl.newcontext({
        mode = "client",
        protocol = "any",
        options = openssl_options,
        cafile = cafile,
        key = key,
        certificate = cert,
    })
    if not context then
        return error_cb(T(_("Error initialising TLS context: %1"), err))
    end

    local peer
    if ipv6_available then
        peer, err = socket.tcp()
    else
        peer, err = socket.tcp4()
    end
    if not peer then
        return error_cb(T(_("Error initialising TCP: %1"), err))
    end

    local pretty_url = gemini.showUrl(u, true)
    local function info(stage, fast)
        return info_cb(T("%1\n%2...", pretty_url, stage), fast)
    end
    if not info("Connecting") then
        return
    end

    local timeout = 1 -- not too short, because each call to info_cb costs 100ms
    peer:settimeout(timeout)

    local function with_timeouts(cb, stage, errmsg_pat, fast)
        while true do
            local ret, e = cb()
            if ret then
                return ret
            end
            if e == "closed" then
                return false
            elseif e == "timeout" or e == "wantread" or e == "wantwrite" then
                while true do
                    if not info(stage, fast) then
                        return false, "aborted"
                    end
                    fast = true
                    local __, ___, sock_err = socket.select(
                        e == "wantread" and {peer} or nil,
                        (e == "timeout" or e == "wantwrite") and {peer} or nil, 1)
                    if sock_err == nil then
                        break
                    elseif sock_err ~= "timeout" then
                        return error_cb(T(error_cb, sock_err))
                    end
                end
            else
                return error_cb(T(errmsg_pat, e))
            end
        end
    end
    local function get_send_cb(data)
        local i = 0
        return function()
            local ret, e
            ret, e, i = peer:send(data, i+1)
            return ret, e
        end
    end
    local function get_recv_cb(p)
        local acc
        return function()
            local ret, e, partial = peer:receive(p)
            if ret then
                return (acc or "") .. ret
            else
                if partial then
                    acc = (acc or "") .. partial
                end
                if e == "closed" and acc then
                    return acc
                end
                return ret, e
            end
        end
    end

    local host, port
    if proxy then
        host, port = proxy:match("^([^:]*):(%d+)")
        if not host then
            host = proxy
            port = default_port
        end
    else
        host = purl.host
        port = tonumber(purl.port or default_port)
    end
    local function get_connect_cb()
        local done
        return function()
            if done then
                return true
            else
                done = true
                return peer:connect(host, port)
            end
        end
    end
    if not with_timeouts(get_connect_cb(),
        _("Connecting"), _("Error connecting to peer: %1"), true)
    then
        return peer:close()
    end

    peer, err = ssl.wrap(peer, context)
    if not peer then
        return error_cb(T(_("Error on ssl.wrap: %1"), err))
    end
    peer:settimeout(timeout)
    peer:sni(host)

    if not with_timeouts(function() return peer:dohandshake() end,
        _("Handshaking"), _("Error on handshake: %1"))
    then
        return peer:close()
    end

    local fullhost
    if proxy then
        fullhost = proxy
    else
        fullhost = purl.host
        if purl.port then
            fullhost = fullhost .. ":" .. purl.port
        end
    end

    local peer_cert = peer:getpeercertificate()
    if not peer_cert then
        peer:close()
        return error_cb(_("Failed to obtain peer certificate"))
    end
    local pk_hash = sha256(peer_cert:pubkey())
    local digest = peer_cert:digest("sha256")
    local expiry = peer_cert:notafter()

    local function do_connection(trusted)
        if not with_timeouts(get_send_cb(u.."\r\n"),
            _("Requesting"), _("Error sending request: %1"))
        then
            return peer:close()
        end

        local status
        if titan_upload_body then
            -- XXX hack: give server a second to respond with an error to our
            -- upload attempt. If we just start sending, the connection will
            -- be closed and then it seems we can't receive the early
            -- response.
            status, err = peer:receive("*l")
            if err and err ~= "wantread" and err ~= "wantwrite" then
                error_cb(T(_("Error receiving early response status: %1"), err))
                return peer:close()
            end

            if not status then
                local __, aborted = with_timeouts(get_send_cb(titan_upload_body),
                    _("Uploading"), _("Error during upload: %1"))
                if aborted then
                    return peer:close()
                end
            end
        end

        -- Note: "*l" reads a line terminated either with \n or \r\n or
        -- EOF, whereas the Gemini header must be terminated with \r\n.
        -- However, no \n is allowed before the \r\n, so the only effect
        -- is to accept some invalid responses.
        status = status or with_timeouts(get_recv_cb("*l"),
            _("Receiving header"), _("Error receiving response status : %1"))
        if not status then
            return peer:close()
        end

        local major, minor, post = status:match("^([1-6])([0-9])(.*)")
        if not major or not minor then
            error_cb(T(_("Invalid response status line: %1"), status:sub(1,64)))
            return peer:close()
        end
        local meta = post:match("^ (.*)") or ""

        if major == "2" then
            local token_chars = "[a-zA-Z0-9!#$%%&'*+-.^_`{|}-]" -- from RFC 2045
            local mimetype, params_str = meta:match("^("..token_chars.."+/"..token_chars.."+)(.*)")
            mimetype = mimetype or "text/gemini"
            local params = {}
            while params_str and params_str ~= "" do
                local param, rest = params_str:match("^;%s*("..token_chars.."+=\"[^\"]*\")(.*)")
                if not param then
                    param, rest = params_str:match("^;%s*("..token_chars.."+="..token_chars.."+)(.*)")
                end
                if not param then
                    -- ignore unparseable parameters
                    break
                end
                params_str = rest
                table.insert(params, param)
            end

            local peer_qfile = {}
            function peer_qfile:read(x)
                x = (type(x) == "string" and x:match("^[al]$") and "*"..x)
                    or (type(x) == "number" and x)
                return with_timeouts(get_recv_cb(x),
                        _("Receiving body"), _("Error receiving body: %1"))
            end
            function peer_qfile:close()
                peer:close()
            end
            local cert_info = {
                fp = digest,
                expiry = expiry,
                trusted_times = trusted and trusted.trusted_times or 0,
                ca = trusted and trusted.ca
            }
            success_cb(peer_qfile, mimetype, params, cert_info)
        else
            peer:close()
            if tonumber(major) < 1 or tonumber(major) > 6 then
                error_cb(_("Server returns invalid error code."))
            else
                local errText = errTexts[major..minor]
                if not errText then
                    errText = errTexts[major.."0"]
                end
                error_cb(errText, major, minor, meta)
            end
        end
    end

    local function set_trust(times)
        trust_store[fullhost] = {
            pk_hash = pk_hash,
            digest = digest,
            expiry = expiry,
            trusted_times = 1,
            last_trust_time = os.time(),
        }
        trust_modified_cb()
    end

    if cafile then
        if peer:getpeerverification() then
            local ca_cert
            for _i, c in ipairs( peer:getpeerchain() ) do
                ca_cert = c
            end
            return do_connection({ ca = ca_cert:issuer() })
        end
    end

    local function trust_cb_cb(user_trust)
        if user_trust == "always" then
            set_trust()
            do_connection(trust_store[fullhost])
        elseif user_trust == "once" then
            do_connection()
        else
            peer:close()
        end
    end

    local trusted = trust_store[fullhost]
    if not trusted then
        -- Trust On First Use
        if confirm_new_tofu then
            check_trust_cb(fullhost, digest, 0, "", trust_cb_cb)
        else
            trust_cb_cb("always")
        end
    else
        if trusted.pk_hash == pk_hash then
            local now = os.time()
            if now - trusted.last_trust_time > trusted_times_step then
                trusted.trusted_times = trusted.trusted_times + 1
                trusted.last_trust_time = now
                trust_modified_cb()
            end
            if trusted.digest ~= digest then
                -- Extend trust to update cert with same public key.
                trusted.digest = digest
                trusted.expiry = expiry
                trust_modified_cb()
            end
            do_connection(trusted)
        else
            check_trust_cb(fullhost, digest, trusted.trusted_times, trusted.expiry, trust_cb_cb)
        end
    end
end
return gemini
