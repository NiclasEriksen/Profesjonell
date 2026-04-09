-- DebugLog.lua
-- Persistent debug log with scrollable viewer window
-- Captures all Debug() output into a circular buffer stored in SavedVariables
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("DebugLog.lua loading")
end

-- Configuration
local MAX_LOG_ENTRIES = 2000
local LOG_WINDOW_WIDTH = 700
local LOG_WINDOW_HEIGHT = 500
local LOG_ROW_HEIGHT = 14

-- State
local logFrame = nil
local logPaused = false
local logFilter = ""

-- Category colors for visual distinction in the log window
local CATEGORY_COLORS = {
    SEND = "|cff66bbff",   -- Blue: outgoing messages
    RECV = "|cffffcc66",   -- Gold: incoming messages
    SYNC = "|cff66ff66",   -- Green: sync state changes
    WARN = "|cffff6666",   -- Red: warnings/errors
    INFO = "|cffcccccc",   -- Gray: general info
}

----------------------------------------------------------------
-- Log Buffer Management
----------------------------------------------------------------

-- Initialize or retrieve the persistent log buffer
function Profesjonell.InitDebugLog()
    if not ProfesjonellDebugLog then
        ProfesjonellDebugLog = {}
    end
    -- Trim if over max (in case max was reduced)
    while table.getn(ProfesjonellDebugLog) > MAX_LOG_ENTRIES do
        table.remove(ProfesjonellDebugLog, 1)
    end
end

-- Add an entry to the persistent log
-- category: "SEND", "RECV", "SYNC", "WARN", "INFO" (optional, defaults to "INFO")
function Profesjonell.DebugLogAdd(message, category)
    if not ProfesjonellDebugLog then
        ProfesjonellDebugLog = {}
    end

    category = category or "INFO"

    -- Build timestamp from GetTime() (seconds since UI load)
    local timestamp = "?"
    if GetTime then
        local t = GetTime()
        local minutes = math.floor(t / 60)
        local seconds = t - (minutes * 60)
        local hours = math.floor(minutes / 60)
        minutes = minutes - (hours * 60)
        timestamp = string.format("%02d:%02d:%04.1f", hours, minutes, seconds)
    end

    local entry = {
        t = timestamp,
        cat = category,
        msg = message or "nil",
    }

    table.insert(ProfesjonellDebugLog, entry)

    -- Trim oldest entries if over limit
    while table.getn(ProfesjonellDebugLog) > MAX_LOG_ENTRIES do
        table.remove(ProfesjonellDebugLog, 1)
    end

    -- Update the window if it's open and not paused
    if logFrame and logFrame:IsVisible() and not logPaused then
        Profesjonell.RefreshDebugLogWindow()
    end
end

-- Clear the entire log
function Profesjonell.ClearDebugLog()
    ProfesjonellDebugLog = {}
    if logFrame and logFrame:IsVisible() then
        Profesjonell.RefreshDebugLogWindow()
    end
    Profesjonell.Print("Debug log cleared.")
end

-- Get filtered entries based on current filter text
local function GetFilteredEntries()
    if not ProfesjonellDebugLog then return {} end
    if logFilter == "" then return ProfesjonellDebugLog end

    local filtered = {}
    local lowerFilter = string.lower(logFilter)
    for _, entry in ipairs(ProfesjonellDebugLog) do
        if string.find(string.lower(entry.msg), lowerFilter, 1, true)
           or string.find(string.lower(entry.cat), lowerFilter, 1, true) then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

----------------------------------------------------------------
-- Hook into existing Debug() to capture messages
----------------------------------------------------------------

