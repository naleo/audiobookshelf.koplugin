local Dispatcher = require("dispatcher")
local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local AudiobookshelfBrowser = require("audiobookshelf/audiobookshelfbrowser")
local BookMapping = require("audiobookshelf/bookmapping")
local ProgressSync = require("audiobookshelf/progresssync")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LuaSettings = require("luasettings")
local _ = require("gettext")
local logger = require("logger")

local Audiobookshelf = WidgetContainer:extend{
    name = "audiobookshelf",
    is_doc_only = false,
    settings = nil,
}

function Audiobookshelf:onDispatcherRegisterActions()
    Dispatcher:registerAction("abs_push_progress", {
        category = "none",
        event = "ABSPushProgress",
        title = _("Push progress to Audiobookshelf"),
        general = true,
    })
    Dispatcher:registerAction("abs_pull_progress", {
        category = "none",
        event = "ABSPullProgress",
        title = _("Pull progress from Audiobookshelf"),
        general = true,
    })
end

function Audiobookshelf:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:loadSettings()

    if self.ui.document then
        self:initSyncForDocument()
    end
end

function Audiobookshelf:loadSettings()
    self.settings = LuaSettings:open("plugins/audiobookshelf.koplugin/audiobookshelf_config.lua")
end

function Audiobookshelf:getSyncSettings()
    if not self.settings then
        self:loadSettings()
    end
    return self.settings:readSetting("sync") or {
        enabled = true,
        auto_push_on_close = true,
        auto_push_on_page_turn = true,
        page_threshold = 5,
        auto_pull_on_open = true,
        show_notifications = true,
    }
end

function Audiobookshelf:saveSyncSetting(key, value)
    local sync_settings = self:getSyncSettings()
    sync_settings[key] = value
    self.settings:saveSetting("sync", sync_settings)
    self.settings:flush()
end

function Audiobookshelf:initSyncForDocument()
    ProgressSync:init(self.ui)
    ProgressSync:loadMappingForDocument()
end

function Audiobookshelf:onReaderReady()
    self:initSyncForDocument()

    local sync_settings = self:getSyncSettings()
    if sync_settings.auto_pull_on_open and ProgressSync.current_mapping then
        UIManager:scheduleIn(0.5, function()
            ProgressSync:checkAndPromptServerProgress(false)
        end)
    end
end

function Audiobookshelf:onPageUpdate(pageno)
    local sync_settings = self:getSyncSettings()
    ProgressSync:onPageTurn(sync_settings)
end

function Audiobookshelf:onCloseDocument()
    local sync_settings = self:getSyncSettings()
    if sync_settings.auto_push_on_close and ProgressSync.current_mapping then
        ProgressSync:pushProgress(true)
    end
    ProgressSync:reset()
end

function Audiobookshelf:onABSPushProgress()
    if not ProgressSync.current_mapping then
        UIManager:show(InfoMessage:new{
            text = _("This book is not linked to Audiobookshelf."),
            timeout = 3,
        })
        return true
    end

    ProgressSync:pushProgress(true, function(success, err)
        if success then
            UIManager:show(InfoMessage:new{
                text = _("Progress pushed to server."),
                timeout = 2,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed to push progress."),
                timeout = 3,
            })
        end
    end)
    return true
end

function Audiobookshelf:onABSPullProgress()
    if not ProgressSync.current_mapping then
        UIManager:show(InfoMessage:new{
            text = _("This book is not linked to Audiobookshelf."),
            timeout = 3,
        })
        return true
    end

    ProgressSync:checkAndPromptServerProgress(true)
    return true
end

function Audiobookshelf:addToMainMenu(menu_items)
    menu_items.audiobookshelf = {
        text = _("Audiobookshelf"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Browse library"),
                callback = function()
                    UIManager:show(AudiobookshelfBrowser:new())
                end,
                separator = true,
            },
            {
                text = _("Push progress now"),
                enabled_func = function()
                    return ProgressSync.current_mapping ~= nil
                end,
                callback = function()
                    self:onABSPushProgress()
                end,
            },
            {
                text = _("Pull progress now"),
                enabled_func = function()
                    return ProgressSync.current_mapping ~= nil
                end,
                callback = function()
                    self:onABSPullProgress()
                end,
            },
            {
                text_func = function()
                    if ProgressSync.current_mapping then
                        return _("Linked: ") .. (ProgressSync.current_mapping.title or "Unknown")
                    else
                        return _("Not linked to Audiobookshelf")
                    end
                end,
                enabled_func = function()
                    return self.ui.document ~= nil
                end,
                callback = function()
                    if ProgressSync.current_mapping then
                        self:showUnlinkDialog()
                    else
                        self:showLinkDialog()
                    end
                end,
                separator = true,
            },
            {
                text = _("Sync settings"),
                sub_item_table = self:getSyncSettingsMenu(),
            },
        },
    }
