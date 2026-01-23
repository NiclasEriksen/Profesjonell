-- Core.lua
-- Main initialization and event loop
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.GetAddOnMetadata then
    Profesjonell.Version = Profesjonell.GetAddOnMetadata("Profesjonell", "Version") or "0.30"
end

if Profesjonell.Log then
    Profesjonell.Log("Core.lua loading")
end

local frame = CreateFrame("Frame")
Profesjonell.Frame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("CRAFT_SHOW")
frame:RegisterEvent("CRAFT_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")

frame:SetScript("OnEvent", function()
    -- In WoW 1.12, event, arg1, arg2, etc. are global variables during the execution of OnEvent
    local event = event
    local arg1 = arg1
    local arg2 = arg2
    local arg4 = arg4

    if event == "ADDON_LOADED" and arg1 == "Profesjonell" then
        if not ProfesjonellDB then ProfesjonellDB = {} end
        if not ProfesjonellConfig then ProfesjonellConfig = {} end
        Profesjonell.Print(Profesjonell.Version .. " loaded.")

        -- Migration check
        if not ProfesjonellConfig.version or ProfesjonellConfig.version < "0.27" then
            if Profesjonell.MigrateDatabase then
                Profesjonell.MigrateDatabase()
            end
            ProfesjonellConfig.version = "0.30"
        end

        if Profesjonell.WipeDatabaseIfGuildChanged then
            Profesjonell.WipeDatabaseIfGuildChanged()
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        if Profesjonell.ScanRecipes then
            Profesjonell.ScanRecipes(false)
        end
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        if Profesjonell.ScanRecipes then
            Profesjonell.ScanRecipes(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if Profesjonell.OnPlayerEnteringWorld then
            Profesjonell.OnPlayerEnteringWorld()
        end
    elseif event == "CHAT_MSG_GUILD" then
        if Profesjonell.OnGuildChat then
            Profesjonell.OnGuildChat(arg1, arg2)
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        if Profesjonell.WipeDatabaseIfGuildChanged then
            Profesjonell.WipeDatabaseIfGuildChanged()
        end
    elseif event == "CHAT_MSG_ADDON" and arg1 == "Profesjonell" then
        if Profesjonell.OnAddonMessage then
            Profesjonell.OnAddonMessage(arg2, arg4)
        end
    end
end)

frame:SetScript("OnUpdate", function()
    if Profesjonell.OnUpdate then
        Profesjonell.OnUpdate()
    end
end)
