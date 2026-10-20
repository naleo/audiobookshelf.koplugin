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

function AudiobookshelfApi:getLibraryItems(id, opts)
    local sink = {}
    -- "ebooks" base64 encoded, then URL encoded, to only return items with ebooks.
    -- Audio mode lists every item and lets the details page decide.
    local filter = (opts and opts.audio) and "" or "filter=ebooks.ZWJvb2s%3D&"
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/items?" .. filter .. "sort=media.metadata.title&limit=0",
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

function AudiobookshelfApi:getSearchResults(id, search_query, opts)
    local sink = {}
    local url_encoded_search_string = util.urlEncode(search_query)
    -- "ebooks" base64 encoded, then URL encoded, to only return items with ebooks.
    local filter = (opts and opts.audio) and "" or "&filter=ebooks.ZWJvb2s%3D"
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/search?q=" .. url_encoded_search_string .. filter,
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

-- Raw cover image bytes (a JPEG, resized by the server) or nil on any failure.
function AudiobookshelfApi:getCoverBytes(id, width)
    local server = self.abs_settings:readSetting("server")
    local token = self.abs_settings:readSetting("token")
    if not server or not token then return nil end
    local sink = {}
    local request = {
        url = server .. "/api/items/" .. id .. "/cover?format=jpeg&width=" .. tostring(width or 600),
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. token,
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if ok and code == 200 and response ~= "" then return response end
    logger.warn("AudiobookshelfApi: could not get cover bytes for", id, ok and code or "request failed")
    return nil
end

-- Generic JSON request. Returns (table, code) on 200/204, (nil, code) on any
-- other status and (nil, nil) when the request itself failed (unreachable).
-- ABS answers progress writes with plain "OK", which is not JSON, so a 200 with
-- an unparsable body yields an empty table.
function AudiobookshelfApi:_json(method, path, body)
    local sink = {}
    local server = self.abs_settings:readSetting("server")
    local token = self.abs_settings:readSetting("token")
    if not server or not token then
        logger.warn("AudiobookshelfApi: server or token not configured")
        return nil, nil
    end
    local headers = {
        ["Authorization"] = "Bearer " .. token,
        ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
    }
    local request = {
        url = server .. path,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(sink),
    }
    if body then
        local payload = JSON.encode(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#payload)
        request.source = ltn12.source.string(payload)
    end
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in _json:", method, path, code)
        return nil, nil
    end
    if code == 200 or code == 204 then
        if response ~= "" then
            local decoded_ok, result = pcall(JSON.decode, response, JSON.decode.simple)
            if decoded_ok and type(result) == "table" then return result, code end
        end
        return {}, code
    end
    logger.warn("AudiobookshelfApi: unexpected status in _json:", method, path, status or code)
    return nil, code
end

function AudiobookshelfApi:getProgress(item_id)
    return self:_json("GET", "/api/me/progress/" .. item_id)
end

function AudiobookshelfApi:setProgress(item_id, body)
    local result = self:_json("PATCH", "/api/me/progress/" .. item_id, body)
    return result ~= nil
end

return AudiobookshelfApi
