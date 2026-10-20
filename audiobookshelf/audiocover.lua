-- Cover artwork for downloaded audiobooks. Pure: the ABS api and a small
-- filesystem table are injected. The cover is stored as cover.jpg in the book's
-- folder, from where both our book page and KinAMP's player can use it.
local M = { WIDTH = 600 }

local function isJpeg(data)
    -- JPEG magic plus enough bytes to be a real image, not an error page.
    return type(data) == "string" and #data > 100 and data:sub(1, 2) == "\255\216"
end

function M.path(entry)
    if type(entry) ~= "table" or not entry.dir then return nil end
    return entry.dir .. "/cover.jpg"
end

-- JPEG bytes from ABS, or nil.
function M.fetch(api, item_id)
    local data = api:getCoverBytes(item_id, M.WIDTH)
    if isJpeg(data) then return data end
    return nil
end

-- Make sure the cover file exists; returns its path, or nil when there is none.
function M.ensure(entry, api, fs)
    local path = M.path(entry)
    if not path then return nil end
    if (fs.size(path) or 0) > 100 then return path end
    local data = M.fetch(api, entry.item_id)
    if not data then return nil end
    if not fs.write_bytes(path, data) then return nil end
    return path
end

-- Bytes to show on the book page: the downloaded file when there is one,
-- otherwise straight from ABS (the book may not be downloaded yet).
function M.bytes(entry, item_id, api, fs)
    local path = M.path(entry)
    if path and (fs.size(path) or 0) > 100 then
        local data = fs.read_bytes(path)
        if isJpeg(data) then return data end
    end
    return M.fetch(api, item_id)
end

return M
