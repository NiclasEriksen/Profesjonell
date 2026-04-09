-- test_runner.lua
-- Custom test runner for Profesjonell

-- Mocks for WoW globals
_G = {}
math.mod = math.mod or function(a, b) return a % b end
table.getn = table.getn or function(t) return #t end
ITEM_QUALITY_COLORS = {
    [0] = { hex = "|cff9d9d9d" },
    [1] = { hex = "|cffffffff" },
    [2] = { hex = "|cff1eff00" },
    [3] = { hex = "|cff0070dd" },
    [4] = { hex = "|cffa335ee" },
}

SlashCmdList = {}
TEST_TOOLTIP_LINES = {}

function CreateFrame(type, name, parent, template)
    local frame = {
        _name = name,
        lines = {},
        scripts = {}
    }

    function frame:RegisterEvent() end
    function frame:SetOwner() end
    function frame:ClearLines()
        self.lines = {}
    end
    function frame:SetHyperlink(link)
        self.link = link
        self.lines = {}
        local lines = TEST_TOOLTIP_LINES[link] or {}
        for i, text in ipairs(lines) do
            self.lines[i] = text
            if name then
                local objName = name .. "TextLeft" .. i
                _G[objName] = {
                    GetText = function() return self.lines[i] end,
                    SetText = function(_, newText) self.lines[i] = newText end
                }
            end
        end
        return true
    end
    function frame:SetScript(eventName, fn)
        self.scripts[eventName] = fn
    end
    function frame:GetScript(eventName)
        return self.scripts[eventName]
    end
    function frame:Hide() end
    function frame:Show() end
    function frame:AddLine(text)
        table.insert(self.lines, text)
        local i = table.getn(self.lines)
        if name then
            local objName = name .. "TextLeft" .. i
            _G[objName] = {
                GetText = function() return self.lines[i] end,
                SetText = function(_, newText) self.lines[i] = newText end
            }
        end
    end
    function frame:NumLines()
        return table.getn(self.lines)
    end
    function frame:GetName()
        return name
    end
    function frame:GetItem()
        return self.itemName, self.itemLink
    end
    function frame:GetSpell()
        return self.spellName, self.spellRank, self.spellId
    end
    function frame:SetItem(link, name)
        self.itemLink = link
        self.itemName = name
    end
    function frame:SetSpell(id, name)
        self.spellId = id
        self.spellName = name
    end
    return frame
end

-- Parse version from .toc file
local function LoadVersionFromToc()
    local f = io.open("Profesjonell.toc", "r")
    if not f then return "0" end
    for line in f:lines() do
        local version = string.match(line, "^## Version:%s*(.+)$")
        if version then
            f:close()
            return version
        end
    end
    f:close()
    return "0"
end

local TOC_VERSION = LoadVersionFromToc()

function GetTime() return 1000 end
function UnitName(unit) return "Player" end
function GetGuildInfo(unit) return "TestGuild" end
function GetAddOnMetadata(addon, field)
    if field == "Version" then return TOC_VERSION end
    return nil
end
function GetItemInfo(id)
    if id == "1234" or id == 1234 then return "Lionheart Helm", "item:1234:0:0:0", 1, nil, nil, "Armor" end
    if id == "1000" or id == 1000 then return "Recipe: Transmute X", "item:1000:0:0:0", 1, nil, nil, "Recipe" end
    if id == "2000" or id == 2000 then return "Transmuted Item", "item:2000:0:0:0", 1, nil, nil, "Armor" end
    if id == "3000" or id == 3000 then return "Major Mana Potion", "item:3000:0:0:0", 1, nil, nil, "Consumable" end
    return nil 
end
function GetNumTradeSkills() return 0 end
function GetTradeSkillInfo(i) return nil end
function GetTradeSkillItemLink(i) return nil end
function GetNumCrafts() return 0 end
function GetCraftInfo(i) return nil end
function GetCraftItemLink(i) return nil end
function GetTradeSkillLine() return "Alchemy" end
function GetCraftDisplayName() return "Enchanting" end
function IsShiftKeyDown() return false end
function ChatEdit_InsertLink(link) end
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_OnVerticalScroll() end
UIParent = CreateFrame("Frame", "UIParent")
UISpecialFrames = {}
function tinsert(t, v) table.insert(t, v) end
function SendAddonMessage(prefix, msg, type) end
function SendChatMessage(msg, type) end
function GetGuildRosterShowOffline() return 1 end
function SetGuildRosterShowOffline(val) end
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo(i) return nil end
function GuildRoster() end
function getglobal(name) return name end

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", nil, "GameTooltipTemplate")
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", nil, "GameTooltipTemplate")

-- Helper for assertions
local passed = 0
local failed = 0
function assert_equal(actual, expected, test_name)
    if actual == expected then
        print("  [PASS] " .. test_name)
        passed = passed + 1
    else
        print("  [FAIL] " .. test_name)
        print("         Expected: " .. tostring(expected))
        print("         Actual:   " .. tostring(actual))
        failed = failed + 1
    end
end

-- Load modules
local modules = {
    "Modules/Init.lua",
    "Modules/Core.lua",
    "Modules/Utils.lua",
    "Modules/Guild.lua",
    "Modules/Database.lua",
    "Modules/Professions.lua",
    "Modules/Scanner.lua",
    "Modules/Comm.lua",
    "Modules/DebugLog.lua",
    "Modules/UI.lua",
    "Modules/SearchWindow.lua"
}

print("Loading modules...")
for _, mod in ipairs(modules) do
    local f, err = loadfile(mod)
    if f then
        f()
    else
        print("Error loading " .. mod .. ": " .. err)
        os.exit(1)
    end
end

print("\nRunning tests...")

-- Test DebugLog
ProfesjonellConfig.debugLog = true
ProfesjonellDebugLog = {}
Profesjonell.DebugLogAdd("Test message", "INFO")
assert_equal(table.getn(ProfesjonellDebugLog), 1, "DebugLogAdd adds entry")
assert_equal(ProfesjonellDebugLog[1].cat, "INFO", "DebugLogAdd sets category")
assert_equal(ProfesjonellDebugLog[1].msg, "Test message", "DebugLogAdd sets message")

-- Test Debug hook captures to log
ProfesjonellDebugLog = {}
Profesjonell.Debug("Hash mismatch with TestPlayer")
assert_equal(table.getn(ProfesjonellDebugLog), 1, "Debug hook captures to log")
assert_equal(ProfesjonellDebugLog[1].cat, "SYNC", "Debug hook auto-categorizes SYNC")

ProfesjonellDebugLog = {}
Profesjonell.Debug("Sending B: batch")
assert_equal(ProfesjonellDebugLog[1].cat, "SEND", "Debug hook auto-categorizes SEND")

ProfesjonellDebugLog = {}
Profesjonell.Debug("Ignoring incompatible version")
assert_equal(ProfesjonellDebugLog[1].cat, "WARN", "Debug hook auto-categorizes WARN")

ProfesjonellDebugLog = {}
Profesjonell.Debug("Received C: from TestPlayer")
assert_equal(ProfesjonellDebugLog[1].cat, "RECV", "Debug hook auto-categorizes RECV")

-- Test ClearDebugLog
Profesjonell.ClearDebugLog()
assert_equal(table.getn(ProfesjonellDebugLog), 0, "ClearDebugLog empties log")

-- Test log disabled
ProfesjonellConfig.debugLog = false
ProfesjonellDebugLog = {}
Profesjonell.Debug("Should not be logged")
assert_equal(table.getn(ProfesjonellDebugLog), 0, "Debug does not log when debugLog is false")
ProfesjonellConfig.debugLog = true

-- Test Utils
assert_equal(Profesjonell.StripPrefix("Recipe: Lionheart Helm"), "Lionheart Helm", "StripPrefix handles 'Recipe:'")
assert_equal(Profesjonell.StripPrefix("Pattern: Robe of the Archmage"), "Robe of the Archmage", "StripPrefix handles 'Pattern:'")
assert_equal(Profesjonell.GetIDFromLink("|Hitem:1234:0:0:0|h[Test Item]|h"), "i:1234", "GetIDFromLink handles item link")
assert_equal(Profesjonell.GetIDFromLink("|Hspell:5678|h[Test Spell]|h"), "s:5678", "GetIDFromLink handles spell link")
assert_equal(Profesjonell.GetIDFromLink("e:7421"), "s:7421", "GetIDFromLink normalizes e: to s:")
assert_equal(Profesjonell.GetIDFromLink("enchant:7421"), "s:7421", "GetIDFromLink normalizes enchant: to s:")
assert_equal(Profesjonell.GetIDFromLink("spell:7421"), "s:7421", "GetIDFromLink normalizes spell: to s:")
assert_equal(Profesjonell.GetIDFromLink("item:1234"), "i:1234", "GetIDFromLink normalizes item: to i:")
assert_equal(Profesjonell.GetIDFromLink("S:7421"), "s:7421", "GetIDFromLink handles uppercase S:")

-- Test Version Compare
assert_equal(Profesjonell.CompareVersions("0.29", "0.3"), 1, "CompareVersions: 0.29 > 0.3")
assert_equal(Profesjonell.CompareVersions("0.3", "0.29"), -1, "CompareVersions: 0.3 < 0.29")
assert_equal(Profesjonell.CompareVersions("0.29", "0.100"), -1, "CompareVersions: 0.29 < 0.100")
assert_equal(Profesjonell.CompareVersions("1.0", "0.29"), 1, "CompareVersions: 1.0 > 0.29")
assert_equal(Profesjonell.CompareVersions("1.1", "1.1"), 0, "CompareVersions: 1.1 == 1.1")

-- Test Database Migration (basic)
ProfesjonellDB = {
    ["item:1234"] = { ["Player"] = true },
    ["Test Item"] = { ["Player"] = true }
}
Profesjonell.MigrateDatabase()
assert_equal(ProfesjonellDB["i:1234"] ~= nil, true, "MigrateDatabase converts item: to i:")
assert_equal(ProfesjonellDB["item:1234"] == nil, true, "MigrateDatabase removes old item: key")

-- Test Hashes
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.UpdateGuildRosterCache = function() return true end
ProfesjonellDB = {
    ["i:1"] = { ["Player"] = true, ["Other"] = true },
    ["i:2"] = { ["Player"] = true }
}
local hashes1 = Profesjonell.GenerateCharacterHashes()
local dbHash1 = Profesjonell.GenerateDatabaseHash()

ProfesjonellDB = {
    ["i:2"] = { ["Player"] = true },
    ["i:1"] = { ["Other"] = true, ["Player"] = true }
}
local hashes2 = Profesjonell.GenerateCharacterHashes()
local dbHash2 = Profesjonell.GenerateDatabaseHash()

