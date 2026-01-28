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

    if Profesjonell.FlushDebug then
        Profesjonell.FlushDebug()
    end
    if frame.pendingGuildMemberHook and Profesjonell.TryAttachGuildMemberProfessionInfo then
        if Profesjonell.TryAttachGuildMemberProfessionInfo() then
            frame.pendingGuildMemberHook = nil
        end
    end
    if Profesjonell.UpdateGuildMemberProfessionInfo and GuildMemberDetailFrame and GuildMemberDetailFrame:IsShown() then
        if not frame.guildMemberDetailUpdate or now >= frame.guildMemberDetailUpdate then
            Profesjonell.UpdateGuildMemberProfessionInfo()
            frame.guildMemberDetailUpdate = now + 0.5
        end
    end

    if Profesjonell.SyncSummaryTimer and now >= Profesjonell.SyncSummaryTimer then
        local sourceList = {}
        for name, _ in pairs(Profesjonell.SyncSources) do
            table.insert(sourceList, name)
        end
        table.sort(sourceList)
        
        if Profesjonell.SyncNewRecipesCount > 0 then
            Profesjonell.Print("Sync complete: Added " .. Profesjonell.SyncNewRecipesCount .. " new recipes from " .. table.concat(Profesjonell.ColorizeList(sourceList), ", ") .. ".")
            if Profesjonell.ResolveUnknownNames then
                Profesjonell.ResolveUnknownNames(2)
            end
        end
        
        Profesjonell.SyncNewRecipesCount = 0
        Profesjonell.SyncSources = {}
        Profesjonell.SyncSummaryTimer = nil
    end

    if frame.pendingP then
        for queryKey, time in pairs(frame.pendingP) do
            if now >= time then
                Profesjonell.Debug("Sending P coordination for '" .. queryKey .. "'")
                SendAddonMessage(Profesjonell.Name, "P:" .. queryKey, "GUILD")
                frame.pendingP[queryKey] = nil
            end
        end
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
    Profesjonell.WipeDatabaseIfGuildChanged()
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
                local playerOffset = Profesjonell.GetPlayerOffset()
                local delay = 1.0 + playerOffset + math.random() * 2.5
                Profesjonell.PendingReplies[queryKey] = {
                    time = GetTime() + delay,
                    originalQuery = recipe,
                    cleanName = inputCleanName
                }

                -- Schedule a fast addon message to coordinate with other modern clients
                if not Profesjonell.Frame.pendingP then Profesjonell.Frame.pendingP = {} end
                if not Profesjonell.Frame.pendingP[queryKey] then
                    local fastDelay = 0.1 + playerOffset + math.random() * 0.4
                    Profesjonell.Frame.pendingP[queryKey] = GetTime() + fastDelay
                end
            end
        end
    elseif string.find(msg, "^Profesjonell: ") then
        local lowerMsg = string.lower(msg)
        for queryKey, _ in pairs(Profesjonell.PendingReplies) do
            if string.find(lowerMsg, queryKey, 1, true) then
                Profesjonell.PendingReplies[queryKey] = nil
                if Profesjonell.Frame.pendingP and Profesjonell.Frame.pendingP[queryKey] then
                    Profesjonell.Frame.pendingP[queryKey] = nil
                end
            end
        end
    end
end

local function TooltipHasKnownByLine(tooltip)
    if not tooltip or not tooltip.GetName or not tooltip.NumLines then return false end
    local tooltipName = tooltip:GetName()
    local numLines = tooltip:NumLines() or 0
    for i = 1, numLines do
        local textObj = _G[tooltipName .. "TextLeft" .. i]
        local text = textObj and textObj:GetText()
        if text and string.find(text, "^Known by") then
            return true
        end
    end
    return false
end

local function FindKnownByLineIndex(tooltip)
    if not tooltip or not tooltip.GetName then return nil end
    local tooltipName = tooltip:GetName()
    for i = 1, 30 do
        local textObj = _G[tooltipName .. "TextLeft" .. i]
        local text = textObj and textObj:GetText()
        if text and string.find(text, "^Known by") then
            return i
        end
    end
    return nil