function Profesjonell.InstallDebugLogHook()
    -- Store original Debug function
    local originalDebug = Profesjonell.Debug

    Profesjonell.Debug = function(msg)
        -- Always log to persistent buffer (regardless of debug chat setting)
        if ProfesjonellConfig and ProfesjonellConfig.debugLog then
            -- Auto-categorize based on message content
            local category = "INFO"
            local lowerMsg = string.lower(msg or "")
            if string.find(lowerMsg, "^send") or string.find(lowerMsg, "broadcasting")
               or string.find(lowerMsg, "^sharing") or string.find(lowerMsg, "^queuing b:")
               or string.find(lowerMsg, "^queuing q") or string.find(lowerMsg, "^queuing c:") then
                category = "SEND"
            elseif string.find(lowerMsg, "^received") or string.find(lowerMsg, "^processing")
               or string.find(lowerMsg, "^incoming") or string.find(lowerMsg, "from ") then
                category = "RECV"
            elseif string.find(lowerMsg, "sync") or string.find(lowerMsg, "hash")
               or string.find(lowerMsg, "coordinator") or string.find(lowerMsg, "exhausted")
               or string.find(lowerMsg, "retry") or string.find(lowerMsg, "cooldown")
               or string.find(lowerMsg, "mismatch") or string.find(lowerMsg, "queued sync") then
                category = "SYNC"
            elseif string.find(lowerMsg, "error") or string.find(lowerMsg, "warn")
               or string.find(lowerMsg, "ignoring") or string.find(lowerMsg, "cancel")
               or string.find(lowerMsg, "yield") or string.find(lowerMsg, "suppress") then
                category = "WARN"
            end
            Profesjonell.DebugLogAdd(msg, category)
        end

        -- Call original Debug (handles chat output with burst collapsing)
        if originalDebug then
            originalDebug(msg)
        end
    end
end

----------------------------------------------------------------
-- Debug Log Window UI
----------------------------------------------------------------