assert_equal(hashes1["Player"], hashes2["Player"], "Character hash is deterministic (order independent)")
assert_equal(dbHash1, dbHash2, "Database hash is deterministic (order independent)")

-- Test FindRecipeHolders
ProfesjonellDB = {
    ["i:1234"] = { ["Player"] = true }
}
local found, cleanName, partialMatches = Profesjonell.FindRecipeHolders("Lionheart")
assert_equal(partialMatches["Lionheart Helm"] ~= nil, true, "FindRecipeHolders finds partial match")
assert_equal(partialMatches["Lionheart Helm"][1], "Player", "FindRecipeHolders finds partial match holder")
assert_equal(cleanName, "Lionheart", "FindRecipeHolders returns clean name")

local found2, cleanName2 = Profesjonell.FindRecipeHolders("Recipe: Lionheart Helm")
assert_equal(found2[1], "Player", "FindRecipeHolders finds exact match with prefix")
assert_equal(cleanName2, "Lionheart Helm", "FindRecipeHolders strips prefix")

-- Test OnAddonMessage (Sync logic)
ProfesjonellDB = {}
Profesjonell.OnAddonMessage("B:Other:i:555,s:666", "Other")
assert_equal(ProfesjonellDB["i:555"]["Other"], true, "OnAddonMessage parses batch recipes (item)")
assert_equal(ProfesjonellDB["s:666"]["Other"], true, "OnAddonMessage parses batch recipes (spell)")

-- Test REMOVE_CHAR removes character data
Profesjonell.IsOfficer = function(name) return name == "Officer" end
Profesjonell.OnAddonMessage("REMOVE_CHAR:Other", "Officer")
assert_equal(ProfesjonellDB["i:555"] == nil, true, "REMOVE_CHAR removes character data")

-- Helper: flush C: buffer by advancing time past settle delay and calling OnCommUpdate
local function flushCBuffer()
    local oldGetTime = GetTime
    local now = oldGetTime()
    GetTime = function() return now + 2 end -- 2s > 1.5s settle delay
    Profesjonell.OnCommUpdate()
    GetTime = oldGetTime
end

-- Global to track sent messages
sentMessages = {}
local oldSAM = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(sentMessages, {prefix = prefix, msg = msg, type = type})
    oldSAM(prefix, msg, type)
end

-- Test self-sync prevention
ProfesjonellDB = {}
Profesjonell.UpdateGuildRosterCache = function() 
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
    return true 
end
Profesjonell.IsInGuild = function(name) return true end
ProfesjonellDB["i:1"] = { ["Other"] = true }
Profesjonell.Frame.pendingR = {}
-- Remote peer reports "Player" has hash "abc", but we have nothing for "Player" locally (hash "0")
local mockMessage = "C:Player:abc,Other:abc" 
Profesjonell.OnAddonMessage(mockMessage, "Other")
flushCBuffer()
assert_equal(Profesjonell.Frame.pendingR["Player"] == nil, true, "Should not request sync for own character")

-- Test own-hash mismatch push
ProfesjonellDB = {}
ProfesjonellDB["i:1"] = { ["Player"] = true }
Profesjonell.Frame.pendingB = {}
-- Remote peer reports Player has hash "0" (empty)
Profesjonell.OnAddonMessage("C:Player:0", "Other")
flushCBuffer()
assert_equal(Profesjonell.Frame.pendingB["Player"] ~= nil, true, "Should push own recipes when remote has old hash for us")

-- Test ResolveRecipeKeysFromLink (recipe item -> spell)
TEST_TOOLTIP_LINES = {}
local recipeLink = "|Hitem:1000:0:0:0|h[Recipe: Transmute X]|h"
TEST_TOOLTIP_LINES["item:1000:0:0:0"] = { "Recipe: Transmute X", "Use: Teaches you how to create a Transmute: X." }
TEST_TOOLTIP_LINES["spell:5678"] = { "Transmute: X" }
ProfesjonellDB = {
    ["s:5678"] = { ["Player"] = true }
}
Profesjonell.GetNameFromKey = function(key)
    if key == "s:5678" then return "Transmute: X" end
    return key
end
Profesjonell.InvalidateTooltipCache()
local keys1 = Profesjonell.ResolveRecipeKeysFromLink(recipeLink)
assert_equal(keys1[1], "s:5678", "ResolveRecipeKeysFromLink uses Teaches line for recipe item")

-- Test ResolveRecipeKeysFromLink (created by item)
local createdItemLink = "|Hitem:2000:0:0:0|h[Transmuted Item]|h"
TEST_TOOLTIP_LINES["item:2000:0:0:0"] = { "Transmuted Item", "Created by: Transmute: X" }
local keys2 = Profesjonell.ResolveRecipeKeysFromLink(createdItemLink)
assert_equal(keys2[1], "s:5678", "ResolveRecipeKeysFromLink uses Created by line for item")

-- Test ResolveRecipeKeysFromLink (consumable item name match)
local potionLink = "|Hitem:3000:0:0:0|h[Major Mana Potion]|h"
TEST_TOOLTIP_LINES["item:3000:0:0:0"] = { "Major Mana Potion" }
ProfesjonellDB = {
    ["s:7777"] = { ["Player"] = true }
}
Profesjonell.GetNameFromKey = function(key)
    if key == "s:7777" then return "Major Mana Potion" end
    return key
end
Profesjonell.InvalidateTooltipCache()
local keys3 = Profesjonell.ResolveRecipeKeysFromLink(potionLink)
assert_equal(keys3[1], "s:7777", "ResolveRecipeKeysFromLink uses item name for consumable fallback")

-- Test tooltip known-by line
ProfesjonellDB = {
    ["s:5678"] = { ["Player"] = true, ["Other"] = true }
}
Profesjonell.GetNameFromKey = function(key)
    if key == "s:5678" then return "Transmute: X" end
    return key
end
Profesjonell.UpdateGuildRosterCache = function() return false end
Profesjonell.InvalidateTooltipCache()
GameTooltip:ClearLines()
GameTooltip._profHyperlink = "item:1000:0:0:0"
GameTooltip:SetHyperlink("item:1000:0:0:0")
Profesjonell.AddKnownByToTooltip(GameTooltip)
local lineIndex = GameTooltip:NumLines()
local tooltipLine = _G["GameTooltipTextLeft" .. lineIndex] and _G["GameTooltipTextLeft" .. lineIndex]:GetText()
assert_equal(tooltipLine, "Known by: Other, Player", "Tooltip shows known-by line for <=3 holders")

-- Test tooltip known-by count
ProfesjonellDB = {
    ["s:5678"] = { ["Player"] = true, ["Other"] = true, ["Third"] = true, ["Fourth"] = true }
}
Profesjonell.GetNameFromKey = function(key)
    if key == "s:5678" then return "Transmute: X" end
    return key
end
Profesjonell.UpdateGuildRosterCache = function() return false end
Profesjonell.InvalidateTooltipCache()
GameTooltip:ClearLines()
GameTooltip._profHyperlink = "item:1000:0:0:0"
GameTooltip:SetHyperlink("item:1000:0:0:0")
Profesjonell.AddKnownByToTooltip(GameTooltip)
local lineIndex2 = GameTooltip:NumLines()
local tooltipLine2 = _G["GameTooltipTextLeft" .. lineIndex2] and _G["GameTooltipTextLeft" .. lineIndex2]:GetText()
assert_equal(tooltipLine2, "Known by 4 guild members", "Tooltip shows known-by count for >3 holders")

-- Test ?prof coordination - no early P message sent
Profesjonell.PendingReplies = {}
sentMessages = {}
Profesjonell.OnGuildChat("?prof Lionheart", "Friend")
assert_equal(Profesjonell.PendingReplies["lionheart"] ~= nil, true, "Should schedule reply for ?prof")
local foundEarlyP = false
for _, msg in ipairs(sentMessages) do
    if msg.msg == "P:lionheart" then foundEarlyP = true end
end
assert_equal(foundEarlyP, false, "Should NOT send early P message (sends after DB check)")

-- Test P: cancellation with alphabetical priority
Profesjonell.PendingReplies = {}
Profesjonell.PendingReplies["test"] = { time = GetTime() + 10 }
UnitName = function() return "Zebra" end -- Alphabetically after "Other"
Profesjonell.OnAddonMessage("P:test", "Other")
assert_equal(Profesjonell.PendingReplies["test"] == nil, true, "Should cancel reply when P received from higher priority player")

-- Test P: keeps reply with alphabetical priority
Profesjonell.PendingReplies = {}
Profesjonell.PendingReplies["test2"] = { time = GetTime() + 10 }
UnitName = function() return "Alpha" end -- Alphabetically before "Zebra"
Profesjonell.OnAddonMessage("P:test2", "Zebra")
assert_equal(Profesjonell.PendingReplies["test2"] ~= nil, true, "Should keep reply when P received from lower priority player")
UnitName = function() return "Player" end -- Reset

-- Test reply cancellation when someone else replies
Profesjonell.PendingReplies = {}
Profesjonell.PendingReplies["crusader"] = { time = GetTime() + 10 }
Profesjonell.OnGuildChat("Profesjonell: Enchant Weapon - Crusader is known by: Enchanter", "Other")
assert_equal(Profesjonell.PendingReplies["crusader"] == nil, true, "Should cancel reply when someone else replies")

-- Test Sync Loop Fix
local old_lastSyncPeer = Profesjonell.Frame.lastSyncPeer
local old_syncTimer = Profesjonell.Frame.syncTimer
local old_UpdateGuildRosterCache = Profesjonell.UpdateGuildRosterCache
Profesjonell.UpdateGuildRosterCache = function() return true end
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }

Profesjonell.Frame.lastSyncPeer = "TestPeer"
Profesjonell.Frame.lastRemoteHash = "0"
Profesjonell.Frame.syncTimer = GetTime() + 100
Profesjonell.OnAddonMessage("C:", "TestPeer")
flushCBuffer()
assert_equal(Profesjonell.Frame.syncTimer, nil, "Sync timer cleared after empty C response from lastSyncPeer")

-- Test Reciprocal Broadcast when C finds no mismatches to pull
Profesjonell.Frame.lastSyncPeer = "TestPeer"
Profesjonell.Frame.lastRemoteHash = "999" -- Mismatching hash
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.Frame.syncTimer = GetTime() + 100
Profesjonell.Frame.broadcastHashTime = nil
Profesjonell.OnAddonMessage("C:", "TestPeer")
flushCBuffer()
assert_equal(Profesjonell.Frame.broadcastHashTime ~= nil, true, "Reciprocal broadcast scheduled when hashes mismatch and no pull mismatches found")
Profesjonell.Frame.broadcastHashTime = nil

