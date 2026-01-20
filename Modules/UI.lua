-- UI.lua
-- Slash commands and chat handlers
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("UI.lua loading")
end

function Profesjonell.OnUpdate()
    local now = GetTime()
    local frame = Profesjonell.Frame

    if frame.broadcastHashTime and now >= frame.broadcastHashTime then
        Profesjonell.BroadcastHash()
        frame.broadcastHashTime = nil
    end

    if frame.syncTimer and now >= frame.syncTimer then
        Profesjonell.RequestSync()
        frame.syncTimer = nil
    end

    if frame.pendingShare and now >= frame.pendingShare then
        Profesjonell.ShareAllRecipes(true)
        frame.pendingShare = nil
    end

    if Profesjonell.SyncSummaryTimer and now >= Profesjonell.SyncSummaryTimer then
        local sourceList = {}
        for name, _ in pairs(Profesjonell.SyncSources) do
            table.insert(sourceList, name)
        end
        table.sort(sourceList)
        
        if Profesjonell.SyncNewRecipesCount > 0 then
            Profesjonell.Print("Sync complete: Added " .. Profesjonell.SyncNewRecipesCount .. " new recipes from " .. table.concat(Profesjonell.ColorizeList(sourceList), ", ") .. ".")
        end
        
        Profesjonell.SyncNewRecipesCount = 0
        Profesjonell.SyncSources = {}
        Profesjonell.SyncSummaryTimer = nil
    end

    for queryKey, data in pairs(Profesjonell.PendingReplies) do
        if now >= data.time then
            local found, cleanName, partialMatches, exactMatchLink, partialLinks = Profesjonell.FindRecipeHolders(data.originalQuery)
            local replyMsg
            local matchCount = 0
            if table.getn(found) > 0 then
                matchCount = 1
            end
            for _ in pairs(partialMatches) do
                matchCount = matchCount + 1
            end

            if matchCount > 1 then
                replyMsg = "Profesjonell: Multiple matches found for '" .. data.cleanName .. "'. Please be more specific."
            elseif matchCount == 1 then
                if table.getn(found) > 0 then
                    replyMsg = "Profesjonell: " .. (exactMatchLink or cleanName) .. " is known by: " .. table.concat(Profesjonell.ColorizeList(found), ", ")
                else
                    local pName, pHolders, pLink
                    for name, holders in pairs(partialMatches) do
                        pName = name
                        pHolders = holders
                        pLink = partialLinks[name]
                    end
                    table.sort(pHolders)
                    replyMsg = "Profesjonell: " .. (pLink or pName) .. " is known by: " .. table.concat(Profesjonell.ColorizeList(pHolders), ", ")
                end
            else
                replyMsg = "Profesjonell: No one knows " .. data.cleanName
            end
            SendChatMessage(replyMsg, "GUILD")
            Profesjonell.Debug("Sent reply: " .. replyMsg)
            Profesjonell.PendingReplies[queryKey] = nil
        end
    end
end

function Profesjonell.OnPlayerEnteringWorld()
    Profesjonell.Frame.enteredWorldTime = GetTime()
    Profesjonell.WipeDatabaseIfNoGuild()
    local now = GetTime()
    if not Profesjonell.LastSyncRequest or (now - Profesjonell.LastSyncRequest > 30) then
        Profesjonell.Frame.broadcastHashTime = now + 10
        Profesjonell.LastSyncRequest = now
    end
end

function Profesjonell.OnGuildChat(msg, sender)
    if string.find(msg, "^%?prof ") then
        local recipe = string.sub(msg, 7)
        if recipe and recipe ~= "" then
            Profesjonell.Debug("Query detected from " .. sender .. ": " .. recipe)
            
            -- Use the input name as queryKey to ensure consistency between clients,
            -- regardless of local database state or tooltip loading status.
            local inputCleanName = Profesjonell.GetItemNameFromLink(recipe)
            inputCleanName = Profesjonell.StripPrefix(inputCleanName)
            local queryKey = string.lower(inputCleanName)
            
            if not Profesjonell.PendingReplies[queryKey] then
                local playerName = Profesjonell.GetPlayerName()
                local playerOffset = 0
                if playerName then
                    for i=1, string.len(playerName) do
                        playerOffset = math.mod(playerOffset + string.byte(playerName, i), 50)
                    end
                    playerOffset = playerOffset / 100
                end
            
                local delay = 1.0 + playerOffset + math.random() * 2.5
                Profesjonell.PendingReplies[queryKey] = {
                    time = GetTime() + delay,
                    originalQuery = recipe,
                    cleanName = inputCleanName
                }
            end
        end
    elseif string.find(msg, "^Profesjonell: ") then
        local lowerMsg = string.lower(msg)
        for queryKey, _ in pairs(Profesjonell.PendingReplies) do
            if string.find(lowerMsg, queryKey, 1, true) then
                Profesjonell.PendingReplies[queryKey] = nil
            end
        end
    end
