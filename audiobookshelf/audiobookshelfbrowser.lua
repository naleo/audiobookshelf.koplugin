local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookDetailsWidget = require("audiobookshelf/bookdetailswidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("audiobookshelf/absi18n")
local T = require("ffi/util").template
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
    local config_file = string.gsub(debug.getinfo(1).source, "^@(.+/)[^/]+$", "%1") .. "/../audiobookshelf_config.lua"
    self.abs_settings = LuaSettings:open(config_file)
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
    if not libraries then
        UIManager:show(InfoMessage:new{
            text = _("Could not reach Audiobookshelf server. Check network and settings."),
            timeout = 2,
        })
        return item_table
    end
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
    if item.type == "filter" then
        self:showTagFilter()
    elseif item.type == "genrefilter" then
        self:showGenreFilter()
    elseif item.type == "toggleview" then
        -- Switch to mosaic view and remember it; reopen the library.
        self.abs_settings:saveSetting("view_mode", "mosaic")
        self.abs_settings:flush()
        self:openLibrary(self.library_id, self.library_name)
    elseif item.type == "library" then
        table.insert(self.paths, {
            id = item.id,
            type = "library",
            name = item.text
        })
        self:openLibrary(item.id, item.text)
    elseif item.type == "book" then
        -- No onCloseParent: the browser Menu stays open underneath, so closing
        -- the details widget returns to the book list (not all the way home).
        local bookdetailswidget = BookDetailsWidget:new{
            book_id = item.id,
        }
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
    local hint_server = _("Audiobookshelf Server Url")
    local text_server = self.abs_settings:readSetting("server", "")
    local hint_token = _("Audiobookshelf API Token")
    local text_token = self.abs_settings:readSetting("token", "")
    local title = _("Audiobookshelf Settings")
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
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.settings_dialog:getFields()
                        logger.warn(fields)

                        self.abs_settings:saveSetting("server", fields[1])
                        self.abs_settings:saveSetting("token", fields[2])
                        self.abs_settings:flush()

                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)

                        UIManager:show(InfoMessage:new{
                            text = _("Settings saved"),
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
        title = _("Search"),
        input = self.search_value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    enabled = true,
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end
                },
                {
                    text = _("Search"),
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
    if not libraryItems or not libraryItems.book then
        UIManager:show(InfoMessage:new{
            text = _("Search failed. Check network and settings."),
            timeout = 2,
        })
        return
    end
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
    self.library_id = id
    self.library_name = name

    -- Persisted filters ("" = show everything) and view mode ("list"/"mosaic").
    -- All remembered across sessions via the plugin's LuaSettings config file.
    local active_tag = self.abs_settings:readSetting("filter_tag", "")
    local active_genre = self.abs_settings:readSetting("filter_genre", "")
    local view_mode = self.abs_settings:readSetting("view_mode", "list")

    local libraryItems = AudiobookshelfApi:getLibraryItems(id, active_tag, active_genre)
    if not libraryItems then
        UIManager:show(InfoMessage:new{
            text = _("Could not load library. Check network and settings."),
            timeout = 2,
        })
        return false
    end

    -- Mosaic view: show a cover grid overlay instead of the text list.
    if view_mode == "mosaic" then
        self:showMosaic(libraryItems, 0)
        return true
    end

    local tbl = {}
    -- Age (tag) filter row.
    table.insert(tbl, {
        text = (active_tag ~= "" and T(_("⚑ Age: %1 (tap to change)"), active_tag)
                                  or _("⚑ Age: all (tap to filter)")),
        type = "filter",
    })
    -- Genre filter row.
    table.insert(tbl, {
        text = (active_genre ~= "" and T(_("♦ Genre: %1 (tap to change)"), active_genre)
                                    or _("♦ Genre: all (tap to filter)")),
        type = "genrefilter",
    })
    -- View toggle row.
    table.insert(tbl, {
        text = _("▦ View: text list (tap for covers)"),
        type = "toggleview",
    })

    for _, item in ipairs(libraryItems) do
        table.insert(tbl, {
            id = item.id,
            text = item.media.metadata.title,
            mandatory = item.media.metadata.authorName,
            type = "book"
        })
    end

    self.level = "library"
    self:setTitleBarLeftIcon("appbar.search")
    self:switchItemTable(name, tbl)
    return true
end

--[[--
Show the cover-mosaic overlay for the current library. Paging re-fetches the
same filtered item list and shows the requested page. Tapping a cover opens the
book details widget (identical to the list view's behaviour).
@param items table  library items (already tag-filtered)
@param page number  0-based page index
--]]
function AudiobookshelfBrowser:showMosaic(items, page)
    local Mosaic = require("audiobookshelf/audiobookshelfmosaic")
    local per_page = 9
    page = page or 0
    local total = #items
    local first = page * per_page + 1
    local page_items = {}
    for i = first, math.min(first + per_page - 1, total) do
        table.insert(page_items, items[i])
    end

    local active_tag = self.abs_settings:readSetting("filter_tag", "")
    local active_genre = self.abs_settings:readSetting("filter_genre", "")

    local mosaic
    mosaic = Mosaic:new{
        items = page_items,
        page = page,
        total = total,
        library_id = self.library_id,
        library_name = self.library_name,
        active_tag = active_tag,
        active_genre = active_genre,
        on_search = function()
            UIManager:close(mosaic)
            self:ShowSearch()
        end,
        on_filter = function()
            -- Close the current mosaic first; the picker reloads the library,
            -- which lands back in a fresh mosaic (view_mode persisted "mosaic").
            UIManager:close(mosaic)
            self:showTagFilter()
        end,
        on_genre_filter = function()
            UIManager:close(mosaic)
            self:showGenreFilter()
        end,
        on_open = function(item)
            -- Leave the mosaic open underneath; closing the details widget
            -- returns to the cover grid (not all the way home).
            local bookdetailswidget = BookDetailsWidget:new{
                book_id = item.id,
            }
            UIManager:show(bookdetailswidget, "flashui")
        end,
        on_page = function(new_page)
            UIManager:close(mosaic)
            self:showMosaic(items, new_page)
        end,
        on_close = function()
            UIManager:close(mosaic)
        end,
        on_toggle_list = function()
            -- Switch back to the text list and remember it.
            UIManager:close(mosaic)
            self.abs_settings:saveSetting("view_mode", "list")
            self.abs_settings:flush()
            self:openLibrary(self.library_id, self.library_name)
        end,
    }
    UIManager:show(mosaic)
    UIManager:setDirty(mosaic, "full")
end

--[[--
Show the tag picker. Lets the user pick a tag to filter the current library on
(or "all books" to clear). The choice is persisted and the library is reloaded.
--]]
function AudiobookshelfBrowser:showTagFilter()
    if not self.library_id then return end
    local tags = AudiobookshelfApi:getLibraryTags(self.library_id)
    if not tags then
        UIManager:show(InfoMessage:new{
            text = _("Could not load tags. Check network and settings."),
            timeout = 2,
        })
        return
    end
    if #tags == 0 then
        UIManager:show(InfoMessage:new{ text = _("No tags in this library."), timeout = 2 })
        return
    end

    local active = self.abs_settings:readSetting("filter_tag", "")
    local buttons = {}
    -- "All books" clears the filter
    table.insert(buttons, {{
        text = (active == "" and "● " or "○ ") .. _("All books (no filter)"),
        callback = function()
            UIManager:close(self.tag_dialog)
            self.abs_settings:saveSetting("filter_tag", "")
            self.abs_settings:flush()
            self:openLibrary(self.library_id, self.library_name)
        end,
    }})
    for _, tag in ipairs(tags) do
        local t = tag
        table.insert(buttons, {{
            text = (active == t and "● " or "○ ") .. t,
            callback = function()
                UIManager:close(self.tag_dialog)
                self.abs_settings:saveSetting("filter_tag", t)
                self.abs_settings:flush()
                self:openLibrary(self.library_id, self.library_name)
            end,
        }})
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    self.tag_dialog = ButtonDialog:new{
        title = _("Filter by age"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.tag_dialog)
end

--[[--
Show the genre picker. Lets the user pick a genre to filter the current library
on (or "all genres" to clear). The choice is persisted and the library reloaded.
The genre filter combines with the age filter (age is server-side, genre is
applied client-side).
--]]
function AudiobookshelfBrowser:showGenreFilter()
    if not self.library_id then return end
    local genres = AudiobookshelfApi:getLibraryGenres(self.library_id)
    if not genres then
        UIManager:show(InfoMessage:new{
            text = _("Could not load genres. Check network and settings."),
            timeout = 2,
        })
        return
    end
    if #genres == 0 then
        UIManager:show(InfoMessage:new{ text = _("No genres in this library."), timeout = 2 })
        return
    end

    local active = self.abs_settings:readSetting("filter_genre", "")
    local buttons = {}
    table.insert(buttons, {{
        text = (active == "" and "● " or "○ ") .. _("All genres (no filter)"),
        callback = function()
            UIManager:close(self.genre_dialog)
            self.abs_settings:saveSetting("filter_genre", "")
            self.abs_settings:flush()
            self:openLibrary(self.library_id, self.library_name)
        end,
    }})
    for _, genre in ipairs(genres) do
        local g = genre
        table.insert(buttons, {{
            text = (active == g and "● " or "○ ") .. g,
            callback = function()
                UIManager:close(self.genre_dialog)
                self.abs_settings:saveSetting("filter_genre", g)
                self.abs_settings:flush()
                self:openLibrary(self.library_id, self.library_name)
            end,
        }})
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    self.genre_dialog = ButtonDialog:new{
        title = _("Filter by genre"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.genre_dialog)
end

return AudiobookshelfBrowser