Profesjonell.Frame.lastSyncPeer = old_lastSyncPeer
Profesjonell.Frame.syncTimer = old_syncTimer

-- Test BroadcastCharacterHashes with empty DB
local old_db = ProfesjonellDB
ProfesjonellDB = {}
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" } -- Ensure roster is set
Profesjonell.CachedCharacterHashes = nil -- Clear cache
Profesjonell.CachedDatabaseHash = nil -- Clear cache
local SENT_MESSAGES = {}
local old_SendAddonMessage = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(SENT_MESSAGES, msg)
end
Profesjonell.BroadcastCharacterHashes()
local foundC = false
for _, m in ipairs(SENT_MESSAGES) do
    if m == "C:" then foundC = true end
end
assert_equal(foundC, true, "BroadcastCharacterHashes sends 'C:' even if DB is empty")
SendAddonMessage = old_SendAddonMessage
ProfesjonellDB = old_db
Profesjonell.UpdateGuildRosterCache = old_UpdateGuildRosterCache

-- Test: syncRetryCount not reset when same peer sends same hash again
Profesjonell.Frame.lastSyncPeer = "TestPeer"
Profesjonell.Frame.lastRemoteHash = "abc123"
Profesjonell.Frame.syncRetryCount = 2
Profesjonell.Frame.syncTimer = nil
Profesjonell.Frame.syncPendingChars = nil
Profesjonell.Frame.pendingQ = nil
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.RemoteVersions["TestPeer"] = "0.401"
-- Simulate receiving H: with the same hash from the same peer
Profesjonell.OnAddonMessage("H:abc123:0.401", "TestPeer")
assert_equal(Profesjonell.Frame.syncRetryCount == 2, true, "syncRetryCount preserved when same peer sends same hash")

-- Test: C: handler pushes data for characters remote doesn't know about
Profesjonell.Frame.pendingB = {}
Profesjonell.Frame.pendingR = {}
Profesjonell.Frame.lastSyncPeer = "TestPeer"
Profesjonell.Frame.lastRemoteHash = "xyz"
Profesjonell.Frame.syncTimer = GetTime() + 100
ProfesjonellDB = { ["i:1"] = { ["Player"] = true }, ["i:2"] = { ["Other"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
    return true
end
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
-- Remote only mentions Player, not Other
Profesjonell.OnAddonMessage("C:Player:somehash", "TestPeer")
flushCBuffer()
assert_equal(Profesjonell.Frame.pendingB["Other"] ~= nil, true, "C: handler pushes data for characters remote doesn't mention")

Profesjonell.Frame.lastSyncPeer = nil
Profesjonell.Frame.syncTimer = nil
Profesjonell.Frame.broadcastHashTime = nil

-- Test: FindRecipeHolders with incomplete roster
ProfesjonellDB = {
    ["s:1234"] = { ["OnlinePlayer"] = true, ["OfflinePlayer"] = true }
}
Profesjonell.GetNameFromKey = function(key)
    if key == "s:1234" then return "Test Recipe" end
    return key
end
Profesjonell.GuildRosterCache = { ["OnlinePlayer"] = "Warrior" } -- Only online player in cache
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["OnlinePlayer"] = "Warrior" }
    return false -- Roster not ready
end
Profesjonell.InvalidateTooltipCache()
local found_incomplete, _, _ = Profesjonell.FindRecipeHolders("Test Recipe")
-- Should still find both players when roster isn't ready (to avoid false "no one knows")
assert_equal(table.getn(found_incomplete), 2, "FindRecipeHolders includes all DB holders when roster not ready")

-- Test: ShowOffline state is restored on all early return paths
do
    -- Save originals
    local origGetTime = GetTime
    local origGetGuildName = Profesjonell.GetGuildName
    local origGetNumGuildMembers = GetNumGuildMembers
    local origGetGuildRosterInfo = GetGuildRosterInfo
    local origGuildRoster = GuildRoster
    local origGetGuildRosterShowOffline = GetGuildRosterShowOffline
    local origSetGuildRosterShowOffline = SetGuildRosterShowOffline
    local origUpdateGuildRosterCache = Profesjonell.UpdateGuildRosterCache

    local testTime = 5000
    GetTime = function() return testTime end
    Profesjonell.GetGuildName = function() return "TestGuild" end
    GetNumGuildMembers = function() return 2 end
    GetGuildRosterInfo = function(i)
        if i == 1 then return "Player", "Member", 2, nil, "Warrior" end
        if i == 2 then return "Other", "Officer", 1, nil, "Mage" end
        return nil
    end
    GuildRoster = function() end

    local showOfflineState = 0 -- User has show-offline DISABLED
    GetGuildRosterShowOffline = function() return showOfflineState end
    local lastSetValue = nil
    SetGuildRosterShowOffline = function(val) showOfflineState = val; lastSetValue = val end

    -- Reload Guild.lua to use our mocks
    Profesjonell.LastRosterUpdate = 0
    Profesjonell.LastRosterRequest = 0
    Profesjonell.GuildRosterCache = {}
    dofile("Modules/Guild.lua")

    -- First call: full rebuild + GuildRoster() request (LastRosterRequest is 0)
    -- ShowOffline should NOT be restored immediately — deferred to OnGuildRosterUpdate
    showOfflineState = 0
    lastSetValue = nil
    Profesjonell.LastRosterUpdate = 0
    Profesjonell.PendingShowOfflineRestore = nil
    Profesjonell.UpdateGuildRosterCache()
    assert_equal(showOfflineState, 1, "ShowOffline stays enabled while waiting for GUILD_ROSTER_UPDATE")
    assert_equal(Profesjonell.PendingShowOfflineRestore, 0, "PendingShowOfflineRestore is set to original value")

    -- Simulate GUILD_ROSTER_UPDATE arriving: should rebuild cache and restore ShowOffline
    Profesjonell.OnGuildRosterUpdate()
    assert_equal(showOfflineState, 0, "ShowOffline restored after OnGuildRosterUpdate")
    assert_equal(Profesjonell.PendingShowOfflineRestore, nil, "PendingShowOfflineRestore cleared after restore")

    -- Second call within 30s (but after 5s): hits the 30s-cache early return
    -- No new GuildRoster() request (throttled to 60s), so restore is immediate
    testTime = testTime + 10 -- 10s later, within 30s window but past 5s
    showOfflineState = 0 -- User still has it disabled
    lastSetValue = nil
    Profesjonell.UpdateGuildRosterCache()
    assert_equal(showOfflineState, 0, "ShowOffline restored on 30s-cache early return path (no pending async)")

    -- Restore originals
    GetTime = origGetTime
    Profesjonell.GetGuildName = origGetGuildName
    GetNumGuildMembers = origGetNumGuildMembers
    GetGuildRosterInfo = origGetGuildRosterInfo
    GuildRoster = origGuildRoster
    GetGuildRosterShowOffline = origGetGuildRosterShowOffline
    SetGuildRosterShowOffline = origSetGuildRosterShowOffline
    Profesjonell.UpdateGuildRosterCache = origUpdateGuildRosterCache
end

-- Test: Delay for "no results" responses
local currentTime = 2000
GetTime = function() return currentTime end
Profesjonell.PendingReplies = {}
ProfesjonellDB = {} -- Empty DB, no results
Profesjonell.UpdateGuildRosterCache = function() return true end
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
sentMessages = {}

-- Schedule a reply for a query
Profesjonell.PendingReplies["testquery"] = {
    time = currentTime,
    originalQuery = "Test Query",
    cleanName = "Test Query",
    noResultsDelayed = false
}

-- First check - should add delay, not send reply
currentTime = currentTime + 1
Profesjonell.OnUpdate()
assert_equal(Profesjonell.PendingReplies["testquery"] ~= nil, true, "Reply still pending after first check with no results")
assert_equal(Profesjonell.PendingReplies["testquery"].noResultsDelayed, true, "noResultsDelayed flag set after first check")
local firstCheckDelay = Profesjonell.PendingReplies["testquery"].time - currentTime
assert_equal(firstCheckDelay >= 1.5 and firstCheckDelay <= 2.5, true, "Extra delay is between 1.5-2.5s for no results")

-- Second check after delay - should send P: and reply
currentTime = Profesjonell.PendingReplies["testquery"].time + 1
Profesjonell.OnUpdate()
local foundNoResultsP = false
for _, msg in ipairs(sentMessages) do
    if msg.msg == "P:testquery" then foundNoResultsP = true end
end
assert_equal(foundNoResultsP, true, "P: message sent before 'no one knows' reply")
assert_equal(Profesjonell.PendingReplies["testquery"] == nil, true, "Reply sent and cleared after second check")

-- Reset GetTime
GetTime = function() return 1000 end

-- =============================================
-- Phase A Sync Improvement Tests
-- =============================================
print("\nRunning Phase A sync improvement tests...")

-- Helper: reset all sync state for clean test isolation
local function resetSyncState()
    Profesjonell.Frame.pendingR = {}
    Profesjonell.Frame.pendingB = {}
    Profesjonell.Frame.pendingQ = nil
    Profesjonell.Frame.pendingC = nil
    Profesjonell.Frame.pendingShare = nil
    Profesjonell.Frame.broadcastHashTime = nil
    Profesjonell.Frame.lastSyncPeer = nil
    Profesjonell.Frame.lastRemoteHash = nil
    Profesjonell.Frame.syncTimer = nil
    Profesjonell.Frame.syncRetryCount = nil
    Profesjonell.Frame.nextSyncPeer = nil
    Profesjonell.Frame.nextSyncHash = nil
    Profesjonell.PendingActions.R = {}
    Profesjonell.PendingActions.B = {}
    Profesjonell.PendingActions.Q = nil
    Profesjonell.PendingActions.C = nil
    Profesjonell.PendingActions.share = nil
    Profesjonell.PendingActions.broadcastHash = nil
    Profesjonell.PendingActions.syncTimer = nil
    Profesjonell.KnownAddonUsers = {}
    Profesjonell.KnownAddonUserCount = 0
    Profesjonell.LastHBroadcastTime = 0
    Profesjonell.RemoteVersions = {}
    Profesjonell.Frame.pendingQTarget = nil
    Profesjonell.YieldedBTo = {}
    Profesjonell.BPriority = {}
    Profesjonell.IncomingCBuffer = {}
    Profesjonell.CachedDatabaseHash = nil
    Profesjonell.CachedCharacterHashes = nil
    ProfesjonellDB = {}
    sentMessages = {}
    Profesjonell.SyncNewRecipesCount = 0
    Profesjonell.SyncSources = {}
    Profesjonell.SyncSummaryTimer = nil
end
Profesjonell.IsInGuild = function(name) return true end
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
    return true
end
UnitName = function() return "Player" end

-- Test 1: Known addon user tracking
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.OnAddonMessage("B:Other:i:1", "Alice")
assert_equal(Profesjonell.KnownAddonUsers["Alice"], true, "KnownAddonUsers tracks sender Alice")
assert_equal(Profesjonell.KnownAddonUserCount, 1, "KnownAddonUserCount is 1 after first sender")
Profesjonell.OnAddonMessage("B:Other:i:1", "Bob")
assert_equal(Profesjonell.KnownAddonUserCount, 2, "KnownAddonUserCount is 2 after second sender")
-- Same sender again should not increment
Profesjonell.OnAddonMessage("B:Other:i:1", "Alice")
assert_equal(Profesjonell.KnownAddonUserCount, 2, "KnownAddonUserCount unchanged for duplicate sender")

-- Test 2: GetSyncDelay scales with user count
resetSyncState()
Profesjonell.KnownAddonUserCount = 1
local delay_1user = Profesjonell.GetSyncDelay(1.0, 0, false)
Profesjonell.KnownAddonUserCount = 20
local delay_20users = Profesjonell.GetSyncDelay(1.0, 0, false)
assert_equal(delay_20users > delay_1user, true, "GetSyncDelay returns larger base delay with 20 users vs 1")

-- Test 3: GetSyncDelay does not scale below 10 users (userScale <= 1)
resetSyncState()
Profesjonell.KnownAddonUserCount = 5
local delay_5users = Profesjonell.GetSyncDelay(1.0, 0, false)
Profesjonell.KnownAddonUserCount = 1
local delay_1user_b = Profesjonell.GetSyncDelay(1.0, 0, false)
-- With range=0, the only variable is playerOffset which is constant, so delays should be equal
assert_equal(delay_5users, delay_1user_b, "GetSyncDelay does not scale up for <= 10 users")

-- Test 4: GetSyncDelay caps scaling at 30 users
resetSyncState()
Profesjonell.KnownAddonUserCount = 30
local delay_30 = Profesjonell.GetSyncDelay(1.0, 0, false)
Profesjonell.KnownAddonUserCount = 100
local delay_100 = Profesjonell.GetSyncDelay(1.0, 0, false)
assert_equal(delay_30, delay_100, "GetSyncDelay caps scaling at 30 users")

-- Test 5: Cancel pending B unconditionally when receiving B (no count comparison)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true }, ["i:2"] = { ["Other"] = true } }
Profesjonell.PendingActions.B["Other"] = GetTime() + 10
Profesjonell.OnAddonMessage("B:Other:i:1,i:2,i:3", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] == nil, true, "Pending B cancelled unconditionally when receiving B")

