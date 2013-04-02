---
-- Persona Lua auth backend using ngx location capture
-- 
-- Copyright Tor Hveem <thveem> 2013
-- 
-- Nginx conf example:
-- location /persona/ {
--     internal;
--     proxy_set_header Content-type 'application/json';
--     proxy_pass 'https://verifier.login.persona.org:443/verify';
-- }
--
local setmetatable = setmetatable
local ngx = ngx
local cjson = require "cjson"
local redis = require "resty.redis"
-- redis
local red  = nil


module(...)

local mt = { __index = _M }

-- 
-- Initialise db
--
local function init_redis()
    -- Start redis connection
    red = redis:new()
    local ok, err = red:connect("unix:/var/run/redis/redis.sock")
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end
end
init_redis()

--
-- End db, we could close here, but park it in the pool instead
--
local function end_redis()
    -- put it into the connection pool of size 100,
    -- with 0 idle timeout
    local ok, err = red:set_keepalive(0, 100)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
        return
    end
end

function login(assertion, audience)

    local vars = {
        assertion=assertion,
        audience=audience,
    }
    local options = {
        method = ngx.HTTP_POST,
        body = cjson.encode(vars)
    }

    local res, err = ngx.location.capture('/persona/', options);

    if not res then
        return { err = res }
    end

    if res.status >= 200 and res.status < 300 then
        return cjson.decode(res.body)
    else
        return {
            status= res.status,
            body = res.body
        }
    end
end

function getsess(sessionid)
    return red:get('nyfyk:session:'..sessionid)
end

local function setsess(personadata)
    -- Set cookie for session
    local sessionid = ngx.md5(personadata.email .. ngx.md5(personadata.expires))
    ngx.header['Set-Cookie'] = 'session='..sessionid..'; path=/; HttpOnly'
    red:set('nyfyk:session:'..sessionid, cjson.encode(personadata))
    -- Expire the key when the session expires, so if key exists login is valid
    red:expire('nyfyk:session:'..sessionid, personadata.expires)
end

function get_current_email()
    local cookie = ngx.var['cookie_session']
    if cookie then
        local sess = getsess(cookie)
        if sess ~= ngx.null then
            sess = cjson.decode(sess)
            return sess.email
        end
    end
    return false
end

function login()
    ngx.req.read_body()
    -- app is sending application/json
    local body = ngx.req.get_body_data()
    if body then 
        local args = cjson.decode(body)
        local audience = 'nyfyk.hveem.no'
        local personadata = persona.login(args.assertion, audience)
        if personadata.status == 'okay' then
            setsess(personadata)
        end
        -- Print the data back to client
        ngx.print(cjson.encode(personadata))
    else
        ngx.print ( cjson.encode({ email = false}) )
    end
end

function status()
    local cookie = ngx.var['cookie_session']
    if cookie then
        ngx.print (getsess(cookie))
    else
        ngx.print ( '{"email":false}' )
    end
end

function logout()
    local cookie = ngx.var['cookie_session']
    if cookie then
        ngx.print(red:del('nyfyk:session:'..cookie))
        ngx.print( 'true' )
    else
        ngx.print( 'false' )
    end
end

local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        ngx.log(ngx.ERR, 'attempt to write to undeclared variable "' .. key .. '"')
    end
}

setmetatable(_M, class_mt)
