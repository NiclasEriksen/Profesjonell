-- Init.lua
-- Global table initialization for WoW 1.12.1

-- Ensure the global table exists immediately
if not Profesjonell then
    Profesjonell = {}
end

-- Core properties
Profesjonell.Name = "Profesjonell"
Profesjonell.Version = "0.32"

-- Ensure sub-tables exist
Profesjonell.PendingReplies = Profesjonell.PendingReplies or {}
Profesjonell.SyncSources = Profesjonell.SyncSources or {}
Profesjonell.GuildRosterCache = Profesjonell.GuildRosterCache or {}
Profesjonell.RecipesToShare = Profesjonell.RecipesToShare or {}

-- Safe Print function
function Profesjonell.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Profesjonell:|r " .. (msg or "nil"))
    end
end

-- Safe Debug function
function Profesjonell.Debug(msg)
    if ProfesjonellConfig and ProfesjonellConfig.debug and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaProfesjonell Debug:|r " .. (msg or "nil"))
    end
end

-- Fallback for GetAddOnMetadata (1.12 standard)
function Profesjonell.GetAddOnMetadata(addon, field)
    if GetAddOnMetadata then
        return GetAddOnMetadata(addon, field)
    end
    return nil
end

-- Loading logger
function Profesjonell.Log(msg)
    Profesjonell.Debug("Load: " .. (msg or "nil"))
end

Profesjonell.Log("Init.lua loaded")