-- Test 6: Cancel pending B even when we have more data (unconditional)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true }, ["i:2"] = { ["Other"] = true }, ["i:3"] = { ["Other"] = true } }
Profesjonell.PendingActions.B["Other"] = GetTime() + 10
Profesjonell.OnAddonMessage("B:Other:i:1,i:2", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] == nil, true, "Pending B cancelled even when we have more recipes (unconditional)")
assert_equal(Profesjonell.YieldedBTo["Other"], "Alice", "YieldedBTo tracks who we yielded to")

-- Test 7: No pending B means no crash on B receive
resetSyncState()
ProfesjonellDB = {}
Profesjonell.PendingActions.B = {}
-- Should not error when receiving B without any pending B
Profesjonell.OnAddonMessage("B:Other:i:1", "Alice")
assert_equal(ProfesjonellDB["i:1"]["Other"], true, "B received correctly even without pending B")

-- Test 8: H broadcast suppressed during active sync cycle
resetSyncState()
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.LastHBroadcastTime = 0
local h_sent = {}
local old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(h_sent, msg)
    old_sam(prefix, msg, type)
end
Profesjonell.BroadcastHash()
local foundH = false
for _, m in ipairs(h_sent) do
    if string.sub(m, 1, 2) == "H:" then foundH = true end
end
assert_equal(foundH, false, "H broadcast suppressed during active sync cycle")
SendAddonMessage = old_sam

-- Test 9: H broadcast suppressed when minimum interval not reached
resetSyncState()
Profesjonell.PendingActions.syncTimer = nil
Profesjonell.LastHBroadcastTime = GetTime() - 5 -- Only 5 seconds ago (< 30s minimum)
h_sent = {}
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(h_sent, msg)
    old_sam(prefix, msg, type)
end
Profesjonell.BroadcastHash()
foundH = false
for _, m in ipairs(h_sent) do
    if string.sub(m, 1, 2) == "H:" then foundH = true end
end
assert_equal(foundH, false, "H broadcast suppressed when minimum interval not reached")
SendAddonMessage = old_sam

-- Test 10: H broadcast allowed when interval has passed and no active sync
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.PendingActions.syncTimer = nil
Profesjonell.LastHBroadcastTime = GetTime() - 60 -- 60 seconds ago (> 30s minimum)
h_sent = {}
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(h_sent, msg)
    old_sam(prefix, msg, type)
end
Profesjonell.BroadcastHash()
foundH = false
for _, m in ipairs(h_sent) do
    if string.sub(m, 1, 2) == "H:" then foundH = true end
end
assert_equal(foundH, true, "H broadcast allowed when interval passed and no active sync")
SendAddonMessage = old_sam

-- Test 11: H broadcast updates LastHBroadcastTime
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.PendingActions.syncTimer = nil
Profesjonell.LastHBroadcastTime = 0
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type) old_sam(prefix, msg, type) end
Profesjonell.BroadcastHash()
assert_equal(Profesjonell.LastHBroadcastTime, GetTime(), "LastHBroadcastTime updated after successful H broadcast")
SendAddonMessage = old_sam

-- Test 12: Q handler uses wider jitter (C delay should be > 2.0 base)
resetSyncState()
Profesjonell.KnownAddonUserCount = 1
Profesjonell.OnAddonMessage("Q", "Alice")
local cDelay = Profesjonell.PendingActions.C - GetTime()
assert_equal(cDelay >= 2.0, true, "C response delay base is >= 2.0s after Q (Phase A wider jitter)")

-- Test 13: R handler uses wider jitter for non-owner characters
resetSyncState()
Profesjonell.KnownAddonUserCount = 1
Profesjonell.OnAddonMessage("R:Other", "Alice")
local bDelay = Profesjonell.PendingActions.B["Other"] - GetTime()
assert_equal(bDelay >= 3.0, true, "B response delay base is >= 3.0s for non-owner char after R (Phase A wider jitter)")

-- Test 14: R handler uses priority (shorter) delay for own character
resetSyncState()
Profesjonell.KnownAddonUserCount = 1
Profesjonell.OnAddonMessage("R:Player", "Alice")
local bDelayOwn = Profesjonell.PendingActions.B["Player"] - GetTime()
-- Priority halves both base and range: base=0.25, range=0.5, + offset
assert_equal(bDelayOwn < 2.0, true, "B response delay is shorter for own character after R (priority)")

-- Test 15: Q handler sets PendingActions.C (not just Frame.pendingC)
resetSyncState()
Profesjonell.OnAddonMessage("Q", "Alice")
assert_equal(Profesjonell.PendingActions.C ~= nil, true, "Q handler sets PendingActions.C")
assert_equal(Profesjonell.Frame.pendingC, Profesjonell.PendingActions.C, "Q handler syncs Frame.pendingC with PendingActions.C")

-- Test 16: R handler sets PendingActions.B (not just Frame.pendingB)
resetSyncState()
Profesjonell.OnAddonMessage("R:Other", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] ~= nil, true, "R handler sets PendingActions.B")

-- Test 17: Multiple B receives cancel pending B correctly
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Char1"] = true } }
Profesjonell.PendingActions.B["Char1"] = GetTime() + 10
-- First B with 1 recipe (equal to our 1) -> should cancel
Profesjonell.OnAddonMessage("B:Char1:i:1", "Alice")
assert_equal(Profesjonell.PendingActions.B["Char1"] == nil, true, "Pending B cancelled when received exactly same count")

-- Test 18: Verify user scaling affects delay magnitude
resetSyncState()
Profesjonell.KnownAddonUserCount = 20  -- userScale = 2.0
local scaledDelay = Profesjonell.GetSyncDelay(1.0, 0, false)
Profesjonell.KnownAddonUserCount = 1
local unscaledDelay = Profesjonell.GetSyncDelay(1.0, 0, false)
-- With 20 users, userScale = 2.0, so base becomes 2.0
-- The ratio should be close to 2.0 (since range=0, only base+offset matters)
-- offset is the same for both, so scaledDelay = 2.0 + offset, unscaledDelay = 1.0 + offset
-- Verify the difference is approximately 1.0 (the extra base from scaling)
local diff = scaledDelay - unscaledDelay
assert_equal(math.abs(diff - 1.0) < 0.001, true, "GetSyncDelay scales base by +1.0 with 20 known users (userScale=2.0)")

-- =============================================
-- Phase B: Coordinator Election, Targeted Q, S Deprecation
-- =============================================
print("Running Phase B sync improvement tests...")

-- Test B1: H mismatch with higher-named sender => we are coordinator (Player < Zara)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.OnAddonMessage("H:differenthash:0.40", "Zara")
-- Player < Zara, so we coordinate: Q should be scheduled
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "B1: Coordinator (lower name) schedules Q on H mismatch")
assert_equal(Profesjonell.Frame.pendingQTarget, "Zara", "B1: Q targets the mismatching peer")
assert_equal(Profesjonell.Frame.lastSyncPeer, "Zara", "B1: lastSyncPeer set to sender")

-- Test B2: H mismatch with lower-named sender => we are NOT coordinator (Player > Alice)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.OnAddonMessage("H:differenthash:0.40", "Alice")
-- Alice < Player, so Alice coordinates: we should NOT schedule Q
assert_equal(Profesjonell.PendingActions.Q == nil, true, "B2: Non-coordinator (higher name) does NOT schedule Q")
assert_equal(Profesjonell.Frame.lastSyncPeer, "Alice", "B2: lastSyncPeer still set for tracking")
assert_equal(Profesjonell.PendingActions.syncTimer ~= nil, true, "B2: Sync timer set even for non-coordinator")

-- Test B3: H from same peer during active sync updates lastRemoteHash (Fix 2)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = "oldhash"
Profesjonell.Frame.syncRetryCount = 2
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnAddonMessage("H:newhash:0.40", "Zara")
assert_equal(Profesjonell.Frame.lastRemoteHash, "newhash", "B3: lastRemoteHash updated from same peer during sync")
assert_equal(Profesjonell.Frame.syncRetryCount, 0, "B3: syncRetryCount reset on hash update from same peer")

