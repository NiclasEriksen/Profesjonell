-- Scanner.lua
-- Trade skill and craft scanning
-- Ensure the global table exists
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Scanner.lua loading")
end

function Profesjonell.ScanRecipes(isCraft)
    local numSkills
    local getSkillInfo
    local getLink
    local getRecipeLink
    
    if isCraft then
        numSkills = GetNumCrafts()
        getSkillInfo = GetCraftInfo
        getLink = GetCraftItemLink
        getRecipeLink = GetCraftRecipeLink or function() return nil end
    else
        numSkills = GetNumTradeSkills()
        getSkillInfo = GetTradeSkillInfo
        getLink = GetTradeSkillItemLink
        getRecipeLink = GetTradeSkillRecipeLink or function() return nil end
    end

    local playerName = Profesjonell.GetPlayerName()
    local newCount = 0
    local newKeys = {}
    for i = 1, numSkills do
        local name, type = getSkillInfo(i)
        if name and type ~= "header" then
            -- Prefer recipe link (spell ID) for better searchability (e.g. "Transmute: X")
            -- Fall back to item link if recipe link is not available
            local link = getRecipeLink(i) or getLink(i)
            local id = Profesjonell.GetIDFromLink(link)
            
            if id then
                -- Use ID as primary key
                local key = id
                
                -- Cleanup legacy name-based entry for the player
                if ProfesjonellDB[name] and ProfesjonellDB[name][playerName] then
                    ProfesjonellDB[name][playerName] = nil
                    if not next(ProfesjonellDB[name]) then ProfesjonellDB[name] = nil end
                end
                
                if not ProfesjonellDB[key] then
                    ProfesjonellDB[key] = {}
                end
                if not ProfesjonellDB[key][playerName] then
                    ProfesjonellDB[key][playerName] = true
                    newCount = newCount + 1
                    table.insert(newKeys, key)
                end
            else
                Profesjonell.Debug("Skipping recipe '" .. name .. "' - no ID found. Link: " .. (link or "nil"))
            end
        end
    end

    if newCount > 0 then
        Profesjonell.Print("Found " .. newCount .. " new recipes!")
        Profesjonell.ShareRecipes(playerName, newKeys)
        Profesjonell.Frame.broadcastHashTime = GetTime() + 10
        if Profesjonell.InvalidateTooltipCache then
            Profesjonell.InvalidateTooltipCache()
        end
    end
end
