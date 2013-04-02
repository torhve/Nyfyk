local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local say = ngx.say
local sprintf = string.format
local print = ngx.print
local cjson = require 'cjson'
local feedparser = require 'feedparser'
local gsub, strfind, strformat, strsub = string.gsub, string.find, string.format, string.sub
local db = require 'dbutil'

-- Set the content type
ngx.header.content_type = 'application/json';


local function fetch(url, feed)
    --ngx.log(ngx.ERR, 'Fetching path:'..path..', from host:'..host)
    --ngx.var.fetcher_url = host
    ngx.log(ngx.ERR, 'Fetching URL:'..url)
    local res, err = ngx.location.capture('/fetcher/', { args = { url = url } })
    return res, err, feed
end

local function save(feed, parsed)
    if not feed then return end
    if not parsed then say('FUCKUP WITH PARSING') return  end
    local quote = dbutil.escapePostgresParam
    -- check that rss_feed exists
    local feedres = db.dbreq(sprintf('SELECT * from rss_feed where rssurl = E%s', quote(feed.rssurl)))[1]
    if not feedres.id then
        say('Could not find feed with URL:'..feed.rssurl)
        return
    end
    local rss_feed = feedres.id
    -- save parsed values to rss_feed
    local title = quote(parsed.feed.title)
    local author = quote(parsed.feed.author)
    local url = quote(parsed.feed.link)

    db.dbreq(sprintf('UPDATE rss_feed SET title=%s, author=%s, url=%s, lastmodified=CURRENT_TIMESTAMP WHERE id=%s', title, author, url, rss_feed))


    --[[ insert entries
    for i, e in ipairs(parsed.entries) do
        local guid = e.guid
        if not guid then guid = e.link end
        local content = e.content
        if not content then content = e.summary end
        local sql = sprintf('INSERT INTO rss_item (rss_feed, guid, title, url, pubDate, content) VALUES (%s, %s, %s, %s, %s, E%s)', rss_feed, quote(guid), quote(e.title), quote(e.link), quote(e.updated), quote(content))
        local res = db.dbreq(sql, true)
    end]]
    return
end

local function parse(feed, body)
    local parsed = feedparser.parse(body)
    say(cjson.encode(parsed))
    if save(feed, parsed) then
        return 'Parse successful'
    else 
        return 'FUCKUP WITH SAVING'
    end

end

local function wait_and_parse(threads)
    local newthreads = {}
    for i = 1, #threads do
        local ok, res, err, feed = wait(threads[i])
        say("RES:"..cjson.encode(feed))
        if not ok then
            say(i, ":failed to run: ", res)
        else
            say(i, ":"..": status: ", res.status)
            if res.status >= 200 and res.status < 300 then
                say(i, ":"..": parsed: ", parse(feed, res.body))
            elseif res.status >= 300 and res.status < 400 then
                -- Got a redirect, spawn a new thread to fetch it
                table.insert(newthreads, spawn(fetch, res.header['Location'], feed))
                say(i, ":"..feed.rssurl..": header: ", cjson.encode(res.header))
            else 
                say(i, ":"..feed.rssurl..": header: ", cjson.encode(res.header))
            end
        end
    end
    return newthreads
end

local function refresh_feeds(feeds)

    local threads = {}

    for i, k in ipairs(feeds) do
        local url = k.rssurl;
        local match = ngx.re.match(url, '^https?://([0-9a-zA-Z-_\\.]+)/(.*)$', 'oj')
        if not match then
            ngx.log(ngx.ERR, 'Parser: No match for url:'..url)
        end
        -- FIXME port https
        local host = match[1]..':80'
        local path = match[2]
        url = 'http://' .. host .. '/' .. path
        table.insert(threads, spawn(fetch, url, k))
    end
    -- recursive resolving of threads
    while #threads > 0 do
        threads = wait_and_parse(threads)
    end
end

local function get_feeds()
    local res = db.dbreq('SELECT * FROM rss_feed');
    refresh_feeds(res)
end

local function get_missing_feeds()
    local res = db.dbreq("SELECT * FROM rss_feed where title IS NULL");
    refresh_feeds(res)
end

local function get_feed(match)
    local id = assert(tonumber(match[1]))
    local res = db.dbreq(sprintf('SELECT * FROM rss_feed WHERE id = %s', id))
    refresh_feeds(res)
end

local function addalotofurls()
    local io = require 'io'
    local file = io.open('/home/xt/.newsbeuter/urls', 'r') 
    local lines = file:lines()
    for line in lines do
        local spacespos = string.find(line, ' ')
        local spacepos = strfind(line,' ')
        local url = nil
        if not spacepos then 
            url = line 
        else 
            url = string.sub(line, 1, spacepos)
        end
        say(url)
        db.dbreq('INSERT INTO rss_feed (rssurl) VALUES ('..dbutil.escapePostgresParam(url)..')')
    end
    file:close()
end
--addalotofurls()

-- mapping patterns to views
local routes = {
    ['$']       = get_feeds,
    ['missing$'] = get_missing_feeds,
    ['(\\d+)$'] = get_feed,
}
-- Set the content type
ngx.header.content_type = 'application/json';

local BASE = '/crawl/'
-- iterate route patterns and find view
for pattern, view in pairs(routes) do
    local uri = '^' .. BASE .. pattern
    local match = ngx.re.match(ngx.var.uri, uri, "") -- regex mather in compile mode
    if match then
        exit = view(match) or ngx.HTTP_OK
        -- finish up
        ngx.exit( exit )
    end
end
-- no match, return 404
ngx.exit( ngx.HTTP_NOT_FOUND )