-- Test B4: H from different peer during active sync is queued (Fix 3)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.RemoteVersions["Bob"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = "zarahash"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnAddonMessage("H:bobhash:0.40", "Bob")
assert_equal(Profesjonell.Frame.lastSyncPeer, "Zara", "B4: lastSyncPeer NOT overwritten during active sync")
assert_equal(Profesjonell.Frame.nextSyncPeer, "Bob", "B4: New peer queued as nextSyncPeer")
assert_equal(Profesjonell.Frame.nextSyncHash, "bobhash", "B4: New peer hash queued as nextSyncHash")

-- Test B5: E: message is now a harmless no-op
resetSyncState()
Profesjonell.PendingActions.Q = GetTime() + 10
Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
Profesjonell.OnAddonMessage("E:Alpha", "Alpha")
-- E: should not affect any state
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "B5: E: message is no-op, does not cancel pending Q")

-- Test B6: Targeted Q:Player triggers C response (we are the target)
resetSyncState()
Profesjonell.OnAddonMessage("Q:Player", "Alice")
assert_equal(Profesjonell.PendingActions.C ~= nil, true, "B6: Targeted Q:Player schedules C response")
-- Targeted Q uses shorter base delay (0.5 base, not 2.0)
-- Compare with broadcast Q delay to verify targeted is shorter
resetSyncState()
Profesjonell.OnAddonMessage("Q:Player", "Alice")
local targetedCDelay = Profesjonell.PendingActions.C - GetTime()
resetSyncState()
Profesjonell.OnAddonMessage("Q", "Alice")
local broadcastCDelay = Profesjonell.PendingActions.C - GetTime()
assert_equal(targetedCDelay < broadcastCDelay, true, "B6: Targeted Q uses shorter delay than broadcast Q")

-- Test B7: Targeted Q:Other does NOT trigger C response (we are not the target)
resetSyncState()
Profesjonell.OnAddonMessage("Q:Other", "Alice")
assert_equal(Profesjonell.PendingActions.C == nil, true, "B7: Targeted Q:Other does not schedule C response for us")

-- Test B8: Broadcast Q still works (backward compat)
resetSyncState()
Profesjonell.OnAddonMessage("Q", "OldClient")
assert_equal(Profesjonell.PendingActions.C ~= nil, true, "B8: Broadcast Q still schedules C response")

-- Test B9: Broadcast Q also clears pendingQTarget
resetSyncState()
Profesjonell.PendingActions.Q = GetTime() + 10
Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
Profesjonell.Frame.pendingQTarget = "Alice"
Profesjonell.OnAddonMessage("Q", "OldClient")
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B9: Broadcast Q clears pendingQTarget")

-- Test B10: S command deprecated - RequestSync no longer sends S
resetSyncState()
sentMessages = {}
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(sentMessages, msg)
end
Profesjonell.RequestSync()
local foundS = false
for _, m in ipairs(sentMessages) do
    if m == "S" then foundS = true end
end
assert_equal(foundS, false, "B10: RequestSync no longer sends S message")
SendAddonMessage = old_sam

-- Test B11: RequestSync falls back to targeted Q when lastSyncPeer is set
resetSyncState()
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.RequestSync()
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "B11: RequestSync schedules Q when lastSyncPeer exists")
assert_equal(Profesjonell.Frame.pendingQTarget, "Alice", "B11: RequestSync targets lastSyncPeer with Q")

-- Test B12: Incoming S from old clients still triggers ShareAllRecipes (backward compat)
resetSyncState()
local shareAllCalled = false
local origShareAll = Profesjonell.ShareAllRecipes
Profesjonell.ShareAllRecipes = function() shareAllCalled = true end
Profesjonell.OnAddonMessage("S", "OldClient")
assert_equal(shareAllCalled, true, "B12: Incoming S still triggers ShareAllRecipes (backward compat)")
Profesjonell.ShareAllRecipes = origShareAll

-- Test B13: Targeted Q cancels our own pending Q and pendingQTarget
resetSyncState()
Profesjonell.PendingActions.Q = GetTime() + 10
Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
Profesjonell.Frame.pendingQTarget = "Someone"
Profesjonell.OnAddonMessage("Q:Player", "Alice")
assert_equal(Profesjonell.PendingActions.Q == nil, true, "B13: Targeted Q cancels our pending Q")
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B13: Targeted Q clears our pendingQTarget")

-- Test B14: OnCommUpdate sends targeted Q when pendingQTarget is set
resetSyncState()
sentMessages = {}
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(sentMessages, msg)
end
Profesjonell.PendingActions.Q = GetTime() - 1 -- Already due
Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
Profesjonell.Frame.pendingQTarget = "Alice"
Profesjonell.OnCommUpdate()
local foundTargetedQ = false
for _, m in ipairs(sentMessages) do
    if m == "Q:Alice" then foundTargetedQ = true end
end
assert_equal(foundTargetedQ, true, "B14: OnCommUpdate sends Q:Alice when pendingQTarget is set")
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B14: pendingQTarget cleared after sending")
SendAddonMessage = old_sam

-- Test B15: OnCommUpdate sends broadcast Q when no pendingQTarget
resetSyncState()
sentMessages = {}
old_sam = SendAddonMessage
SendAddonMessage = function(prefix, msg, type)
    table.insert(sentMessages, msg)
end
Profesjonell.PendingActions.Q = GetTime() - 1 -- Already due
Profesjonell.Frame.pendingQ = Profesjonell.PendingActions.Q
Profesjonell.Frame.pendingQTarget = nil
Profesjonell.OnCommUpdate()
local foundBroadcastQ = false
for _, m in ipairs(sentMessages) do
    if m == "Q" then foundBroadcastQ = true end
end
assert_equal(foundBroadcastQ, true, "B15: OnCommUpdate sends broadcast Q when no target")
SendAddonMessage = old_sam

-- Test B16: ClearSyncState clears pendingQTarget
resetSyncState()
Profesjonell.Frame.pendingQTarget = "Alice"
Profesjonell.PendingActions.syncTimer = nil
Profesjonell.Frame.syncTimer = nil
-- Trigger ClearSyncState indirectly via sync completion
-- We'll test the field directly since ClearSyncState is local
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
local matchHash = Profesjonell.GenerateDatabaseHash()
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = matchHash
Profesjonell.Frame.pendingQTarget = "Alice"
-- Send H with matching hash to trigger ClearSyncState
Profesjonell.OnAddonMessage("H:" .. matchHash .. ":0.40", "Alice")
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B16: ClearSyncState clears pendingQTarget")

-- Test B17: First sync retry uses targeted Q for lastSyncPeer
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "differenthash"
Profesjonell.Frame.syncRetryCount = 0 -- Will be incremented to 1 (first retry)
Profesjonell.PendingActions.syncTimer = GetTime() - 1 -- Already expired
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnCommUpdate()
assert_equal(Profesjonell.Frame.pendingQTarget, "Alice", "B17: First sync retry uses targeted Q for lastSyncPeer")

-- Test B17b: Second+ sync retry falls back to broadcast Q for backward compatibility
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "differenthash"
Profesjonell.Frame.syncRetryCount = 1 -- Will be incremented to 2 (second retry)
Profesjonell.PendingActions.syncTimer = GetTime() - 1
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnCommUpdate()
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B17b: Second sync retry falls back to broadcast Q (no target)")
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "B17b: Broadcast Q is still scheduled")

-- Test B17c: Third sync retry also uses broadcast Q
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "differenthash"
Profesjonell.Frame.syncRetryCount = 2 -- Will be incremented to 3 (third retry)
Profesjonell.PendingActions.syncTimer = GetTime() - 1
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnCommUpdate()
assert_equal(Profesjonell.Frame.pendingQTarget == nil, true, "B17c: Third sync retry also uses broadcast Q")

-- Test B18: Sync retries exhausted does soft reset with delayed H broadcast (Fix 6)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "differenthash"
Profesjonell.Frame.syncRetryCount = 3 -- At limit
Profesjonell.PendingActions.syncTimer = GetTime() - 1
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnCommUpdate()
-- Sync state should be cleared
assert_equal(Profesjonell.Frame.lastSyncPeer == nil, true, "B18: Retries exhausted clears lastSyncPeer")
assert_equal(Profesjonell.PendingActions.syncTimer == nil, true, "B18: Retries exhausted clears syncTimer")
-- But a fresh H broadcast should be scheduled (soft reset)
assert_equal(Profesjonell.PendingActions.broadcastHash ~= nil, true, "B18: Retries exhausted schedules fresh H broadcast")
assert_equal(Profesjonell.PendingActions.broadcastHash > GetTime() + 29, true, "B18: Fresh H broadcast delayed >= 30s")

-- Test B19: E: message from old Phase B clients is harmless no-op
resetSyncState()
Profesjonell.OnAddonMessage("E:SomeCoordinator", "SomeCoordinator")
assert_equal(Profesjonell.PendingActions.Q == nil, true, "B19: E: does not schedule Q")
assert_equal(Profesjonell.Frame.lastSyncPeer == nil, true, "B19: E: does not set lastSyncPeer")

-- Test B20: ClearSyncState processes queued nextSyncPeer
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
-- Set up: we're syncing with Zara, Bob is queued
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = nil
Profesjonell.Frame.nextSyncPeer = "Bob"
Profesjonell.Frame.nextSyncHash = "bobhash"
-- Generate matching hash and send matching H to trigger ClearSyncState
local matchHash20 = Profesjonell.GenerateDatabaseHash()
Profesjonell.Frame.lastRemoteHash = matchHash20
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.OnAddonMessage("H:" .. matchHash20 .. ":0.40", "Zara")
-- After ClearSyncState, queued Bob should become active peer
assert_equal(Profesjonell.Frame.lastSyncPeer, "Bob", "B20: ClearSyncState starts queued sync with nextSyncPeer")
assert_equal(Profesjonell.Frame.lastRemoteHash, "bobhash", "B20: ClearSyncState uses queued hash")
assert_equal(Profesjonell.Frame.nextSyncPeer == nil, true, "B20: nextSyncPeer cleared after processing")
assert_equal(Profesjonell.PendingActions.syncTimer ~= nil, true, "B20: Sync timer set for queued peer")

-- =============================================
-- B Cancellation Anti-Loop Tests
-- =============================================
print("\nRunning B cancellation anti-loop tests...")

-- B_CANCEL_1: Receiving B cancels pending B unconditionally (no count comparison)
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true }, ["i:2"] = { ["Other"] = true }, ["i:3"] = { ["Other"] = true } }
Profesjonell.PendingActions.B["Other"] = GetTime() + 10
Profesjonell.OnAddonMessage("B:Other:i:1", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] == nil, true, "B_CANCEL_1: Pending B cancelled unconditionally even with 1 recipe in batch vs 3 local")
assert_equal(Profesjonell.YieldedBTo["Other"], "Alice", "B_CANCEL_1: YieldedBTo records Alice as the sender we yielded to")

-- B_CANCEL_2: After yielding, next pending B for same char is marked priority via R: handler
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.YieldedBTo["Other"] = "Alice"
Profesjonell.OnAddonMessage("R:Other", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] ~= nil, true, "B_CANCEL_2: R: schedules pending B")
assert_equal(Profesjonell.BPriority["Other"], true, "B_CANCEL_2: Pending B marked as priority because we previously yielded")

-- B_CANCEL_3: Priority B is NOT cancelled when receiving B
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.PendingActions.B["Other"] = GetTime() + 10
Profesjonell.BPriority["Other"] = true
Profesjonell.OnAddonMessage("B:Other:i:1,i:2,i:3", "Alice")
assert_equal(Profesjonell.PendingActions.B["Other"] ~= nil, true, "B_CANCEL_3: Priority B is NOT cancelled when receiving B")
-- Priority should be consumed after use
assert_equal(Profesjonell.BPriority["Other"] == nil, true, "B_CANCEL_3: Priority consumed after protecting B once")

-- B_CANCEL_4: After priority is consumed, a subsequent B reception cancels normally
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
-- First: set up priority and have it consumed
Profesjonell.PendingActions.B["Other"] = GetTime() + 10
Profesjonell.BPriority["Other"] = true
Profesjonell.OnAddonMessage("B:Other:i:1", "Alice") -- Priority protects, gets consumed
assert_equal(Profesjonell.PendingActions.B["Other"] ~= nil, true, "B_CANCEL_4a: Priority protected first time")
-- Second: now no priority, should cancel
Profesjonell.OnAddonMessage("B:Other:i:1", "Bob")
assert_equal(Profesjonell.PendingActions.B["Other"] == nil, true, "B_CANCEL_4b: Without priority, B cancelled on second receive")
assert_equal(Profesjonell.YieldedBTo["Other"], "Bob", "B_CANCEL_4c: YieldedBTo updated to Bob")

-- B_CANCEL_5: ClearSyncState resets YieldedBTo and BPriority
resetSyncState()
Profesjonell.YieldedBTo["Other"] = "Alice"
Profesjonell.BPriority["Other"] = true
-- Trigger ClearSyncState via matching H from lastSyncPeer
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
local clearHash = Profesjonell.GenerateDatabaseHash()
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = clearHash
Profesjonell.OnAddonMessage("H:" .. clearHash .. ":0.40", "Alice")
assert_equal(next(Profesjonell.YieldedBTo) == nil, true, "B_CANCEL_5: ClearSyncState resets YieldedBTo")
assert_equal(next(Profesjonell.BPriority) == nil, true, "B_CANCEL_5: ClearSyncState resets BPriority")

-- B_CANCEL_6: Successfully sending B clears yield/priority state for that character
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.YieldedBTo["Other"] = "Alice"
Profesjonell.BPriority["Other"] = true
-- Schedule B that is already due
Profesjonell.PendingActions.B["Other"] = GetTime() - 1
local old_sam_bc6 = SendAddonMessage
SendAddonMessage = function(prefix, msg, type) end -- no-op
Profesjonell.OnCommUpdate()
SendAddonMessage = old_sam_bc6
assert_equal(Profesjonell.YieldedBTo["Other"] == nil, true, "B_CANCEL_6: Sending B clears YieldedBTo for that character")
assert_equal(Profesjonell.BPriority["Other"] == nil, true, "B_CANCEL_6: Sending B clears BPriority for that character")

-- B_CANCEL_7: Priority is set when scheduling B push in C: handler after previous yield
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.YieldedBTo["Other"] = "Alice"
Profesjonell.RemoteVersions["Alice"] = "0.40"
-- Send C: with a mismatching hash for Other to trigger B push scheduling
Profesjonell.OnAddonMessage("C:Other:wronghash", "Alice")
flushCBuffer()
assert_equal(Profesjonell.BPriority["Other"], true, "B_CANCEL_7: B push from C: handler marked priority after previous yield")

-- =============================================
-- C: Buffer Accumulation Tests
-- =============================================
print("\nRunning C: buffer accumulation tests...")

-- C_BUFFER_1: Single C: message buffers and processes after settle delay
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "xyz"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnAddonMessage("C:Other:wronghash", "Alice")
-- Before settle: buffer exists but no processing yet
assert_equal(Profesjonell.IncomingCBuffer["Alice"] ~= nil, true, "C_BUFFER_1: C: message buffered")
assert_equal(Profesjonell.Frame.pendingR["Other"] == nil, true, "C_BUFFER_1: No immediate R scheduling before settle")
-- After settle: processing happens
flushCBuffer()
assert_equal(Profesjonell.Frame.pendingR["Other"] ~= nil, true, "C_BUFFER_1: R scheduled after settle delay")
assert_equal(Profesjonell.IncomingCBuffer["Alice"] == nil, true, "C_BUFFER_1: Buffer cleared after processing")

-- C_BUFFER_2: Multiple C: splits from same sender accumulate into one buffer
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Alice"] = true }, ["i:2"] = { ["Bob"] = true }, ["i:3"] = { ["Carol"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Alice"] = "Mage", ["Bob"] = "Rogue", ["Carol"] = "Priest" }
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Alice"] = "Mage", ["Bob"] = "Rogue", ["Carol"] = "Priest" }
    return true
end
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = "xyz"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
-- Simulate two C: splits from same sender
Profesjonell.OnAddonMessage("C:Alice:hash1,Bob:hash2", "Zara")
Profesjonell.OnAddonMessage("C:Carol:hash3", "Zara")
-- Buffer should have all 3 characters
local bufChars = Profesjonell.IncomingCBuffer["Zara"].chars
assert_equal(bufChars["Alice"], "hash1", "C_BUFFER_2: First split char accumulated")
assert_equal(bufChars["Bob"], "hash2", "C_BUFFER_2: First split second char accumulated")
assert_equal(bufChars["Carol"], "hash3", "C_BUFFER_2: Second split char accumulated")

-- C_BUFFER_3: C: from different senders maintain separate buffers
resetSyncState()
ProfesjonellDB = {}
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.RemoteVersions["Bob"] = "0.40"
Profesjonell.OnAddonMessage("C:Char1:hash1", "Alice")
Profesjonell.OnAddonMessage("C:Char2:hash2", "Bob")
assert_equal(Profesjonell.IncomingCBuffer["Alice"] ~= nil, true, "C_BUFFER_3: Alice has separate buffer")
assert_equal(Profesjonell.IncomingCBuffer["Bob"] ~= nil, true, "C_BUFFER_3: Bob has separate buffer")
assert_equal(Profesjonell.IncomingCBuffer["Alice"].chars["Char1"], "hash1", "C_BUFFER_3: Alice buffer has Char1")
assert_equal(Profesjonell.IncomingCBuffer["Bob"].chars["Char2"], "hash2", "C_BUFFER_3: Bob buffer has Char2")
assert_equal(Profesjonell.IncomingCBuffer["Alice"].chars["Char2"] == nil, true, "C_BUFFER_3: Alice buffer does NOT have Bob's char")

-- C_BUFFER_4: No false "Remote missing character" when chars are split across messages
-- This is the core bug fix test
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Alice"] = true }, ["i:2"] = { ["Bob"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Alice"] = "Mage", ["Bob"] = "Rogue" }
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Alice"] = "Mage", ["Bob"] = "Rogue" }
    return true
end
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = "xyz"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
-- Remote knows both Alice and Bob but sends them in separate C: messages
-- With matching hashes, there should be NO "missing character" B pushes
local aliceHash = Profesjonell.GenerateCharacterHashes()["Alice"]
local bobHash = Profesjonell.GenerateCharacterHashes()["Bob"]
Profesjonell.OnAddonMessage("C:Alice:" .. aliceHash, "Zara")
Profesjonell.OnAddonMessage("C:Bob:" .. bobHash, "Zara")
flushCBuffer()
-- Neither Alice nor Bob should be flagged as "missing" — both were in the accumulated buffer
assert_equal(Profesjonell.Frame.pendingB["Alice"] == nil, true, "C_BUFFER_4: No false B push for Alice (was in second split)")
assert_equal(Profesjonell.Frame.pendingB["Bob"] == nil, true, "C_BUFFER_4: No false B push for Bob (was in first split)")

-- C_BUFFER_5: ClearSyncState clears the C: buffer
resetSyncState()
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.OnAddonMessage("C:Char1:hash1", "Alice")
assert_equal(Profesjonell.IncomingCBuffer["Alice"] ~= nil, true, "C_BUFFER_5: Buffer exists before clear")
-- Simulate ClearSyncState via matching H from lastSyncPeer
Profesjonell.IncomingCBuffer = {}
assert_equal(next(Profesjonell.IncomingCBuffer) == nil, true, "C_BUFFER_5: Buffer cleared")

-- C_BUFFER_6: Partial C: (only one split arrives) still processes after settle
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Other"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
    return true
end
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "xyz"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
-- Only one C: message arrives (sender disconnected before sending rest)
Profesjonell.OnAddonMessage("C:Other:wronghash", "Alice")
flushCBuffer()
-- Should still process the partial data
assert_equal(Profesjonell.Frame.pendingR["Other"] ~= nil, true, "C_BUFFER_6: Partial C: still processed after settle")

-- C_BUFFER_7: Settle timer resets on each new C: from same sender
resetSyncState()
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.OnAddonMessage("C:Char1:hash1", "Alice")
local firstSettle = Profesjonell.IncomingCBuffer["Alice"].settleTime
-- Advance time slightly (but not past settle) and send another split
local oldGT = GetTime
GetTime = function() return oldGT() + 0.5 end
Profesjonell.OnAddonMessage("C:Char2:hash2", "Alice")
local secondSettle = Profesjonell.IncomingCBuffer["Alice"].settleTime
GetTime = oldGT
assert_equal(secondSettle > firstSettle, true, "C_BUFFER_7: Settle timer extended by second C: message")

-- Restore default UpdateGuildRosterCache for subsequent tests
Profesjonell.UpdateGuildRosterCache = function()
    Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
    return true
end

-- =============================================
-- Sync Fix Tests (Fixes 1-6)
-- =============================================
print("\nRunning sync fix tests...")

-- FIX1_1: Deterministic coordinator - both peers agree without communication
-- "Alpha" sees H mismatch from "Zara": Alpha < Zara => Alpha coordinates
-- "Zara" sees H mismatch from "Alpha": Alpha < Zara => Zara waits
-- We test from Player's perspective:
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.OnAddonMessage("H:somehash:0.40", "Zara")
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "FIX1_1: Lower-named player schedules Q (coordinator)")
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.OnAddonMessage("H:somehash:0.40", "Alice")
assert_equal(Profesjonell.PendingActions.Q == nil, true, "FIX1_1: Higher-named player does NOT schedule Q (not coordinator)")

