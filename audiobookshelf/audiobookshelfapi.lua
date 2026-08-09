local config = require("audiobookshelf_config")
local T = require("ffi/util").template
local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local socket = require("socket")
local logger = require("logger")
local RenderImage = require("ui/renderimage")
local util = require("util")
local LuaSettings = require("luasettings")

local VERSION = require("audiobookshelf_version")

local config_file = string.gsub(debug.getinfo(1).source, "^@(.+/)[^/]+$", "%1") .. "/../audiobookshelf_config.lua"
local AudiobookshelfApi = {
    abs_settings = LuaSettings:open(config_file)
}

function AudiobookshelfApi:getLibraries()
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraries:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response)
        return result.libraries
    end
    logger.warn("AudiobookshelfApi: cannot get libraries", status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

--[[--
Get items in a library.
@param id string          library id
@param tag string|nil     optional tag name; when set, only items carrying this
                          tag are returned (server-side filter). "" or nil = all.
--]]
function AudiobookshelfApi:getLibraryItems(id, tag)
    local sink = {}
    -- Server-side filter. The ABS filter value is base64(<value>) URL-encoded.
    -- Default keeps the original "ebooks" filter (only items that have an ebook
    -- file). If a tag is given, filter on that tag instead so excluded books
    -- never come back over the wire.
    local mime = require("mime")
    local filters
    if tag and tag ~= "" then
        filters = "tags." .. util.urlEncode(mime.b64(tag))
    else
        -- "ebooks" -> base64 "ZWJvb2s=" -> URL-encoded
        filters = "ebooks." .. "ZWJvb2s%3D"
    end
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/items?filter=" .. filters .. "&sort=media.metadata.title&limit=0",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItems:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result.results
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

--[[--
Get the list of tags available in a library (for the tag filter picker).
@param id string  library id
@return table|nil  array of tag names, or nil on failure
--]]
function AudiobookshelfApi:getLibraryTags(id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/filterdata",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryTags:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result and result.tags or {}
    end
    logger.warn("AudiobookshelfApi: cannot get filterdata for library", id, status or code)
    return nil
end

function AudiobookshelfApi:getLibraryItem(id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "?expanded=1",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItem:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library item", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:downloadFile(id, ino, filename, local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local outfile, err = io.open(local_path .. "/" .. filename, "w")
    if not outfile then
        logger.warn("AudiobookshelfApi: cannot open local file for writing:", local_path .. "/" .. filename, err)
        socketutil:reset_timeout()
        return nil
    end
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "/file/" .. ino .. "/download",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.file(outfile),
    }
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then
        logger.warn("AudiobookshelfApi: cannot download file:", id , ino, status or code)
    end
    return code
end

function AudiobookshelfApi:getLibraryItemCover(id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "/cover?format=webp",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItemCover:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local result = RenderImage:renderImageData(response, #response)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library item cover", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

--[[--
Get a cover thumbnail for an item, cached on disk so the mosaic view does not
re-download covers on every page render. Returns a local file path or nil.
Uses a small server-side resized JPEG (width=240) to keep files tiny.
@param id string  library item id
@return string|nil  local file path to the cached cover jpg
--]]
function AudiobookshelfApi:getCachedCoverPath(id)
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local cache_dir = DataStorage:getDataDir() .. "/cache/absmosaic"
    if not lfs.attributes(cache_dir, "mode") then
        os.execute(string.format('mkdir -p "%s"', cache_dir))
    end
    local path = cache_dir .. "/" .. id .. ".jpg"

    -- Reuse a cached file if it looks valid (non-trivial size).
    local attr = lfs.attributes(path)
    if attr and attr.size and attr.size > 512 then
        return path
    end

    -- Download a resized cover to disk.
    local outfile, oerr = io.open(path, "wb")
    if not outfile then
        logger.warn("AudiobookshelfApi: cannot open cover cache file:", path, oerr)
        return nil
    end
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "/cover?width=240&format=jpeg",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.file(outfile),
    }
    socketutil:set_timeout()
    local ok, code = pcall(function() return socket.skip(1, http.request(request)) end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then
        logger.warn("AudiobookshelfApi: cover download failed:", id, code)
        os.remove(path)
        return nil
    end
    local attr2 = lfs.attributes(path)
    if not attr2 or not attr2.size or attr2.size < 512 then
        os.remove(path)
        return nil
    end
    return path
end

function AudiobookshelfApi:getSearchResults(id, search_query)
    local sink = {}
    local url_encoded_search_string = util.urlEncode(search_query)
    -- this is "ebooks" base64 encoded, and the URL encoded, to only return library items with ebooks
    local filters = "ebooks." .. "ZWJvb2s%3D"
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/search?q=" .. url_encoded_search_string .. "&filter=" .. filters,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getSearchResults:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot search library", id ,search_query, status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

return AudiobookshelfApi
