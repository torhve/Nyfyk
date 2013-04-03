local cjson = require "cjson"
local persona = require 'persona'
local db = require 'dbutil'
local sprintf = string.format
local say = ngx.say

--
-- Get or modify all itens
--
local function items()
    local method = ngx.req.get_method()
    if method == 'PUT' then
        ngx.req.read_body()
        -- app is sending application/json
        local args = cjson.decode(ngx.req.get_body_data())
        local email = persona.get_current_email()
        if not email then say('{}') return end
        --local res= db.dbreq([[ UPDATE rss_item SET unread = 0 ]])
        local ok = true
        for i, id in ipairs(args.items) do
            ok = db.dbreq(sprintf('INSERT INTO rss_log (email, rss_item, read) VALUES (%s, %s, true)', db.quote(email, id)))
        end
        if not ok then
            ngx.print('{"success": false}')
        else
            ngx.print('{"success": true}')
        end
    elseif method == 'GET' then
        if persona.get_current_email() == 'tor@hveem.no' then
            local feeds = db.dbreq([[SELECT 
            rss_item.id,
            rss_item.title,
            extract(EPOCH FROM pubdate) as pubdate,
            content,
            rss_item.url,
            rss_feed.title AS feedTitle, 
            rss_feed.id AS feedId,
            COALESCE(rss_log.read::boolean, false) as read,
            COALESCE(rss_log.starred::boolean, false) as starred
            FROM rss_item
            INNER JOIN rss_feed ON (rss_item.rss_feed=rss_feed.id)
            LEFT OUTER JOIN rss_log ON ( rss_item.id = rss_log.rss_item)
            ORDER BY feedTitle
            ]])
            ngx.print(cjson.encode(feeds))
        end
    end
end


--
-- Add new feed
--
-- newsbeuter has a simple text file called urls, which we will add a line to
--
local function addfeed(match)
    -- FIXME demo/multiuser
    if persona.get_current_email() == 'tor@hveem.no' then
        ngx.req.read_body()
        -- app is sending application/json
        local args = cjson.decode(ngx.req.get_body_data())
        -- make sure it's a number
        local url = args.url
        local cat = args.cat
        -- FIXME
        ngx.print( cjson.encode({ success = true }) )
    end
    ngx.print( cjson.encode({ success = false }) )
end

--
-- Take parameters from a PUT request and overwrite the record with new values
--
local function item(match)
    local id = assert(tonumber(match[1]))
    local method = ngx.req.get_method()
    if method == 'PUT' then
        ngx.req.read_body()
        -- app is sending application/json
        local args = cjson.decode(ngx.req.get_body_data())
        local email = persona.get_current_email()
        if not email then say('{}') return end
        local res = db.dbreq(sprintf('INSERT INTO rss_log (email, rss_item) VALUES (%s, %s)', db.quote(email, id)))
        local ok
        -- check if read is set
        local read = tonumber(args.read)
        if read then 
            ok = db.dbreq([[
            UPDATE rss_log 
            SET read = ']]..read..[[' 
            WHERE rss_item = ]]..id ..[[ 
            AND email = ']]..email..[['
            ]])
        end
        -- check if starred is set
        local starred = tonumber(args.starred)
        if starred then 
            ok = db.dbreq([[
            UPDATE rss_log 
            SET starred = ']]..starred..[[' 
            WHERE rss_item = ]]..id ..[[ 
            AND email = ']]..email..[['
            ]])
        end
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
-- Spawn the refresh
--
local function refresh()
    -- TODO
end

-- TODO wrapper for login/status insert into  email (email) values ('tor@hveem.no')

-- mapping patterns to views
local routes = {
    ['feeds/$']     = feeds,
    ['addfeed/$']     = addfeed,
    ['items/?$'] = items,
    ['items/(\\d+)/?$'] = item,
    ['refresh/$']     = refresh,
    ['persona/verify$']  = persona.login,
    ['persona/logout$']  = persona.logout,
    ['persona/status$']  = persona.status,
}
-- Set the content type
ngx.header.content_type = 'application/json';

local BASE = '/nyfyk/api/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        if persona.get_current_email() == 'tor@hveem.no' then
            DBPATH = '/home/xt/.newsbeuter/cache.db'
        end
        exit = view(match) or ngx.HTTP_OK
        -- finish up
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )


