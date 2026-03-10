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
    "Modules/Scanner.lua",
    "Modules/Comm.lua",
    "Modules/UI.lua"
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
assert_equal(Profesjonell.Frame.pendingR["Player"] == nil, true, "Should not request sync for own character")

-- Test own-hash mismatch push
ProfesjonellDB = {}
ProfesjonellDB["i:1"] = { ["Player"] = true }
Profesjonell.Frame.pendingB = {}
-- Remote peer reports Player has hash "0" (empty)
Profesjonell.OnAddonMessage("C:Player:0", "Other")
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

-- Test ?prof coordination with P message
Profesjonell.PendingReplies = {}
Profesjonell.Frame.pendingP = {}
Profesjonell.OnGuildChat("?prof Lionheart", "Friend")
assert_equal(Profesjonell.PendingReplies["lionheart"] ~= nil, true, "Should schedule reply for ?prof")
assert_equal(Profesjonell.Frame.pendingP["lionheart"] ~= nil, true, "Should schedule P message for ?prof")

-- Simulate receiving P from another player
Profesjonell.OnAddonMessage("P:lionheart", "Other")
assert_equal(Profesjonell.PendingReplies["lionheart"] == nil, true, "Should cancel reply when P received")
assert_equal(Profesjonell.Frame.pendingP["lionheart"] == nil, true, "Should cancel pending P when P received")

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
assert_equal(Profesjonell.Frame.syncTimer, nil, "Sync timer cleared after empty C response from lastSyncPeer")

-- Test Reciprocal Broadcast when C finds no mismatches to pull
Profesjonell.Frame.lastSyncPeer = "TestPeer"
Profesjonell.Frame.lastRemoteHash = "999" -- Mismatching hash
ProfesjonellDB = { ["i:1"] = { ["Player"] = true } }
Profesjonell.Frame.syncTimer = GetTime() + 100
Profesjonell.Frame.broadcastHashTime = nil
Profesjonell.OnAddonMessage("C:", "TestPeer")
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
assert_equal(Profesjonell.Frame.pendingB["Other"] ~= nil, true, "C: handler pushes data for characters remote doesn't mention")

Profesjonell.Frame.lastSyncPeer = nil
Profesjonell.Frame.syncTimer = nil
Profesjonell.Frame.broadcastHashTime = nil

-- Summary
print(string.format("\nTests complete: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