function Profesjonell.CreateDebugLogWindow()
    if logFrame then return logFrame end

    logFrame = CreateFrame("Frame", "ProfesjonellDebugLogFrame", UIParent)
    logFrame:SetWidth(LOG_WINDOW_WIDTH)
    logFrame:SetHeight(LOG_WINDOW_HEIGHT)
    logFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    logFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    logFrame:SetBackdropColor(0, 0, 0, 0.9)
    logFrame:SetMovable(true)
    logFrame:EnableMouse(true)
    logFrame:RegisterForDrag("LeftButton")
    logFrame:SetScript("OnDragStart", function() logFrame:StartMoving() end)
    logFrame:SetScript("OnDragStop", function() logFrame:StopMovingOrSizing() end)
    logFrame:SetFrameStrata("HIGH")
    logFrame:Hide()

    -- Title
    local title = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", logFrame, "TOP", 0, -16)
    title:SetText("Profesjonell Debug Log")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, logFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -5, -5)

    -- Status bar at top (entry count, pause state)
    local statusText = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 20, -18)
    statusText:SetTextColor(0.7, 0.7, 0.7)
    logFrame.statusText = statusText

    -- Filter input
    local filterBox = CreateFrame("EditBox", "ProfesjonellDebugLogFilter", logFrame, "InputBoxTemplate")
    filterBox:SetWidth(200)
    filterBox:SetHeight(20)
    filterBox:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 20, -38)
    filterBox:SetAutoFocus(false)
    filterBox:SetScript("OnTextChanged", function()
        logFilter = filterBox:GetText() or ""
        Profesjonell.RefreshDebugLogWindow()
    end)
    filterBox:SetScript("OnEscapePressed", function() filterBox:ClearFocus() end)
    logFrame.filterBox = filterBox

    local filterLabel = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("RIGHT", filterBox, "LEFT", -4, 0)
    filterLabel:SetText("Filter:")

    -- Buttons row
    local btnY = -38
    local btnStartX = 240

    -- Pause/Resume button
    local pauseBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    pauseBtn:SetWidth(70)
    pauseBtn:SetHeight(22)
    pauseBtn:SetPoint("TOPLEFT", logFrame, "TOPLEFT", btnStartX, btnY)
    pauseBtn:SetText("Pause")
    pauseBtn:SetScript("OnClick", function()
        logPaused = not logPaused
        pauseBtn:SetText(logPaused and "Resume" or "Pause")
        Profesjonell.RefreshDebugLogWindow()
    end)
    logFrame.pauseBtn = pauseBtn

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    clearBtn:SetWidth(70)
    clearBtn:SetHeight(22)
    clearBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        Profesjonell.ClearDebugLog()
    end)

    -- Scroll to bottom button
    local bottomBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    bottomBtn:SetWidth(90)
    bottomBtn:SetHeight(22)
    bottomBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    bottomBtn:SetText("Scroll Down")
    bottomBtn:SetScript("OnClick", function()
        if logFrame.scrollFrame then
            local maxScroll = logFrame.scrollFrame:GetVerticalScrollRange()
            logFrame.scrollFrame:SetVerticalScroll(maxScroll)
        end
    end)

    -- Copy button
    local copyBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    copyBtn:SetWidth(60)
    copyBtn:SetHeight(22)
    copyBtn:SetPoint("LEFT", bottomBtn, "RIGHT", 4, 0)
    copyBtn:SetText("Copy")
    copyBtn:SetScript("OnClick", function()
        if Profesjonell.ExportDebugLog then
            Profesjonell.ExportDebugLog()
        end
    end)

    -- Bottom status bar (roster size, current hash)
    local bottomStatus = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bottomStatus:SetPoint("BOTTOMLEFT", logFrame, "BOTTOMLEFT", 16, 14)
    bottomStatus:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -16, 14)
    bottomStatus:SetJustifyH("LEFT")
    bottomStatus:SetTextColor(0.5, 0.8, 1.0)
    logFrame.bottomStatus = bottomStatus

    -- Scroll frame for log content
    local scrollFrame = CreateFrame("ScrollFrame", "ProfesjonellDebugLogScroll", logFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 16, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", -36, 30)
    logFrame.scrollFrame = scrollFrame

    -- Create row font strings
    local contentHeight = LOG_WINDOW_HEIGHT - 65 - 30
    local visibleRows = math.floor(contentHeight / LOG_ROW_HEIGHT)
    logFrame.rows = {}
    logFrame.visibleRows = visibleRows

    for i = 1, visibleRows do
        local row = logFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -((i - 1) * LOG_ROW_HEIGHT))
        row:SetPoint("RIGHT", scrollFrame, "RIGHT", -4, 0)
        row:SetJustifyH("LEFT")
        row:SetHeight(LOG_ROW_HEIGHT)
        logFrame.rows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(LOG_ROW_HEIGHT, function()
            Profesjonell.UpdateDebugLogRows()
        end)
    end)

    -- ESC to close
    table.insert(UISpecialFrames, "ProfesjonellDebugLogFrame")

    return logFrame
end

function Profesjonell.UpdateDebugLogRows()
    if not logFrame then return end

    local entries = GetFilteredEntries()
    local numEntries = table.getn(entries)
    local offset = FauxScrollFrame_GetOffset(logFrame.scrollFrame)

    for i = 1, logFrame.visibleRows do
        local row = logFrame.rows[i]
        local idx = offset + i
        if idx <= numEntries then
            local entry = entries[idx]
            local color = CATEGORY_COLORS[entry.cat] or CATEGORY_COLORS.INFO
            local catTag = "[" .. entry.cat .. "]"
            row:SetText("|cff999999" .. entry.t .. "|r " .. color .. catTag .. "|r " .. entry.msg)
            row:Show()
        else
            row:SetText("")
            row:Hide()
        end
    end
end