end

local function ClearKnownByLines(tooltip)
    if not tooltip or not tooltip.GetName then return end
    local tooltipName = tooltip:GetName()
    for i = 1, 30 do
        local textObj = _G[tooltipName .. "TextLeft" .. i]
        local text = textObj and textObj:GetText()
        if text and string.find(text, "^Known by") then
            if textObj.SetText then
                textObj:SetText("")
            end
        end
    end
end

function Profesjonell.GetTooltipLink(tooltip)
    if not tooltip then return nil end
    return tooltip._profHyperlink
end

function Profesjonell.AddKnownByToTooltip(tooltip)
    if not tooltip or not Profesjonell.ResolveRecipeKeysFromLink then return end
    ClearKnownByLines(tooltip)
    local existingIndex = FindKnownByLineIndex(tooltip)

    local link = Profesjonell.GetTooltipLink(tooltip)
    if not link then
        local keys = Profesjonell.ResolveRecipeKeysFromTooltip and Profesjonell.ResolveRecipeKeysFromTooltip(tooltip)
        if not keys then return end
        local line = Profesjonell.BuildKnownByLine and Profesjonell.BuildKnownByLine(keys)
        if line then
            if existingIndex then
                local tooltipName = tooltip:GetName()
                local textObj = tooltipName and _G[tooltipName .. "TextLeft" .. existingIndex]
                if textObj and textObj.SetText then
                    textObj:SetText(line)
                else
                    tooltip:AddLine(line)
                end
            else
                tooltip:AddLine(line)
            end
            if tooltip.Show then tooltip:Show() end
        elseif existingIndex then
            local tooltipName = tooltip:GetName()
            local textObj = tooltipName and _G[tooltipName .. "TextLeft" .. existingIndex]
            if textObj and textObj.SetText then
                textObj:SetText("")
            end
            if tooltip.Show then tooltip:Show() end
        end
        return
    end

    local keys = Profesjonell.ResolveRecipeKeysFromLink(link)
    if not keys then
        if existingIndex then
            local tooltipName = tooltip:GetName()
            local textObj = tooltipName and _G[tooltipName .. "TextLeft" .. existingIndex]
            if textObj and textObj.SetText then
                textObj:SetText("")
            end
            if tooltip.Show then tooltip:Show() end
        end
        return
    end

    local line = Profesjonell.BuildKnownByLine and Profesjonell.BuildKnownByLine(keys)
    if line then
        if existingIndex then
            local tooltipName = tooltip:GetName()
            local textObj = tooltipName and _G[tooltipName .. "TextLeft" .. existingIndex]
            if textObj and textObj.SetText then
                textObj:SetText(line)
            else
                tooltip:AddLine(line)
            end
        else
            tooltip:AddLine(line)
        end
        if tooltip.Show then tooltip:Show() end
    elseif existingIndex then
        local tooltipName = tooltip:GetName()
        local textObj = tooltipName and _G[tooltipName .. "TextLeft" .. existingIndex]
        if textObj and textObj.SetText then
            textObj:SetText("")
        end
        if tooltip.Show then tooltip:Show() end
    end
end

