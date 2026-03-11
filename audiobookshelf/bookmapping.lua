local LuaSettings = require("luasettings")
local logger = require("logger")

local BookMapping = {
    mappings_file = "plugins/audiobookshelf.koplugin/audiobookshelf_mappings.lua",
    mappings = nil,
}

function BookMapping:init()
    if self.mappings then
        return
    end
    self.mappings = LuaSettings:open(self.mappings_file)
end

function BookMapping:getMapping(filepath)
    self:init()
    local mappings = self.mappings:readSetting("mappings") or {}
    return mappings[filepath]
end

function BookMapping:setMapping(filepath, library_item_id, ebook_file_ino, title)
    self:init()
    local mappings = self.mappings:readSetting("mappings") or {}
    mappings[filepath] = {
        library_item_id = library_item_id,
        ebook_file_ino = ebook_file_ino,
        title = title,
        linked_at = os.time(),
        last_sync = nil,
    }
    self.mappings:saveSetting("mappings", mappings)
    self.mappings:flush()
    logger.dbg("BookMapping: linked", filepath, "to", library_item_id)
end

function BookMapping:updateLastSync(filepath)
    self:init()
    local mappings = self.mappings:readSetting("mappings") or {}
    if mappings[filepath] then
        mappings[filepath].last_sync = os.time()
        self.mappings:saveSetting("mappings", mappings)
        self.mappings:flush()
    end
end

function BookMapping:removeMapping(filepath)
    self:init()
    local mappings = self.mappings:readSetting("mappings") or {}
    if mappings[filepath] then
        mappings[filepath] = nil
        self.mappings:saveSetting("mappings", mappings)
        self.mappings:flush()
        logger.dbg("BookMapping: unlinked", filepath)
        return true
    end
    return false
end

function BookMapping:getAllMappings()
    self:init()
    return self.mappings:readSetting("mappings") or {}
end

return BookMapping