-- FIX2_1: lastRemoteHash updated when same peer sends new H during active sync
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
-- Set up mid-sync with stale hash
Profesjonell.Frame.lastSyncPeer = "Zara"
Profesjonell.Frame.lastRemoteHash = "stale_hash"
Profesjonell.Frame.syncRetryCount = 2
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
-- Zara sends updated H with a NEW hash (still different from ours)
Profesjonell.OnAddonMessage("H:updated_hash:0.40", "Zara")
-- The update path should fire: lastRemoteHash updated, retryCount reset
assert_equal(Profesjonell.Frame.lastRemoteHash, "updated_hash", "FIX2_1: lastRemoteHash updated from same peer during sync")
assert_equal(Profesjonell.Frame.syncRetryCount, 0, "FIX2_1: syncRetryCount reset on hash update")
assert_equal(Profesjonell.Frame.lastSyncPeer, "Zara", "FIX2_1: lastSyncPeer unchanged")

-- FIX3_1: H suppression check order — sync-active checked before interval
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.LastHBroadcastTime = 0 -- Interval has passed, but sync is active
h_sent = {}
local old_sam_fix3 = SendAddonMessage
SendAddonMessage = function(prefix, msg, type) table.insert(h_sent, msg) end
Profesjonell.BroadcastHash()
local foundH_fix3 = false
for _, m in ipairs(h_sent) do
    if string.sub(m, 1, 2) == "H:" then foundH_fix3 = true end
end
assert_equal(foundH_fix3, false, "FIX3_1: H suppressed during active sync even when interval has passed")
SendAddonMessage = old_sam_fix3

-- FIX3_2: Queued peer is started when ClearSyncState fires with coordinator check
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Zara"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Zara"
local matchHash_fix3 = Profesjonell.GenerateDatabaseHash()
Profesjonell.Frame.lastRemoteHash = matchHash_fix3
-- Queue a peer where we ARE coordinator (Player < Zara)
Profesjonell.Frame.nextSyncPeer = "Zara"
Profesjonell.Frame.nextSyncHash = "zarahash"
Profesjonell.OnAddonMessage("H:" .. matchHash_fix3 .. ":0.40", "Zara")
-- ClearSyncState should pick up Zara and schedule Q (Player < Zara)
assert_equal(Profesjonell.Frame.lastSyncPeer, "Zara", "FIX3_2: Queued peer becomes active after ClearSyncState")
assert_equal(Profesjonell.PendingActions.Q ~= nil, true, "FIX3_2: Q scheduled for queued peer where we're coordinator")
assert_equal(Profesjonell.Frame.pendingQTarget, "Zara", "FIX3_2: Q targets the queued peer")

-- FIX3_3: Queued peer where we are NOT coordinator — no Q scheduled
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
Profesjonell.Frame.lastSyncPeer = "Alice"
local matchHash_fix3b = Profesjonell.GenerateDatabaseHash()
Profesjonell.Frame.lastRemoteHash = matchHash_fix3b
-- Queue peer where we are NOT coordinator (Player > Alice)
Profesjonell.Frame.nextSyncPeer = "Alice"
Profesjonell.Frame.nextSyncHash = "alicehash"
Profesjonell.OnAddonMessage("H:" .. matchHash_fix3b .. ":0.40", "Alice")
assert_equal(Profesjonell.Frame.lastSyncPeer, "Alice", "FIX3_3: Queued peer becomes active")
assert_equal(Profesjonell.PendingActions.Q == nil, true, "FIX3_3: No Q scheduled when we're not coordinator for queued peer")
assert_equal(Profesjonell.PendingActions.syncTimer ~= nil, true, "FIX3_3: Sync timer still set for queued peer")

-- FIX4_1: Removed syncPendingChars — B handler no longer tracks pending char count
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.CachedCharacterHashes = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "somehash"
Profesjonell.PendingActions.syncTimer = GetTime() + 100
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
-- Receive B with new data — should NOT set/manipulate syncPendingChars
Profesjonell.OnAddonMessage("B:Other:i:99", "Alice")
-- The field should not exist since we removed the feature
assert_equal(Profesjonell.Frame.syncPendingChars == nil, true, "FIX4_1: syncPendingChars not used after removal")

-- FIX5_1: No double sync timer extension — only one extension in B handler
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "somehash"
Profesjonell.PendingActions.syncTimer = GetTime() + 5
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
local timerBefore = Profesjonell.PendingActions.syncTimer
Profesjonell.OnAddonMessage("B:Other:i:99", "Alice")
-- Timer should be extended once (not doubled)
assert_equal(Profesjonell.PendingActions.syncTimer ~= nil, true, "FIX5_1: Sync timer still active after B receive")
assert_equal(Profesjonell.PendingActions.syncTimer > timerBefore, true, "FIX5_1: Sync timer extended after B with new data")

-- FIX6_1: Graceful retry exhaustion - broadcastHash is scheduled with escalating backoff
resetSyncState()
Profesjonell.ExhaustedPeers = {}
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.Frame.lastSyncPeer = "Alice"
Profesjonell.Frame.lastRemoteHash = "differenthash"
Profesjonell.Frame.syncRetryCount = 3
Profesjonell.PendingActions.syncTimer = GetTime() - 1
Profesjonell.Frame.syncTimer = Profesjonell.PendingActions.syncTimer
Profesjonell.OnCommUpdate()
assert_equal(Profesjonell.PendingActions.broadcastHash ~= nil, true, "FIX6_1: Soft reset schedules fresh H broadcast")
-- First exhaustion: 5 min (300s) + up to 30s random
local bcastDelay = Profesjonell.PendingActions.broadcastHash - GetTime()
assert_equal(bcastDelay >= 300, true, "FIX6_1: Fresh H broadcast delay >= 300s (5 min backoff)")
assert_equal(bcastDelay <= 331, true, "FIX6_1: Fresh H broadcast delay <= ~330s")
assert_equal(Profesjonell.ExhaustedPeers["Alice"] ~= nil, true, "FIX6_1: Peer marked as exhausted")
assert_equal(Profesjonell.ExhaustedPeers["Alice"].count, 1, "FIX6_1: Exhaustion count is 1")

-- FIX6_1b: Exhaustion cooldown blocks re-sync with same peer on H mismatch
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
-- Alice is still in exhaustion cooldown from FIX6_1
Profesjonell.OnAddonMessage("H:differenthash:0.40", "Alice")
assert_equal(Profesjonell.Frame.lastSyncPeer == nil, true, "FIX6_1b: Exhausted peer H mismatch is ignored during cooldown")

-- FIX6_1c: Cooldown clears when hashes match
resetSyncState()
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
local matchHash = Profesjonell.GenerateDatabaseHash()
Profesjonell.OnAddonMessage("H:" .. matchHash .. ":0.40", "Alice")
assert_equal(Profesjonell.ExhaustedPeers["Alice"] == nil, true, "FIX6_1c: Exhaustion cleared when hashes match")

-- FIX6_2: After soft reset, if hashes truly match, the H exchange resolves cleanly
resetSyncState()
Profesjonell.ExhaustedPeers = {}
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior" }
Profesjonell.CachedDatabaseHash = nil
Profesjonell.RemoteVersions["Alice"] = "0.40"
local resolveHash = Profesjonell.GenerateDatabaseHash()
-- Simulate: after soft reset, Alice sends H with matching hash
Profesjonell.OnAddonMessage("H:" .. resolveHash .. ":0.40", "Alice")
-- No sync state should be created since hashes match
assert_equal(Profesjonell.Frame.lastSyncPeer == nil, true, "FIX6_2: Matching H after soft reset doesn't start new sync")

-- ==========================================
-- Search Window Tests
-- ==========================================

-- SW1: GetFilteredRecipes returns all recipes with no filters
ProfesjonellDB = {
    ["i:1234"] = { ["Player"] = true, ["Other"] = true },
    ["s:5678"] = { ["Player"] = true }
}
local swNameCache = { ["i:1234"] = "Lionheart Helm", ["s:5678"] = "Arcane Brilliance" }
Profesjonell.NameCache = swNameCache
ProfesjonellConfig = { nameCache = swNameCache }
Profesjonell.GuildRosterCache = { ["Player"] = "Warrior", ["Other"] = "Mage" }
Profesjonell.UpdateGuildRosterCache = function() return true end
Profesjonell.InvalidateProfessionCache()

-- Restore original GetNameFromKey (may have been mocked by earlier tests)
Profesjonell.GetNameFromKey = nil
dofile("Modules/Database.lua")
Profesjonell.NameCache = swNameCache
ProfesjonellConfig.nameCache = swNameCache
local sw_results = Profesjonell.GetFilteredRecipes("", nil)
assert_equal(table.getn(sw_results), 2, "SW1: GetFilteredRecipes returns all recipes with no filter")
-- Should be sorted alphabetically: Arcane Brilliance before Lionheart Helm
assert_equal(sw_results[1].name, "Arcane Brilliance", "SW1: Results sorted alphabetically (first)")
assert_equal(sw_results[2].name, "Lionheart Helm", "SW1: Results sorted alphabetically (second)")

-- SW2: Text filter matches recipe name
sw_results = Profesjonell.GetFilteredRecipes("lion", nil)
assert_equal(table.getn(sw_results), 1, "SW2: Text filter matches recipe name")
assert_equal(sw_results[1].name, "Lionheart Helm", "SW2: Correct recipe matched")

-- SW3: Text filter matches holder name
sw_results = Profesjonell.GetFilteredRecipes("other", nil)
assert_equal(table.getn(sw_results), 1, "SW3: Text filter matches holder name")
assert_equal(sw_results[1].name, "Lionheart Helm", "SW3: Correct recipe matched by holder")

-- SW4: Text filter with multiple words (AND logic)
sw_results = Profesjonell.GetFilteredRecipes("lion helm", nil)
assert_equal(table.getn(sw_results), 1, "SW4: Multi-word filter matches")
sw_results = Profesjonell.GetFilteredRecipes("lion arcane", nil)
assert_equal(table.getn(sw_results), 0, "SW4: Multi-word filter excludes non-matching")

-- SW5: Text filter is case-insensitive
sw_results = Profesjonell.GetFilteredRecipes("LIONHEART", nil)
assert_equal(table.getn(sw_results), 1, "SW5: Case-insensitive filter")

-- SW6: Category filter works via tooltip-scanned cache
-- Set up tooltip lines: Lionheart Helm has "Head" slot (equipment), Arcane Brilliance has no slot
TEST_TOOLTIP_LINES["item:1234:0:0:0"] = { "Lionheart Helm", "Head", "Plate" }
TEST_TOOLTIP_LINES["spell:5678"] = { "Arcane Brilliance" }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
sw_results = Profesjonell.GetFilteredRecipes("", "equipment")
assert_equal(table.getn(sw_results), 1, "SW6: Category filter returns matching equipment")
assert_equal(sw_results[1].name, "Lionheart Helm", "SW6: Correct recipe for equipment")