function Profesjonell.AttachTooltipHooks()
    if Profesjonell.TooltipHooksAttached then return end
    local function HookTooltip(tt)
        if not tt then return end
        if tt.GetScript and tt.SetScript then
            local oldOnHide = tt:GetScript("OnHide")
            tt:SetScript("OnHide", function()
                if oldOnHide then oldOnHide(tt) end
                tt._profHyperlink = nil
                ClearKnownByLines(tt)
            end)
        end

        local oldSetHyperlink = tt.SetHyperlink
        if oldSetHyperlink then
            tt.SetHyperlink = function(self, link)
                self._profHyperlink = link
                local r1, r2, r3, r4, r5 = oldSetHyperlink(self, link)
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetSpell = tt.SetSpell
        if oldSetSpell then
            tt.SetSpell = function(self, spell, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
                local r1, r2, r3, r4, r5 = oldSetSpell(self, spell, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetSpellBookItem = tt.SetSpellBookItem
        if oldSetSpellBookItem then
            tt.SetSpellBookItem = function(self, slot, bookType, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetSpellBookItem(self, slot, bookType, a1, a2, a3, a4)
                self._profHyperlink = nil
                if GetSpellLink then
                    local link = GetSpellLink(slot, bookType)
                    if link then
                        self._profHyperlink = link
                    end
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetSpellBookItemByID = tt.SetSpellBookItemByID
        if oldSetSpellBookItemByID then
            tt.SetSpellBookItemByID = function(self, spellId, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetSpellBookItemByID(self, spellId, a1, a2, a3, a4)
                self._profHyperlink = nil
                if spellId then
                    self._profHyperlink = "spell:" .. spellId
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetBagItem = tt.SetBagItem
        if oldSetBagItem then
            tt.SetBagItem = function(self, bag, slot, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetBagItem(self, bag, slot, a1, a2, a3, a4)
                if GetContainerItemLink then
                    self._profHyperlink = GetContainerItemLink(bag, slot)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetInventoryItem = tt.SetInventoryItem
        if oldSetInventoryItem then
            tt.SetInventoryItem = function(self, unit, slot, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetInventoryItem(self, unit, slot, a1, a2, a3, a4)
                if GetInventoryItemLink then
                    self._profHyperlink = GetInventoryItemLink(unit, slot)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetTradeSkillItem = tt.SetTradeSkillItem
        if oldSetTradeSkillItem then
            tt.SetTradeSkillItem = function(self, skillIndex, reagentIndex, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetTradeSkillItem(self, skillIndex, reagentIndex, a1, a2, a3, a4)
                if reagentIndex and GetTradeSkillReagentItemLink then
                    self._profHyperlink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
                elseif GetTradeSkillItemLink then
                    self._profHyperlink = GetTradeSkillItemLink(skillIndex)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetTradeSkillReagentItem = tt.SetTradeSkillReagentItem
        if oldSetTradeSkillReagentItem then
            tt.SetTradeSkillReagentItem = function(self, skillIndex, reagentIndex, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetTradeSkillReagentItem(self, skillIndex, reagentIndex, a1, a2, a3, a4)
                if GetTradeSkillReagentItemLink then
                    self._profHyperlink = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetCraftItem = tt.SetCraftItem
        if oldSetCraftItem then
            tt.SetCraftItem = function(self, index, reagentIndex, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetCraftItem(self, index, reagentIndex, a1, a2, a3, a4)
                if reagentIndex and GetCraftReagentItemLink then
                    self._profHyperlink = GetCraftReagentItemLink(index, reagentIndex)
                elseif GetCraftItemLink then
                    self._profHyperlink = GetCraftItemLink(index)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end

        local oldSetCraftSpell = tt.SetCraftSpell
        if oldSetCraftSpell then
            tt.SetCraftSpell = function(self, index, a1, a2, a3, a4)
                local r1, r2, r3, r4, r5 = oldSetCraftSpell(self, index, a1, a2, a3, a4)
                if GetCraftRecipeLink then
                    self._profHyperlink = GetCraftRecipeLink(index)
                end
                Profesjonell.AddKnownByToTooltip(self)
                return r1, r2, r3, r4, r5
            end
        end
    end

    HookTooltip(GameTooltip)
    if SpellTooltip then
        HookTooltip(SpellTooltip)
    end
    HookTooltip(ItemRefTooltip)
    if AtlasLootTooltip then
        HookTooltip(AtlasLootTooltip)
    end
    if AtlasLootTooltip2 then
        HookTooltip(AtlasLootTooltip2)
    end
    Profesjonell.TooltipHooksAttached = true
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
                    if Profesjonell.InvalidateTooltipCache then
                        Profesjonell.InvalidateTooltipCache()
                    end
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
                    if Profesjonell.InvalidateTooltipCache then
                        Profesjonell.InvalidateTooltipCache()
                    end
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
                        if Profesjonell.InvalidateTooltipCache then
                            Profesjonell.InvalidateTooltipCache()
                        end
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