function Profesjonell.RefreshDebugLogWindow()
    if not logFrame or not logFrame:IsVisible() then return end

    local entries = GetFilteredEntries()
    local numEntries = table.getn(entries)
    local totalEntries = ProfesjonellDebugLog and table.getn(ProfesjonellDebugLog) or 0

    -- Update status
    local statusParts = {}
    table.insert(statusParts, numEntries .. "/" .. totalEntries .. " entries")
    if logPaused then
        table.insert(statusParts, "|cffff6666PAUSED|r")
    end
    if logFilter ~= "" then
        table.insert(statusParts, "filter: '" .. logFilter .. "'")
    end
    logFrame.statusText:SetText(table.concat(statusParts, "  |  "))

    -- Update bottom status bar with roster size and hash
    if logFrame.bottomStatus then
        local rosterSize = 0
        if Profesjonell.GuildRosterCache then
            for _ in pairs(Profesjonell.GuildRosterCache) do
                rosterSize = rosterSize + 1
            end
        end
        local dbHash = Profesjonell.GenerateDatabaseHash and Profesjonell.GenerateDatabaseHash() or "n/a"
        logFrame.bottomStatus:SetText("Roster: " .. rosterSize .. "  |  Hash: " .. (dbHash or "n/a"))
    end

    -- Update scroll range
    FauxScrollFrame_Update(logFrame.scrollFrame, numEntries, logFrame.visibleRows, LOG_ROW_HEIGHT)

    Profesjonell.UpdateDebugLogRows()
end

function Profesjonell.ToggleDebugLogWindow()
    if not logFrame then
        Profesjonell.CreateDebugLogWindow()
    end
    if logFrame:IsVisible() then
        logFrame:Hide()
    else
        logFrame:Show()
        logPaused = false
        if logFrame.pauseBtn then
            logFrame.pauseBtn:SetText("Pause")
        end
        Profesjonell.RefreshDebugLogWindow()
        -- Scroll to bottom
        if logFrame.scrollFrame then
            local maxScroll = logFrame.scrollFrame:GetVerticalScrollRange()
            logFrame.scrollFrame:SetVerticalScroll(maxScroll)
        end
    end
end

-- Export log as a single string (for copy/paste from SavedVariables or chat)
function Profesjonell.ExportDebugLog()
    if not ProfesjonellDebugLog or table.getn(ProfesjonellDebugLog) == 0 then
        Profesjonell.Print("Debug log is empty.")
        return
    end

    -- Build export into a temporary editbox for copy/paste
    local exportFrame = CreateFrame("Frame", "ProfesjonellDebugLogExport", UIParent)
    exportFrame:SetWidth(600)
    exportFrame:SetHeight(400)
    exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    exportFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    exportFrame:SetBackdropColor(0, 0, 0, 0.95)
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:EnableMouse(true)

    local exportTitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    exportTitle:SetPoint("TOP", exportFrame, "TOP", 0, -16)
    exportTitle:SetText("Debug Log Export (Ctrl+A, Ctrl+C to copy)")

    local closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -5, -5)

    local scrollFrame = CreateFrame("ScrollFrame", "ProfesjonellDebugLogExportScroll", exportFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -36, 16)

    local editBox = CreateFrame("EditBox", "ProfesjonellDebugLogExportEdit", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(540)
    editBox:SetAutoFocus(true)
    scrollFrame:SetScrollChild(editBox)

    -- Build text
    local lines = {}
    local entries = GetFilteredEntries()
    for _, entry in ipairs(entries) do
        table.insert(lines, entry.t .. " [" .. entry.cat .. "] " .. entry.msg)
    end
    local text = table.concat(lines, "\n")
    editBox:SetText(text)
    editBox:HighlightText()

    editBox:SetScript("OnEscapePressed", function()
        exportFrame:Hide()
    end)

    table.insert(UISpecialFrames, "ProfesjonellDebugLogExport")
    exportFrame:Show()
end

----------------------------------------------------------------
-- Initialization
----------------------------------------------------------------

Profesjonell.InitDebugLog()
Profesjonell.InstallDebugLogHook()
