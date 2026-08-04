--[[--
Lightweight per-plugin translations.

KOReader's central gettext catalog does not know this plugin's own strings, so
they fall back to English. This module provides a drop-in replacement for the
gettext `_` function: when the KOReader UI language matches one of our tables
below, it returns our translation; otherwise it defers to KOReader's gettext
(so strings KOReader already knows, and other languages, keep working).

Usage in a module (replace `local _ = require("gettext")`):
    local _ = require("audiobookshelf/absi18n")

Language-flexible: follows GetText.current_lang, and is not wiped on language
change (unlike injecting into GetText.translation). No .mo compilation needed.

@module absi18n
--]]

local GetText = require("gettext")

-- Translations keyed by language code, then by the English source string.
-- Only strings that need translating must be listed; anything missing falls
-- back to KOReader gettext / English.
local STRINGS = {
    nl = {
        -- Browser / library
        ["Audiobookshelf Browser"] = "Audiobookshelf-bibliotheek",
        ["Could not reach Audiobookshelf server. Check network and settings."] =
            "Kan de Audiobookshelf-server niet bereiken. Controleer netwerk en instellingen.",
        ["Could not load library. Check network and settings."] =
            "Kan de bibliotheek niet laden. Controleer netwerk en instellingen.",
        ["Search failed. Check network and settings."] =
            "Zoeken mislukt. Controleer netwerk en instellingen.",
        -- Age (tag) filter
        ["⚑ Age: %1 (tap to change)"] = "⚑ Leeftijd: %1 (tik om te wijzigen)",
        ["⚑ Age: all (tap to filter)"] = "⚑ Leeftijd: alle (tik om te filteren)",
        ["Could not load tags. Check network and settings."] =
            "Kan tags niet laden. Controleer netwerk en instellingen.",
        ["No tags in this library."] = "Geen tags in deze bibliotheek.",
        ["All books (no filter)"] = "Alle boeken (geen filter)",
        ["Filter by age"] = "Filter op leeftijd",
        -- Genre filter
        ["♦ Genre: %1 (tap to change)"] = "♦ Genre: %1 (tik om te wijzigen)",
        ["♦ Genre: all (tap to filter)"] = "♦ Genre: alle (tik om te filteren)",
        ["Could not load genres. Check network and settings."] =
            "Kan genres niet laden. Controleer netwerk en instellingen.",
        ["No genres in this library."] = "Geen genres in deze bibliotheek.",
        ["All genres (no filter)"] = "Alle genres (geen filter)",
        ["Filter by genre"] = "Filter op genre",
        -- View toggle
        ["▦ View: text list (tap for covers)"] = "▦ Weergave: tekstlijst (tik voor omslagen)",
        ["▦ View: cover mosaic (tap for list)"] = "▦ Weergave: omslagraster (tik voor lijst)",
        -- Mosaic
        ["Untitled"] = "Zonder titel",
        ["Library"] = "Bibliotheek",
        ["%1 / %2"] = "%1 / %2",
        -- Dialog buttons
        ["Cancel"] = "Annuleren",
        ["Save"] = "Opslaan",
        ["Search"] = "Zoeken",
        ["Settings saved"] = "Instellingen opgeslagen",
        ["Audiobookshelf Settings"] = "Audiobookshelf-instellingen",
        ["Audiobookshelf Server Url"] = "Audiobookshelf-server-URL",
        ["Audiobookshelf API Token"] = "Audiobookshelf-API-token",
    },
}

-- The replacement translator. Returns our string when available for the current
-- UI language, else defers to KOReader's gettext.
return function(msgid)
    local lang = GetText.current_lang
    local tbl = lang and STRINGS[lang]
    if tbl and tbl[msgid] then
        return tbl[msgid]
    end
    -- Some codes look like "nl_NL"; try the base language too.
    if lang then
        local base = lang:match("^([a-z][a-z])")
        if base and STRINGS[base] and STRINGS[base][msgid] then
            return STRINGS[base][msgid]
        end
    end
    return GetText(msgid)
end
