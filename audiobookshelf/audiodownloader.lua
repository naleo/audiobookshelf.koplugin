-- Sequential, resumable (per file) download of one audiobook. Pure: the ABS
-- api and a small filesystem table are injected.
local Store = require("audiobookshelf/audiostore")

local Downloader = {}
local FAT_MAX = 4294967295

-- `fs` is optional: when given, files already complete on disk do not count
-- towards the space needed, so resuming a nearly finished book is not refused.
function Downloader.preflight(entry, free_bytes, fs)
    local need = 0
    for _, t in ipairs(entry.tracks) do
        if t.size and t.size > FAT_MAX then return nil, "file_too_large" end
        local have = fs and t.size and fs.size(t.path) == t.size
        if t.size and not have then need = need + t.size end
    end
    if free_bytes and need > free_bytes then return nil, "no_space" end
    return true
end

function Downloader.run(opts)
    local entry, fs, api = opts.entry, opts.fs, opts.api
    if not fs.mkdir_p(entry.dir) then return nil, "mkdir_failed" end
    local n = #entry.tracks
    for i, t in ipairs(entry.tracks) do
        -- on_progress may yield (the UI drives this loop from a coroutine and
        -- processes taps while paused), so the cancel check comes after it.
        if opts.on_progress then opts.on_progress(i, n, t) end
        if opts.cancelled and opts.cancelled() then return nil, "cancelled" end
        local size = fs.size(t.path)
        local complete = size ~= nil and (t.size == nil or size == t.size)
        if not complete then
            if size ~= nil then fs.remove(t.path) end
            local part = t.filename .. ".part"
            local part_path = entry.dir .. "/" .. part
            local code = api:downloadFile(entry.item_id, t.ino, part, entry.dir)
            if code ~= 200 then
                fs.remove(part_path)
                return nil, "download_failed:" .. tostring(code)
            end
            if t.size and fs.size(part_path) ~= t.size then
                fs.remove(part_path)
                return nil, "size_mismatch"
            end
            if not fs.rename(part_path, t.path) then return nil, "rename_failed" end
        end
    end
    if not fs.write(entry.m3u, Store.buildM3u(Store.paths(entry))) then return nil, "m3u_failed" end
    entry.complete = true
    return true
end

return Downloader