end

function Audiobookshelf:getSyncSettingsMenu()
    return {
        {
            text = _("Auto-push on book close"),
            checked_func = function()
                return self:getSyncSettings().auto_push_on_close
            end,
            callback = function()
                local current = self:getSyncSettings().auto_push_on_close
                self:saveSyncSetting("auto_push_on_close", not current)
            end,
        },
        {
            text = _("Auto-push on page turns"),
            checked_func = function()
                return self:getSyncSettings().auto_push_on_page_turn
            end,
            callback = function()
                local current = self:getSyncSettings().auto_push_on_page_turn
                self:saveSyncSetting("auto_push_on_page_turn", not current)
            end,
        },
        {
            text_func = function()
                local threshold = self:getSyncSettings().page_threshold or 5
                return _("Pages before sync: ") .. threshold
            end,
            callback = function()
                local current = self:getSyncSettings().page_threshold or 5
                local spin_widget = SpinWidget:new{
                    title_text = _("Pages before sync"),
                    info_text = _("Sync progress after this many page turns."),
                    value = current,
                    value_min = 1,
                    value_max = 50,
                    value_step = 1,
                    default_value = 5,
                    callback = function(spin)
                        self:saveSyncSetting("page_threshold", spin.value)
                    end,
                }
                UIManager:show(spin_widget)
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text = _("Auto-pull on book open"),
            checked_func = function()
                return self:getSyncSettings().auto_pull_on_open
            end,
            callback = function()
                local current = self:getSyncSettings().auto_pull_on_open
                self:saveSyncSetting("auto_pull_on_open", not current)
            end,
        },
    }
end

function Audiobookshelf:showUnlinkDialog()
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = _("Unlink this book from Audiobookshelf?\n\nProgress will no longer sync for this book."),
        ok_text = _("Unlink"),
        ok_callback = function()
            if self.ui.document then
                BookMapping:removeMapping(self.ui.document.file)
                ProgressSync.current_mapping = nil
                UIManager:show(InfoMessage:new{
                    text = _("Book unlinked."),
                    timeout = 2,
                })
            end
        end,
    })
end

function Audiobookshelf:showLinkDialog()
    if not self.ui.document then
        return
    end

    local doc_props = self.ui.document:getProps()
    local default_search = doc_props.title or self.ui.document.file:match("([^/]+)%.[^.]+$") or ""

    self.link_dialog = InputDialog:new{
        title = _("Search Audiobookshelf to link this book"),
        input = default_search,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.link_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = self.link_dialog:getInputText()
                        UIManager:close(self.link_dialog)
                        if query and #query > 0 then
                            self:searchAndShowLinkResults(query)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.link_dialog)
    self.link_dialog:onShowKeyboard()
end

function Audiobookshelf:searchAndShowLinkResults(query)
    local libraries = AudiobookshelfApi:getLibraries()
    if not libraries or #libraries == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Could not connect to Audiobookshelf. Check settings."),
            timeout = 3,
        })
        return
    end

    local all_results = {}
    for _, library in ipairs(libraries) do
        local results = AudiobookshelfApi:getSearchResults(library.id, query)
        if results and results.book then
            for _, item in ipairs(results.book) do
                -- Only include items that have an ebook file
                if item.libraryItem.media and item.libraryItem.media.ebookFile then
                    table.insert(all_results, {
                        id = item.libraryItem.id,
                        title = item.libraryItem.media.metadata.title,
                        author = item.libraryItem.media.metadata.authorName,
                    })
                end
            end
        end
    end

    if #all_results == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No books found. Try a different search."),
            timeout = 3,
        })
        return
    end

    self:showLinkResultsDialog(all_results)
end

function Audiobookshelf:showLinkResultsDialog(results)
    local buttons = {}

    for i, result in ipairs(results) do
        if i > 10 then break end
        table.insert(buttons, {
            {
                text = result.title .. "\n" .. (result.author or ""),
                callback = function()
                    UIManager:close(self.results_dialog)
                    self:linkToBook(result.id, result.title)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(self.results_dialog)
            end,
        },
    })

    self.results_dialog = ButtonDialogTitle:new{
        title = _("Select book to link"),
        buttons = buttons,
    }
    UIManager:show(self.results_dialog)
end

function Audiobookshelf:linkToBook(library_item_id, title)
    if not self.ui.document then
        return
    end

    local filepath = self.ui.document.file
    BookMapping:setMapping(filepath, library_item_id, nil, title)
    ProgressSync:loadMappingForDocument()

    UIManager:show(InfoMessage:new{
        text = _("Book linked to: ") .. title,
        timeout = 2,
    })
end

return Audiobookshelf