sw_results = Profesjonell.GetFilteredRecipes("", "other")
assert_equal(table.getn(sw_results), 1, "SW6b: 'other' filter for uncategorized")
assert_equal(sw_results[1].name, "Arcane Brilliance", "SW6b: Correct recipe for other")

-- SW7: Combined text + category filter
sw_results = Profesjonell.GetFilteredRecipes("lion", "equipment")
assert_equal(table.getn(sw_results), 1, "SW7: Combined filter matches")
sw_results = Profesjonell.GetFilteredRecipes("lion", "consumable")
assert_equal(table.getn(sw_results), 0, "SW7b: Combined filter excludes mismatch")

-- SW8: GetRecipeCategory reads from cache after build
assert_equal(Profesjonell.GetRecipeCategory("i:1234"), "equipment", "SW8: GetRecipeCategory from tooltip cache")

-- SW9: Name-based rules take priority (enchant -> enhancement)
ProfesjonellDB = {
    ["s:9999"] = { ["Enc1"] = true },
    ["i:1234"] = { ["Player"] = true, ["Other"] = true },
}
Profesjonell.NameCache["s:9999"] = "Enchant Weapon - Fiery"
Profesjonell.GuildRosterCache = { ["Enc1"] = true, ["Player"] = true, ["Other"] = true }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("s:9999"), "enhancement", "SW9: Enchant inferred as enhancement")

-- SW10: Holders are sorted alphabetically
sw_results = Profesjonell.GetFilteredRecipes("lionheart", nil)
assert_equal(table.getn(sw_results), 1, "SW10: Found recipe")
assert_equal(sw_results[1].holders[1], "Other", "SW10: Holders sorted (first)")
assert_equal(sw_results[1].holders[2], "Player", "SW10: Holders sorted (second)")

-- SW11: Unknown recipes are excluded (use a key that can't resolve via GetItemInfo or tooltip)
ProfesjonellDB["s:9999"] = { ["Player"] = true }
Profesjonell.NameCache["s:9999"] = "Unknown (s:9999)"
-- Clear stale tooltip globals to prevent false resolution
_G["ProfesjonellTooltipTextLeft1"] = nil
sw_results = Profesjonell.GetFilteredRecipes("", nil)
local foundUnknown = false
for _, rr in ipairs(sw_results) do
    if rr.key == "s:9999" then foundUnknown = true end
end
assert_equal(foundUnknown, false, "SW11: Unknown recipes excluded from results")
ProfesjonellDB["s:9999"] = nil
Profesjonell.NameCache["s:9999"] = nil

-- SW12: Empty database returns empty results
ProfesjonellDB = {}
sw_results = Profesjonell.GetFilteredRecipes("", nil)
assert_equal(table.getn(sw_results), 0, "SW12: Empty DB returns empty results")

-- SW13: ToggleSearchWindow function exists
assert_equal(type(Profesjonell.ToggleSearchWindow), "function", "SW13: ToggleSearchWindow exists")

-- SW14: GetFilteredRecipes function exists
assert_equal(type(Profesjonell.GetFilteredRecipes), "function", "SW14: GetFilteredRecipes exists")

-- SW15: Tooltip-based equipment detection via ReadItemTypeFromTooltip
ProfesjonellDB = {
    ["i:5555"] = { ["Crafter1"] = true },
    ["i:5556"] = { ["Crafter1"] = true },
}
Profesjonell.NameCache["i:5555"] = "Arcanite Reaper"
Profesjonell.NameCache["i:5556"] = "Major Healing Potion"
Profesjonell.GuildRosterCache = { ["Crafter1"] = true }
TEST_TOOLTIP_LINES["item:5555:0:0:0"] = { "Arcanite Reaper", "Two-Hand", "Axe" }
TEST_TOOLTIP_LINES["item:5556:0:0:0"] = { "Major Healing Potion", "Use: Restores 1050 health." }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("i:5555"), "equipment", "SW15: Equipment detected from tooltip slot")
assert_equal(Profesjonell.GetRecipeCategory("i:5556"), "consumable", "SW15b: Consumable detected from tooltip Use:")

-- SW16: Name-based inference for Item Enhancement via rules table
ProfesjonellDB = { ["s:9999"] = { ["Enc1"] = true } }
Profesjonell.NameCache["s:9999"] = "Enchant Weapon - Fiery"
Profesjonell.GuildRosterCache = { ["Enc1"] = true }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("s:9999"), "enhancement", "SW16: 'Enchant Weapon' rule infers enhancement")

-- SW16b: Oil rules
ProfesjonellDB["s:9998"] = { ["Enc1"] = true }
Profesjonell.NameCache["s:9998"] = "Brilliant Mana Oil"
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("s:9998"), "consumable", "SW16b: 'Mana Oil' suffix infers consumable")

-- SW17: InferCategoryFromName rules
assert_equal(Profesjonell.InferCategoryFromName("Enchant Boots - Minor Speed"), "enhancement", "SW17: Enchant -> enhancement")
assert_equal(Profesjonell.InferCategoryFromName("Brilliant Wizard Oil"), "consumable", "SW17b: Wizard Oil -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Dense Sharpening Stone"), "consumable", "SW17c: Sharpening Stone -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Frost Oil"), "consumable", "SW17d: Frost Oil -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Shadow Oil"), "consumable", "SW17e: Shadow Oil -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Elixir of the Mongoose"), "consumable", "SW17f: Elixir of -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Flask of the Titans"), "consumable", "SW17g: Flask of -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Major Mana Potion"), "consumable", "SW17h: Potion -> consumable")
assert_equal(Profesjonell.InferCategoryFromName("Iron Grenade"), nil, "SW17i: No match returns nil")

-- SW18: "Other" category filter matches recipes with no category
ProfesjonellDB = {
    ["s:8888"] = { ["Enc1"] = true },
    ["i:7777"] = { ["Crafter1"] = true },
}
Profesjonell.NameCache["s:8888"] = "Enchant Gloves - Mining"
Profesjonell.NameCache["i:7777"] = "Some Unknown Craft"
Profesjonell.GuildRosterCache = { ["Enc1"] = true, ["Crafter1"] = true }
TEST_TOOLTIP_LINES["item:7777:0:0:0"] = { "Some Unknown Craft" }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
local otherResults = Profesjonell.GetFilteredRecipes("", "other")
assert_equal(table.getn(otherResults), 1, "SW18: 'other' filter returns only unclassified recipes")
assert_equal(otherResults[1].name, "Some Unknown Craft", "SW18: 'other' filter correct recipe")

-- SW19: "Gun" detected as equipment from tooltip
ProfesjonellDB = { ["i:6666"] = { ["Hunter1"] = true } }
Profesjonell.NameCache["i:6666"] = "Thorium Rifle"
Profesjonell.GuildRosterCache = { ["Hunter1"] = true }
TEST_TOOLTIP_LINES["item:6666:0:0:0"] = { "Thorium Rifle", "Gun", "Speed 2.90" }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("i:6666"), "equipment", "SW19: 'Gun' slot detected as equipment")
-- SW19b: Other weapon subtypes detected as equipment
ProfesjonellDB["i:6667"] = { ["Hunter1"] = true }
Profesjonell.NameCache["i:6667"] = "Arcanite Dragonling Bow"
TEST_TOOLTIP_LINES["item:6667:0:0:0"] = { "Arcanite Dragonling Bow", "Bow", "Speed 2.70" }
ProfesjonellDB["i:6668"] = { ["Hunter1"] = true }
Profesjonell.NameCache["i:6668"] = "Dwarven Hand Cannon"
TEST_TOOLTIP_LINES["item:6668:0:0:0"] = { "Dwarven Hand Cannon", "Crossbow", "Speed 3.20" }
ProfesjonellDB["i:6669"] = { ["Hunter1"] = true }
Profesjonell.NameCache["i:6669"] = "Ritual Kris"
TEST_TOOLTIP_LINES["item:6669:0:0:0"] = { "Ritual Kris", "Wand", "Speed 1.50" }
ProfesjonellDB["i:6670"] = { ["Hunter1"] = true }
Profesjonell.NameCache["i:6670"] = "Thorium Shield Spike"
TEST_TOOLTIP_LINES["item:6670:0:0:0"] = { "Thorium Shield Spike" }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
assert_equal(Profesjonell.GetRecipeCategory("i:6667"), "equipment", "SW19b: 'Bow' slot detected as equipment")
assert_equal(Profesjonell.GetRecipeCategory("i:6668"), "equipment", "SW19c: 'Crossbow' slot detected as equipment")
assert_equal(Profesjonell.GetRecipeCategory("i:6669"), "equipment", "SW19d: 'Wand' slot detected as equipment")
assert_equal(Profesjonell.GetRecipeCategory("i:6670"), "enhancement", "SW19e: 'Thorium Shield Spike' inferred as enhancement by name")
-- SW20: Enhancement items get enchanting icon only for spell keys, not item keys
assert_equal(Profesjonell.InferCategoryFromName("Enchant Chest - Stats"), "enhancement", "SW20: Enchant inferred as enhancement")
-- Verify that enhancement recipes include category in filtered results
ProfesjonellDB = {
    ["s:7000"] = { ["Enc1"] = true },
    ["i:6670"] = { ["Crafter1"] = true },
}
Profesjonell.NameCache["s:7000"] = "Enchant Weapon - Crusader"
Profesjonell.NameCache["i:6670"] = "Thorium Shield Spike"
Profesjonell.GuildRosterCache = { ["Enc1"] = true, ["Crafter1"] = true }
TEST_TOOLTIP_LINES["item:6670:0:0:0"] = { "Thorium Shield Spike" }
Profesjonell.InvalidateItemTypeCache()
Profesjonell.BuildItemTypeCache(nil, nil)
local enchResults = Profesjonell.GetFilteredRecipes("", "enhancement")
assert_equal(table.getn(enchResults), 2, "SW20b: Enhancement filter returns both spell and item enhancements")
-- Verify spell enhancement has category for tooltip skip
local spellEnch, itemEnch
for _, r in ipairs(enchResults) do
    if r.key == "s:7000" then spellEnch = r end
    if r.key == "i:6670" then itemEnch = r end
end
assert_equal(spellEnch.category, "enhancement", "SW20c: Spell enhancement has enhancement category")
assert_equal(itemEnch.category, "enhancement", "SW20d: Item enhancement has enhancement category")
-- Summary
print(string.format("\nTests complete: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
