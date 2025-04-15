local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookDetailsWidget = require("audiobookshelf/bookdetailswidget")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local AudiobookshelfBrowser = Menu:extend{
    no_title= false,
    title = _("Audiobookshelf Browser"),
    is_popout = false,
    is_borderless = true,
    show_parent = nil
}

function AudiobookshelfBrowser:init()
    self.show_parent = self
    if self.item then
    else
        self.item_table = self:genItemTableFromLibraries()
    end
    Menu.init(self)
end

function AudiobookshelfBrowser:genItemTableFromLibraries()
    local item_table = {}
    local libraries = AudiobookshelfApi:getLibraries()
    for _, library in ipairs(libraries) do
        table.insert(item_table, {
            text = library.name,
            type = "library",
            id = library.id,
        })
    end
    return item_table
end

function AudiobookshelfBrowser:getItemTableFromLibrary()
    logger.log("hi")
end

function AudiobookshelfBrowser:onMenuSelect(item)
    if item.type == "library" then
        table.insert(self.paths, {
            id = item.id,
            type = "library",
            name = item.text
        })
        self:openLibrary(item.id, item.text)
    elseif item.type == "book" then
        local bookdetailswidget = BookDetailsWidget:new{ book_id = item.id, onCloseParent = self.onClose }
        UIManager:show(bookdetailswidget, "flashui")
    end
        return true
end

function AudiobookshelfBrowser:openLibrary(id, name)
    local tbl = {}
    local libraryItems = AudiobookshelfApi:getLibraryItems(id)
    for _, item in ipairs(libraryItems) do
        table.insert(tbl, {
            id = item.id,
            text = item.media.metadata.title,
            mandatory = item.media.metadata.authorName,
            url = "test",
            type = "book"
        })
    end

    self:switchItemTable(name, tbl)
    return true
end

return AudiobookshelfBrowser
