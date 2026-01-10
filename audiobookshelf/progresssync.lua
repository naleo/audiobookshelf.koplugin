local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookMapping = require("audiobookshelf/bookmapping")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ProgressSync = {
    MIN_SYNC_INTERVAL = 25,
    DEFAULT_PAGE_THRESHOLD = 5,

    ui = nil,
    last_sync_time = 0,
    page_turn_count = 0,
    current_mapping = nil,
}

function ProgressSync:init(ui)
    self.ui = ui
    self.last_sync_time = 0
    self.page_turn_count = 0
    self.current_mapping = nil
end

function ProgressSync:loadMappingForDocument()
    if not self.ui or not self.ui.document then
        return nil
    end
    local filepath = self.ui.document.file
    self.current_mapping = BookMapping:getMapping(filepath)
    return self.current_mapping
end

function ProgressSync:calculateProgress()
    if not self.ui or not self.ui.document then
        return nil
    end

    local ok, current, total = pcall(function()
        return self.ui:getCurrentPage(), self.ui.document:getPageCount()
    end)

    if not ok or not current or not total or total == 0 then
        logger.warn("ProgressSync: failed to calculate progress")
        return nil
    end

    return {
        page = current,
        total_pages = total,
        percent = current / total,
        timestamp = os.time(),
    }
end

function ProgressSync:shouldSync()
    local now = os.time()
    if now - self.last_sync_time < self.MIN_SYNC_INTERVAL then
        return false
    end
    return true
end

function ProgressSync:pushProgress(blocking, callback)
    if not self.current_mapping then
        logger.dbg("ProgressSync: no mapping, skipping push")
        if callback then callback(false, "no_mapping") end
        return
    end

    if not self:shouldSync() and not blocking then
        logger.dbg("ProgressSync: debounced, skipping push")
        if callback then callback(false, "debounced") end
        return
    end

    local local_progress = self:calculateProgress()
    if not local_progress then
        if callback then callback(false, "no_progress") end
        return
    end

    local progress_data = {
        progress = local_progress.percent,
        currentTime = 0,
        isFinished = local_progress.percent >= 0.99,
        ebookProgress = local_progress.percent,
    }

    logger.dbg("ProgressSync: pushing progress", local_progress.percent, "to", self.current_mapping.library_item_id)

    local result, err = AudiobookshelfApi:updateProgress(
        self.current_mapping.library_item_id,
        progress_data
    )

    if result then
        self.last_sync_time = os.time()
        BookMapping:updateLastSync(self.ui.document.file)
        logger.dbg("ProgressSync: push successful")
        if callback then callback(true) end
    else
        logger.dbg("ProgressSync: push failed:", err)
        if callback then callback(false, err) end
    end
end

function ProgressSync:pullProgress(callback)
    if not self.current_mapping then
        logger.dbg("ProgressSync: no mapping, skipping pull")
        if callback then callback(false, "no_mapping") end
        return
    end

    logger.dbg("ProgressSync: pulling progress for", self.current_mapping.library_item_id)

    local server_progress, err = AudiobookshelfApi:getProgress(self.current_mapping.library_item_id)

    if err == "no_progress" then
        logger.dbg("ProgressSync: no server progress exists")
        if callback then callback(true, nil) end
        return
    end

    if not server_progress then
        logger.warn("ProgressSync: pull failed:", err)
        if callback then callback(false, err) end
        return
    end

    if callback then callback(true, server_progress) end
end

function ProgressSync:checkAndPromptServerProgress(show_no_diff_message)
    self:pullProgress(function(success, server_progress)
        if not success then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("Could not fetch progress from server."),
                    timeout = 3,
                })
            end
            return
        end

        if not server_progress then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("No progress on server yet."),
                    timeout = 2,
                })
            end
            return
        end

        local local_progress = self:calculateProgress()
        if not local_progress then
            return
        end

        local server_percent = server_progress.ebookProgress or server_progress.progress or 0
        local local_percent = local_progress.percent

        local diff = math.abs(server_percent - local_percent)
        if diff < 0.01 then
            if show_no_diff_message then
                UIManager:show(InfoMessage:new{
                    text = _("Progress is already in sync."),
                    timeout = 2,
                })
            end
            return
        end

        local server_page = math.floor(server_percent * local_progress.total_pages)
        local server_time_str = ""
        if server_progress.lastUpdate then
            server_time_str = os.date("%Y-%m-%d %H:%M", server_progress.lastUpdate / 1000)
        end

        local message
        if server_percent > local_percent then
            message = T(_("Server is ahead of local.\n\nLocal: Page %1 (%2%%)\nServer: Page %3 (%4%%)\nServer updated: %5\n\nJump to server position?"),
                local_progress.page,
                math.floor(local_percent * 100),
                server_page,
                math.floor(server_percent * 100),
                server_time_str
            )
        else
            message = T(_("Server is behind local.\n\nLocal: Page %1 (%2%%)\nServer: Page %3 (%4%%)\nServer updated: %5\n\nGo back to server position?"),
                local_progress.page,
                math.floor(local_percent * 100),
                server_page,
                math.floor(server_percent * 100),
                server_time_str
            )
        end

        UIManager:show(ConfirmBox:new{
            text = message,
            ok_text = _("Use server"),
            cancel_text = _("Keep local"),
            ok_callback = function()
                self:applyServerProgress(server_progress)
            end,
        })
    end)
end

function ProgressSync:applyServerProgress(server_progress)
    if not self.ui or not self.ui.document then
        return
    end

    local total_pages = self.ui.document:getPageCount()
    local server_percent = server_progress.ebookProgress or server_progress.progress or 0
    local target_page = math.floor(server_percent * total_pages)
    target_page = math.max(1, math.min(target_page, total_pages))

    logger.dbg("ProgressSync: applying server progress, going to page", target_page)

    local Event = require("ui/event")
    self.ui:handleEvent(Event:new("GotoPage", target_page))

    UIManager:show(InfoMessage:new{
        text = T(_("Moved to page %1."), target_page),
        timeout = 2,
    })
end

function ProgressSync:onPageTurn(settings)
    if not self.current_mapping then
        return
    end

    local auto_sync = settings and settings.auto_push_on_page_turn
    if auto_sync == false then
        return
    end

    self.page_turn_count = self.page_turn_count + 1

    local threshold = (settings and settings.page_threshold) or self.DEFAULT_PAGE_THRESHOLD
    if self.page_turn_count >= threshold then
        self.page_turn_count = 0
        if self:shouldSync() then
            self:pushProgress(false)
        end
    end
end

function ProgressSync:reset()
    self.ui = nil
    self.last_sync_time = 0
    self.page_turn_count = 0
    self.current_mapping = nil
end

return ProgressSync