end

-- Slash Command
SLASH_PROFESJONELL1 = "/prof"
SLASH_PROFESJONELL2 = "/profesjonell"
SlashCmdList["PROFESJONELL"] = function(msg)
    if msg == "debug" then
        ProfesjonellConfig.debug = not ProfesjonellConfig.debug
        Profesjonell.Print("Debug mode: " .. (ProfesjonellConfig.debug and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
        return
    end

    if msg == "sync" then
        local now = GetTime()
        if not Profesjonell.LastSyncRequest or (now - Profesjonell.LastSyncRequest > 30) then
            Profesjonell.Print("Requesting manual sync from guild...")
            Profesjonell.RequestSync()
            Profesjonell.LastSyncRequest = now
        else
            local wait = math.ceil(30 - (now - Profesjonell.LastSyncRequest))
            Profesjonell.Print("Please wait " .. wait .. "s before syncing again.")
        end
        return
    end

    if msg == "share" then
        Profesjonell.Print("Sharing your database with the guild...")
        Profesjonell.ShareAllRecipes(true)
        return
    end

    if string.find(msg, "^add ") then
        if Profesjonell.IsOfficer(Profesjonell.GetPlayerName()) then
            local _, _, charName, recipeLink = string.find(msg, "^add ([^%s]+) (.+)$")
            if charName and recipeLink then
                local id = Profesjonell.GetIDFromLink(recipeLink)
                if not id then
                    Profesjonell.Print("Error: Could not extract item/spell ID from link. Only links are supported for adding recipes.")
                    return
                end

                local cleanRecipeName = Profesjonell.GetItemNameFromLink(recipeLink)
                local key = id
                
                if not ProfesjonellDB[key] then ProfesjonellDB[key] = {} end

                if not ProfesjonellDB[key][charName] then
                    ProfesjonellDB[key][charName] = true
                    Profesjonell.Print("Added " .. (cleanRecipeName or key) .. " to " .. Profesjonell.ColorizeName(charName) .. " and broadcasting.")
                    Profesjonell.ShareRecipes(charName, {key})
                    if Profesjonell.GetGuildName() then
                        SendChatMessage("Profesjonell: Added " .. (cleanRecipeName or key) .. " to " .. charName, "GUILD")
                    end
                else
                    Profesjonell.Print(Profesjonell.ColorizeName(charName) .. " already has " .. (cleanRecipeName or key) .. " in the database.")
                end
            else
                Profesjonell.Print("Usage: /prof add [name] [recipe]")
            end
        else
            Profesjonell.Print("Only officers can add recipes.")
        end
        return
    end

    if string.find(msg, "^remove ") then
        if Profesjonell.IsOfficer(Profesjonell.GetPlayerName()) then
            local _, _, charName, recipeLink = string.find(msg, "^remove ([^%s]+) (.+)$")
            if charName and recipeLink then
                local id = Profesjonell.GetIDFromLink(recipeLink)
                if not id then
                    Profesjonell.Print("Error: Could not extract item/spell ID from link. Only links are supported for removing specific recipes.")
                    return
                end

                local cleanRecipeName = Profesjonell.GetItemNameFromLink(recipeLink)
                local key = id
                
                if ProfesjonellDB[key] and ProfesjonellDB[key][charName] then
                    ProfesjonellDB[key][charName] = nil
                    if not next(ProfesjonellDB[key]) then ProfesjonellDB[key] = nil end
                    Profesjonell.Print("Removed " .. (cleanRecipeName or key) .. " from " .. Profesjonell.ColorizeName(charName) .. " and broadcasting.")
                    SendAddonMessage(Profesjonell.Name, "REMOVE_RECIPE:" .. charName .. ":" .. key, "GUILD")
                    if Profesjonell.GetGuildName() then
                        SendChatMessage("Profesjonell: Removed " .. (cleanRecipeName or key) .. " from " .. charName, "GUILD")
                    end
                else
                    Profesjonell.Print(Profesjonell.ColorizeName(charName) .. " does not have " .. (cleanRecipeName or key) .. " in the database.")
                end
            else
                local charNameOnly = string.sub(msg, 8)
                if charNameOnly and charNameOnly ~= "" then
                    local removedCount = 0
                    for rName, holders in pairs(ProfesjonellDB) do
                        if holders[charNameOnly] then
                            holders[charNameOnly] = nil
                            removedCount = removedCount + 1
                            if not next(holders) then ProfesjonellDB[rName] = nil end
                        end
                    end
                    if removedCount > 0 then
                        Profesjonell.Print("Removed " .. Profesjonell.ColorizeName(charNameOnly) .. " from local database and broadcasting.")
                        SendAddonMessage(Profesjonell.Name, "REMOVE_CHAR:" .. charNameOnly, "GUILD")
                    else
                        Profesjonell.Print("Character " .. Profesjonell.ColorizeName(charNameOnly) .. " not found.")
                    end
                else
                    Profesjonell.Print("Usage: /prof remove [name] [recipe] or /prof remove [name]")
                end
            end
        else
            Profesjonell.Print("Only officers can remove recipes.")
        end
        return
    end

    if msg == "purge" then
        if Profesjonell.IsOfficer(Profesjonell.GetPlayerName()) then
            if not Profesjonell.UpdateGuildRosterCache() then
                Profesjonell.Print("Guild roster is not yet loaded.")
                return
            end
            local charsToPurge = {}
            local charPresence = {}
            for _, holders in pairs(ProfesjonellDB) do
                for charName, _ in pairs(holders) do
                    charPresence[charName] = true
                end
            end
            for charName, _ in pairs(charPresence) do
                if not Profesjonell.GuildRosterCache[charName] then
                    table.insert(charsToPurge, charName)
                end
            end
            
            local count = table.getn(charsToPurge)
            if count == 0 then
                Profesjonell.Print("No members to purge.")
                return
            end

            local index = 1
            local purgeTimer = CreateFrame("Frame")
            purgeTimer:SetScript("OnUpdate", function()
                local chunkCount = 0
                while index <= count and chunkCount < 5 do
                    local charName = charsToPurge[index]
                    for recipeName, holders in pairs(ProfesjonellDB) do
                        if holders[charName] then
                            holders[charName] = nil
                            if not next(holders) then ProfesjonellDB[recipeName] = nil end
                        end
                    end
                    SendAddonMessage(Profesjonell.Name, "REMOVE_CHAR:" .. charName, "GUILD")
                    index = index + 1
                    chunkCount = chunkCount + 1
                end
                if index > count then
                    purgeTimer:SetScript("OnUpdate", nil)
                    purgeTimer:Hide()
                    Profesjonell.BroadcastHash()
                    Profesjonell.Print("Purged " .. count .. " members.")
                end
            end)
        else
            Profesjonell.Print("Only officers can purge.")
        end
        return
    end

    if msg and msg ~= "" and msg ~= "help" then
        local found, cleanName, partialMatches, exactMatchLink, partialLinks = Profesjonell.FindRecipeHolders(msg)
        if table.getn(found) > 0 then
            Profesjonell.Print((exactMatchLink or cleanName) .. " is known by: " .. table.concat(Profesjonell.ColorizeList(found), ", "))
        else
            local matchCount = 0
            for _ in pairs(partialMatches) do matchCount = matchCount + 1 end
            
            if matchCount == 1 then
                local pName, pHolders = next(partialMatches)
                local pLink = partialLinks[pName]
                table.sort(pHolders)
                Profesjonell.Print((pLink or pName) .. " is known by: " .. table.concat(Profesjonell.ColorizeList(pHolders), ", "))
            elseif matchCount > 1 then
                Profesjonell.Print("Multiple matches found for '" .. msg .. "':")
                local sortedNames = {}
                for pName in pairs(partialMatches) do table.insert(sortedNames, pName) end
                table.sort(sortedNames)
                for _, pName in ipairs(sortedNames) do
                    local pHolders = partialMatches[pName]
                    local pLink = partialLinks[pName]
                    table.sort(pHolders)
                    Profesjonell.Print("  " .. (pLink or pName) .. " is known by: " .. table.concat(Profesjonell.ColorizeList(pHolders), ", "))
                end
            else
                Profesjonell.Print("No one knows " .. msg)
            end
        end
        return
    end

    Profesjonell.Print("Commands:")
    Profesjonell.Print("/prof [recipe] - Search for a recipe holder.")
    Profesjonell.Print("/prof sync - Synchronize database with guild.")
    Profesjonell.Print("/prof share - Share your recipes with the guild.")
    Profesjonell.Print("/prof debug - Toggle debug messages.")
    Profesjonell.Print("/prof add [name] [recipe] - Add recipe to character (Officer only).")
    Profesjonell.Print("/prof remove [name] [recipe] - Remove recipe from character (Officer only).")
    Profesjonell.Print("/prof purge - Clean up database (Officer only).")
end
