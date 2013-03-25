local dbi = require 'DBI'
local cjson = require "cjson"
local os = require 'os'

local DBPATH = '/home/xt/src/nyfyk/db/newsbeuter.db'
if ngx.var.remote_addr == "172.16.36.100" then
    DBPATH = '/home/xt/.newsbeuter/cache.db'
end
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
        -- TODO check for parameter (unread) ?
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
        local sth, ok, err = dbexec([[
            UPDATE rss_item SET unread = 0 WHERE id = ]]..id ..[[ LIMIT 1 ]]
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
    
    if ngx.var.remote_addr == "172.16.36.100" then
        cmd = 'newsbeuter -u /home/xt/.newsbeuter/urls -c /home/xt/.newsbeuter/cache.db -x reload'
    end
    ngx.print(cmd)
    local exec = os.execute(cmd)
    ngx.print(exec)
end


-- mapping patterns to views
local routes = {
    ['feeds/$']     = feeds,
    ['items/?$'] = allitems,
    ['items/(\\d+)/?$'] = item,
    ['refresh/$']     = refresh,
}
-- Set the content type
ngx.header.content_type = 'application/json';

local BASE = '/nyfyk/api/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
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


