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
    
    if isCraft then
        numSkills = GetNumCrafts()
        getSkillInfo = GetCraftInfo
    else
        numSkills = GetNumTradeSkills()
        getSkillInfo = GetTradeSkillInfo
    end

    local playerName = Profesjonell.GetPlayerName()
    local newCount = 0
    for i = 1, numSkills do
        local name, type = getSkillInfo(i)
        if name and type ~= "header" then
            if not ProfesjonellDB[name] then
                ProfesjonellDB[name] = {}
            end
            if not ProfesjonellDB[name][playerName] then
                ProfesjonellDB[name][playerName] = true
                newCount = newCount + 1
                Profesjonell.ShareRecipe(name, playerName)
            end
        end
    end

    if newCount > 0 then
        Profesjonell.Print("Found " .. newCount .. " new recipes!")
        Profesjonell.Frame.broadcastHashTime = GetTime() + 10
    end
end
