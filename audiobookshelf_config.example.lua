-- plugins/audiobookshelf.koplugin/audiobookshelf_config.lua
return {
    ["token"] = 'your api key here',
    ["server"] = 'your audiobookshelf instance url here',

    -- Sync settings (optional - these are the defaults)
    ["sync"] = {
        ["auto_push_on_close"] = true,      -- Push progress when closing a book
        ["auto_push_on_page_turn"] = true,  -- Push progress after N page turns
        ["page_threshold"] = 5,             -- Number of page turns before syncing (1-50)
        ["auto_pull_on_open"] = true,       -- Check server progress when opening a book
    },
}
