local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookDetailsWidget = require("audiobookshelf/bookdetailswidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")

local AudiobookshelfBrowser = Menu:extend{
    no_title = false,
    title = _("Audiobookshelf Browser"),
    is_popout = false,
    is_borderless = true,
    title_bar_left_icon = "appbar.settings",
    show_parent = nil
}

-- levels:
-- abs
-- library
function AudiobookshelfBrowser:init()
    self.abs_settings = LuaSettings:open("plugins/audiobookshelf.koplugin/audiobookshelf_config.lua")
    self.abs_settings:saveSetting("token", self.abs_settings:readSetting("token"))
    self.abs_settings:flush()
    self.show_parent = self
    self.level = "abs"
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

function AudiobookshelfBrowser:onLeftButtonTap()
    if self.level == "abs" then
        self:configAudiobookshelf()
    elseif self.level == "library" then
        self:ShowSearch()
    end
end

function AudiobookshelfBrowser:configAudiobookshelf()
    local hint_server = "Audiobookshelf Server Url"
    local text_server = self.abs_settings:readSetting("server", "")
    local hint_token = "Audiobookshelf API Token"
    local text_token = self.abs_settings:readSetting("token", "")
    local title = "Audiobookshelf Settings"
    self.settings_dialog = MultiInputDialog:new {
        title = title,
        fields = {
            {
                text = text_server,
                input_type = "string",
                hint = hint_server
            },
            {
                text = text_token,
                input_type = "string",
                hint = hint_token
            }
        },
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = "Save",
                    callback = function()
                        local fields = self.settings_dialog:getFields()
                        logger.warn(fields)

                        self.abs_settings:saveSetting("server", fields[1])
                        self.abs_settings:saveSetting("token", fields[2])
                        self.abs_settings:flush()

                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)

                        UIManager:show(InfoMessage:new{
                            text = "Settings saved",
                            timeout = 1
                        })
                    end
                }
            }
        }
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function AudiobookshelfBrowser:ShowSearch()
    self.search_dialog = InputDialog:new{
        title = "Search",
        input = self.search_value,
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    enabled = true,
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end
                },
                {
                    text = "Search",
                    enabled = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        self:search()
                    end
                }
            }
        }
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function AudiobookshelfBrowser:search()
    if self.search_value then
        self.search_dialog:onClose()
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 then
            self:loadLibrarySearch(self.search_value)
        end
    end
end

function AudiobookshelfBrowser:loadLibrarySearch(search)
    local tbl = {}
    local libraryItems = AudiobookshelfApi:getSearchResults(self.library_id, search)
    logger.warn(libraryItems)
    for _, item in ipairs(libraryItems.book) do
        table.insert(tbl, {
            id = item.libraryItem.id,
            text = item.libraryItem.media.metadata.title,
            mandatory = item.libraryItem.media.metadata.authorName,
            type = "book"
        })
    end

    self:setTitleBarLeftIcon("appbar.search")
    self:switchItemTable("Search Results", tbl)
end

function AudiobookshelfBrowser:openLibrary(id, name)
    local tbl = {}
    local libraryItems = AudiobookshelfApi:getLibraryItems(id)
    for _, item in ipairs(libraryItems) do
        table.insert(tbl, {
            id = item.id,
            text = item.media.metadata.title,
            mandatory = (string.len(item.media.metadata.authorName) > 50) and (string.sub(item.media.metadata.authorName, 1, 50) .. "...") or item.media.metadata.authorName,
            type = "book"
        })
    end

    self.library_id = id
    self.level = "library"
    self:setTitleBarLeftIcon("appbar.search")
    self:switchItemTable(name, tbl)
    return true
end




return AudiobookshelfBrowser
