local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local say = ngx.say
local sprintf = string.format
local print = ngx.print
local cjson = require 'cjson'
local feedparser = require 'feedparser'
local gsub, strfind, strformat = string.gsub, string.find, string.format

-- Set the content type
ngx.header.content_type = 'application/json';

function trim(s)
  if not s then return '' end
  
  return (s:gsub('^%s*(.-)%s*$', '%1'))
end

function escapePostgresParam(...)
  local url      = '/postgresescape?param='
  local requests = {}
  
  for i = 1, select('#', ...) do
    local param = ngx.escape_uri((select(i, ...)))
    
    table.insert(requests, {url .. param})
  end
  
  local results = {ngx.location.capture_multi(requests)}
  for k, v in pairs(results) do
    results[k] = trim(v.body)
  end
  
  return unpack(results)
end

-- The function sending subreq to nginx postgresql location with rds_json on
-- returns json body to the caller
local function dbreq(sql, donotdecode)
    ngx.log(ngx.ERR, '-*- SQL -*-: ' .. sql)

    local params = {
        method = ngx.HTTP_POST,
        body   = sql
    }
    local result = ngx.location.capture("/pg", params)
    if result.status ~= ngx.HTTP_OK or not result.body then
        return nil
    end
    local body = result.body
    if donotdecode then
        return body
    end
    return (cjson.decode(body) or {})
end

local function fetch(url, feed)
    --ngx.log(ngx.ERR, 'Fetching path:'..path..', from host:'..host)
    --ngx.var.fetcher_url = host
    ngx.log(ngx.ERR, 'Fetching URL:'..url)
    local res, err = ngx.location.capture('/fetcher/', { args = { url = url } })
    return res, err, feed
end

local function save(feed, parsed)
    if not feed then return end
    local quote = escapePostgresParam
    -- update rss_feed
    local feedres = dbreq(sprintf('SELECT * from rss_feed where rssurl = E%s', quote(feed.rssurl)))[1]
    if not feedres.id then
        say('Could not find feed with URL:'..feed.rssurl)
        return
    end
    say('got ID' .. tostring(feedres.id))
    local rss_feed = feedres.id

    -- insert entries
    for i, e in ipairs(parsed.entries) do
        local guid = e.guid
        if not guid then guid = e.link end
        local content = e.content
        if not content then content = e.summary end
        local sql = sprintf('INSERT INTO rss_item (rss_feed, guid, title, url, pubDate, content) VALUES (%s, %s, %s, %s, %s, E%s)', rss_feed, quote(guid), quote(e.title), quote(e.link), quote(e.updated), quote(content))
        local res = dbreq(sql, true)
    end
end

local function parse(feed, body)
    local parsed = feedparser.parse(body)
    say(cjson.encode(parsed))
    save(feed, parsed)
    return 'Parse successful'
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
    local res = dbreq('SELECT * FROM rss_feed');
    refresh_feeds(res)
end
get_feeds()
