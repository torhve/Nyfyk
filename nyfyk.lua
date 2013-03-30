local dbi = require 'DBI'
local cjson = require "cjson"
local os = require 'os'
local persona = require 'persona'
local redis = require "resty.redis"

local DBPATH = '/home/xt/src/nyfyk/db/newsbeuter.db'
-- sqlite
local dbh  = nil
-- redis
local red  = nil

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

--
-- Helper function to execute statements
--
local function dbexec(sql)
    local sth, err = dbh:prepare(sql)
    if err then 
        ngx.print(err)
        return false
    end
    local ok, err = sth:execute()
    if err then 
        ngx.print(err)
        return false
    end
    return sth, ok, err
end

--
-- Convenience SQL getter function that puts columns into each row, for easy JSON
--
local function dbget(sql) 
    local ret = {}
    local sth, ok, err = dbexec(sql)
    if ok then 
        local columns = sth:columns()
        for r in sth:rows() do
            local row = {}
            for i, c in ipairs(columns) do
                row[c] = r[i]
            end
            table.insert(ret, row)
        end
    end
    return ret
end

local function items(idx)
    local sql = dbget('SELECT rssurl FROM rss_feed')
    for i, k in ipairs(sql) do
        if idx == i then
            local feedurl = k.rssurl;
            local feedurl = '%'
            local feeds = dbget('SELECT guid,title,author,url,pubDate,content,unread,feedurl,enclosure_url,enclosure_type,enqueued,flags,base FROM rss_item WHERE feedurl = "'..feedurl..'" AND deleted = 0 ORDER BY pubDate DESC, id DESC limit 10;"')
            ngx.print(cjson.encode(feeds))
            return
        end
    end
end

--
-- Get or modify all itmes
--
local function allitems()
    local method = ngx.req.get_method()
    if method == 'PUT' then
        local sth, ok, err = dbexec([[ UPDATE rss_item SET unread = 0 ]])
        if not ok then
            ngx.print('{"success": false, "err": '..err..'}')
        else
            ngx.print('{"success": true}')
        end
    elseif method == 'GET' then
        local feeds = dbget('SELECT id,guid,title,author,url,pubDate,content,unread,feedurl,enclosure_url,enclosure_type,enqueued,flags,base,(select title from rss_feed where rss_feed.rssurl = feedurl) as feedTitle FROM rss_item WHERE deleted = 0 ORDER BY pubDate DESC, id DESC ;"')
        ngx.print(cjson.encode(feeds))
    end
end

local function feeds()
    --local sql = dbget('SELECT * FROM rss_feed')
    --local sql = dbget([[
    --    select rss_feed.title,rssurl, count(unread) as unread from rss_feed inner join rss_item where rss_item.feedurl = rss_feed.rssurl and unread = 1 group by rssurl order by rss_feed.title;
    --]])
    local sql = dbget([[
    select *, (select count(unread) from rss_item where rss_item.feedurl = rssurl and unread = 1) as unread  from rss_feed;
    ]])

    ngx.print(cjson.encode(sql))
end

--
-- Take parameters from a PUT request and overwrite the record with new values
--
local function item(match)
    local id = assert(tonumber(match[1]))
    local method = ngx.req.get_method()
    -- TODO check for parameter (unread)
    if method == 'PUT' then
        -- TODO check for parameter (unread) ?
        ngx.req.read_body()
        -- app is sending application/json
        local args = cjson.decode(ngx.req.get_body_data())
        -- make sure it's a number
        local unread = assert(tonumber(args.unread))
        local sth, ok, err = dbexec([[
            UPDATE rss_item 
            SET unread = ]]..unread..[[ 
            WHERE id = ]]..id ..[[ 
            LIMIT 1 ]]
        )
        if not ok then
            ngx.print(ok)
        else
            ngx.print('{"success": true}')
        end
    elseif method == 'GET' then
        items(id)
    end
end

--
-- Spawn the newsbeuter refresh
--
local function refresh()
    -- for the demo copy a sample db back to newsbeuter.db
    local cmd = 'cp '..DBPATH..'.demo '..DBPATH
    
    if get_current_email() == 'tor@hveem.no' then
        cmd = 'newsbeuter -u /home/xt/.newsbeuter/urls -c /home/xt/.newsbeuter/cache.db -x reload'
    end
    ngx.print(cmd)
    local exec = os.execute(cmd)
    ngx.print(exec)
end

local function getsess(sessionid)
    return red:get('nyfyk:session:'..sessionid)
end

local function get_current_email()
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

local function setsess(personadata)
    -- Set cookie for session
    local sessionid = ngx.md5(personadata.email .. ngx.md5(personadata.expires))
    ngx.header['Set-Cookie'] = 'session='..sessionid..'; path=/; HttpOnly'
    red:set('nyfyk:session:'..sessionid, cjson.encode(personadata))
    -- Expire the key when the session expires, so if key exists login is valid
    red:expire('nyfyk:session:'..sessionid, personadata.expires)
end

local function login()
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

local function persona_status()
    local cookie = ngx.var['cookie_session']
    if cookie then
        ngx.print (getsess(cookie))
    else
        ngx.print ( '{"email":false}' )
    end
end

local function logout()
    local cookie = ngx.var['cookie_session']
    if cookie then
        ngx.print(red:del('nyfyk:session:'..cookie))
        ngx.print( 'true' )
    else
        ngx.print( 'false' )
    end
end

-- mapping patterns to views
local routes = {
    ['feeds/$']     = feeds,
    ['items/?$'] = allitems,
    ['items/(\\d+)/?$'] = item,
    ['refresh/$']     = refresh,
    ['persona/verify$']  = login,
    ['persona/logout$']  = logout,
    ['persona/status$']  = persona_status,
}
-- Set the content type
ngx.header.content_type = 'application/json';

local BASE = '/nyfyk/api/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        init_redis()
        if get_current_email() == 'tor@hveem.no' then
            DBPATH = '/home/xt/.newsbeuter/cache.db'
        end
        dbh = assert(DBI.Connect('SQLite3', DBPATH, nil, nil, nil, nil))
        dbh:autocommit(true)
        exit = view(match) or ngx.HTTP_OK
        -- finish up
        --local ok = dbh:commit()
        local ok = dbh:close()
        end_redis()
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )


