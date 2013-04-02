local dbi = require 'DBI'
local cjson = require "cjson"
local os = require 'os'
local persona = require 'persona'
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local say = ngx.say

local DBPATH = '/home/xt/src/nyfyk/db/newsbeuter.db'
-- sqlite
local dbh  = nil


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
        if url and cat then
            URLSPATH = '/home/xt/.newsbeuter/urls'
            -- append mode
            file = io.open(URLSPATH, 'a+')
            if file then -- maybe no permission ?
                file:write(url..' "'..cat..'"\n')
                file:close()
                ngx.print( cjson.encode({ success = true }) )
            end
        end
    end
    ngx.print( cjson.encode({ success = false }) )
end

--
-- Take parameters from a PUT request and overwrite the record with new values
--
local function item(match)
    local id = assert(tonumber(match[1]))
    local method = ngx.req.get_method()
    -- TODO check for parameter (unread)
    if method == 'PUT' then
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
    
    if persona.get_current_email() == 'tor@hveem.no' then
        cmd = 'newsbeuter -u /home/xt/.newsbeuter/urls -c /home/xt/.newsbeuter/cache.db -x reload'
    end
    ngx.print(cmd)
    local exec = os.execute(cmd)
    ngx.print(exec)
end


-- mapping patterns to views
local routes = {
    ['feeds/$']     = feeds,
    ['addfeed/$']     = addfeed,
    ['items/?$'] = allitems,
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
        dbh = assert(DBI.Connect('SQLite3', DBPATH, nil, nil, nil, nil))
        dbh:autocommit(true)
        exit = view(match) or ngx.HTTP_OK
        -- finish up
        --local ok = dbh:commit()
        local ok = dbh:close()
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )


