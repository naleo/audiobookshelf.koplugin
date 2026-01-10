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

local AudiobookshelfApi = {
    abs_settings = LuaSettings:open("plugins/audiobookshelf.koplugin/audiobookshelf_config.lua")
}

-- Execute an API request and return response body and code
-- opts: { method, path, body, timeout_block, timeout_total, sink }
function AudiobookshelfApi:request(opts)
    local sink = opts.sink or {}
    local use_table_sink = not opts.sink

    local headers = {
        ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
        ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
    }
    if opts.body then
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = #opts.body
    end

    local request = {
        url = self.abs_settings:readSetting("server") .. opts.path,
        method = opts.method or "GET",
        headers = headers,
        sink = use_table_sink and ltn12.sink.table(sink) or opts.sink,
    }
    if opts.body then
        request.source = ltn12.source.string(opts.body)
    end

    if opts.timeout_block then
        socketutil:set_timeout(opts.timeout_block, opts.timeout_total)
    else
        socketutil:set_timeout()
    end

    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    socketutil:reset_timeout()

    if not ok then
        return nil, nil, "network_error"
    end

    local response = use_table_sink and table.concat(sink) or nil
    return response, code, status
end

-- Execute a GET request and decode JSON response
function AudiobookshelfApi:get(path, opts)
    opts = opts or {}
    opts.path = path
    opts.method = "GET"
    local response, code, status = self:request(opts)

    if not response then
        logger.warn("AudiobookshelfApi: request failed:", path, status)
        return nil, "network_error"
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result, code
    end
    if code == 404 then
        return nil, "not_found"
    end
    logger.warn("AudiobookshelfApi:", path, status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil, "api_error"
end

function AudiobookshelfApi:getLibraries()
    local result = self:get("/api/libraries")
    return result and result.libraries
end

function AudiobookshelfApi:getLibraryItems(id)
    -- "ebooks." + base64("ebook") url-encoded to filter for ebooks only
    local filters = "ebooks.ZWJvb2s%3D"
    local result = self:get("/api/libraries/" .. id .. "/items?filter=" .. filters .. "&sort=media.metadata.title&limit=0")
    return result and result.results
end

function AudiobookshelfApi:getLibraryItem(id)
    return self:get("/api/items/" .. id .. "?expanded=1")
end

function AudiobookshelfApi:downloadFile(id, ino, filename, local_path)
    local outfile, err = io.open(local_path .. "/" .. filename, "w")
    if not outfile then
        logger.warn("AudiobookshelfApi: cannot open local file for writing:", local_path .. "/" .. filename, err)
        return nil
    end

    local _, code = self:request({
        path = "/api/items/" .. id .. "/file/" .. ino .. "/download",
        sink = ltn12.sink.file(outfile),
        timeout_block = socketutil.FILE_BLOCK_TIMEOUT,
        timeout_total = socketutil.FILE_TOTAL_TIMEOUT,
    })

    if code ~= 200 then
        logger.warn("AudiobookshelfApi: cannot download file:", id, ino, code)
    end
    return code
end

function AudiobookshelfApi:getLibraryItemCover(id)
    local response, code = self:request({ path = "/api/items/" .. id .. "/cover?format=webp" })
    if code == 200 and response and response ~= "" then
        return RenderImage:renderImageData(response, #response)
    end
    logger.warn("AudiobookshelfApi: cannot get cover", id, code)
    return nil
end

function AudiobookshelfApi:getSearchResults(id, search_query)
    local filters = "ebooks.ZWJvb2s%3D"
    local path = "/api/libraries/" .. id .. "/search?q=" .. util.urlEncode(search_query) .. "&filter=" .. filters
    return self:get(path)
end

function AudiobookshelfApi:getProgress(library_item_id)
    return self:get("/api/me/progress/" .. library_item_id, { timeout_block = 5, timeout_total = 10 })
end

function AudiobookshelfApi:updateProgress(library_item_id, progress_data)
    local body = JSON.encode(progress_data)
    local response, code, status = self:request({
        path = "/api/me/progress/" .. library_item_id,
        method = "PATCH",
        body = body,
        timeout_block = 5,
        timeout_total = 10,
    })

    if not response then
        logger.warn("AudiobookshelfApi: updateProgress failed:", status)
        return nil, "network_error"
    end
    if code == 200 then
        local _, result = pcall(JSON.decode, response)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot update progress", library_item_id, code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil, "api_error"
end

return AudiobookshelfApi