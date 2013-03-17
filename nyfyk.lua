local dbi = require 'DBI'
local cjson = require "cjson"

local dbh  = nil

local function dbget(sql) 
    local sth, err = dbh:prepare(sql)
    if err then 
        ngx.print(err)
        return
    end
    local ok, err = sth:execute()
    local ret = {}
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
    local idx = tonumber(idx[1])
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
local function allitems()
    local feeds = dbget('SELECT guid,title,author,url,pubDate,content,unread,feedurl,enclosure_url,enclosure_type,enqueued,flags,base FROM rss_item WHERE deleted = 0 ORDER BY pubDate DESC, id DESC limit 10;"')
    ngx.print(cjson.encode(feeds))
end

local function feeds()
    local sql = dbget('SELECT * FROM rss_feed')
    ngx.print(cjson.encode(sql))
end


-- mapping patterns to views
local routes = {
    ['feeds/$']     = feeds,
    ['items/(\\d+)/?$']     = items,
    ['items/?$'] = allitems,
}
-- Set the content type
ngx.header.content_type = 'application/json';

local BASE = '/nyfyk/api/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        dbh = assert(DBI.Connect('SQLite3', '/home/xt/src/nyfyk/newsbeuter.db', nil, nil, nil, nil))
        exit = view(match) or ngx.HTTP_OK
        -- finish up
        local ok = dbh:close()
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )


