--[[
    The Quartermaster - German Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

-- General
L["ADDON_NAME"] = "The Quartermaster"
L["ADDON_LOADED"] = "The Quartermaster geladen. Tippe /tq oder /quartermaster für Optionen."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Allgemeine Einstellungen"
L["ENABLE_ADDON"] = "Addon aktivieren"
L["MINIMAP_ICON"] = "Minimap-Symbol anzeigen"
L["DEBUG_MODE"] = "Debug-Modus"

-- Scanner Module
L["SCAN_STARTED"] = "Scanne Kriegsmeute-Bank..."
L["SCAN_COMPLETE"] = "Scan abgeschlossen. %d Gegenstände in %d Plätzen gefunden."
L["SCAN_FAILED"] = "Scan fehlgeschlagen: Kriegsmeute-Bank ist nicht geöffnet."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "The Quartermaster"
L["SEARCH_PLACEHOLDER"] = "Gegenstände suchen..."
L["BTN_SCAN"] = "Bank scannen"
L["BTN_DEPOSIT"] = "Einzahlungswarteschlange"
L["BTN_SORT"] = "Bank sortieren"
L["BTN_CLOSE"] = "Schließen"
L["BTN_SETTINGS"] = "Einstellungen"

