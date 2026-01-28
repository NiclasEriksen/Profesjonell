-- Professions.lua
-- Guild member profession inference from recipe signatures
Profesjonell = Profesjonell or {}

if Profesjonell.Log then
    Profesjonell.Log("Professions.lua loading")
end

Profesjonell.ProfessionSignatures = Profesjonell.ProfessionSignatures or {
    enchanting = {"s:7421", "s:7795"},
    tailoring = {"i:2996", "i:2997"},
    jewelcrafting = {"i:55150", "i:81032"},
    blacksmithing = {"i:2862", "i:3239"},
    leatherworking = {"i:2318", "i:2304"},
    alchemy = {"i:118", "i:2455"}
}
Profesjonell.ProfessionSignatureMinMatches = Profesjonell.ProfessionSignatureMinMatches or 2

Profesjonell.ProfessionDetectEpoch = Profesjonell.ProfessionDetectEpoch or 0
Profesjonell.ProfessionDetectCache = Profesjonell.ProfessionDetectCache or {}
Profesjonell.SignatureIndex = Profesjonell.SignatureIndex or nil
Profesjonell.SignatureIndexEpoch = Profesjonell.SignatureIndexEpoch or nil

local professionLabels = {
    enchanting = "Enchanting",
    tailoring = "Tailoring",
    jewelcrafting = "Jewelcrafting",
    blacksmithing = "Blacksmithing",
    leatherworking = "Leatherworking",
    alchemy = "Alchemy"
}

local allowedProfessions = {
    enchanting = true,
    tailoring = true,
    jewelcrafting = true,
    blacksmithing = true,
    leatherworking = true,
    alchemy = true
}

local function NormalizeSignatureKey(value)
    if value == nil then return nil end
    if type(value) == "number" then
        value = tostring(value)
    end
    if type(value) ~= "string" then return nil end

    return Profesjonell.GetIDFromLink and Profesjonell.GetIDFromLink(value) or value
end

function Profesjonell.InvalidateProfessionCache()
    Profesjonell.ProfessionDetectEpoch = (Profesjonell.ProfessionDetectEpoch or 0) + 1
    Profesjonell.ProfessionDetectCache = {}
    Profesjonell.SignatureIndex = nil
    Profesjonell.SignatureIndexEpoch = nil
end

function Profesjonell.GetSignatureIndex()
    if Profesjonell.SignatureIndex and Profesjonell.SignatureIndexEpoch == Profesjonell.ProfessionDetectEpoch then
        return Profesjonell.SignatureIndex
    end

    local signatures = Profesjonell.ProfessionSignatures or {}
    local index = {}
    for profession, list in pairs(signatures) do
        if allowedProfessions[profession] and type(list) == "table" then
            for listKey, value in pairs(list) do
                local candidate = value
                if value == true and type(listKey) ~= "number" then
                    candidate = listKey
                end
                local key = NormalizeSignatureKey(candidate)
                if key and key ~= "" then
                    if not index[key] then index[key] = {} end
                    index[key][profession] = true
                end
            end
        end
    end

    Profesjonell.SignatureIndex = index
    Profesjonell.SignatureIndexEpoch = Profesjonell.ProfessionDetectEpoch
    return index
end

function Profesjonell.DetectCraftProfessionsForChar(charName)
    if not charName or not ProfesjonellDB then return nil end

    local cache = Profesjonell.ProfessionDetectCache
    if cache and cache.epoch == Profesjonell.ProfessionDetectEpoch and cache[charName] ~= nil then
        if cache[charName] == false then return nil end
        return cache[charName]
    end

    local minMatches = Profesjonell.ProfessionSignatureMinMatches or 2
    if minMatches < 1 then minMatches = 1 end

    local signatureIndex = Profesjonell.GetSignatureIndex()
    local matchCounts = {}
    local detected = {}
    local hasAnyRecipe = false

    for recipeKey, holders in pairs(ProfesjonellDB) do
        if holders and holders[charName] then
            hasAnyRecipe = true
            local profs = signatureIndex[recipeKey]
            if profs then
                for profession in pairs(profs) do
                    matchCounts[profession] = (matchCounts[profession] or 0) + 1
                end
            end
        end
    end

    if not hasAnyRecipe then
        if not cache then cache = {} end
        cache.epoch = Profesjonell.ProfessionDetectEpoch
        cache[charName] = false
        Profesjonell.ProfessionDetectCache = cache
        return nil
    end

    for profession, count in pairs(matchCounts) do
        if count >= minMatches then
            detected[profession] = true
        end
    end

    local list = {}
    for profession in pairs(detected) do
        table.insert(list, profession)
    end
    table.sort(list)

    local result = nil
    if table.getn(list) > 0 then
        result = list
    end

    if not cache then cache = {} end
    cache.epoch = Profesjonell.ProfessionDetectEpoch
    cache[charName] = result or false
    Profesjonell.ProfessionDetectCache = cache

    return result
end

function Profesjonell.GetGuildMemberProfessionText(charName)
    local list = Profesjonell.DetectCraftProfessionsForChar(charName)
    if not list then return nil end

    local useAbbrev = table.getn(list) > 1
    local abbrev = {
        enchanting = "ENCH",
        tailoring = "TAIL",
        jewelcrafting = "JC",
        blacksmithing = "BS",
        leatherworking = "LW",
        alchemy = "ALCH"
    }
    local labels = {}
    for _, profession in ipairs(list) do
        if useAbbrev then
            table.insert(labels, abbrev[profession] or professionLabels[profession] or profession)
        else
            table.insert(labels, professionLabels[profession] or profession)
        end
    end
    return table.concat(labels, " / ")
end

local function CleanName(name)
    if not name then return nil end
    name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")
    name = string.gsub(name, "%s*%b()", "")
    name = string.gsub(name, "%s+$", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%-.*$", "")
    if name == "" then return nil end
    return name
end

local function GetSelectedGuildMemberIndex()
    if GetGuildRosterSelection then
        local idx = GetGuildRosterSelection()
        if idx and idx > 0 then return idx end
    end
    if GuildFrame then
        local idx = GuildFrame.selectedGuildMember or GuildFrame.selectedMember or GuildFrame.selectedIndex
        if idx and idx > 0 then return idx end
    end
    return nil
end

local function GetSelectedGuildMemberName()
    local index = GetSelectedGuildMemberIndex()
    if index then
        local name = CleanName(GetGuildRosterInfo(index))
        if name then return name end
    end

    local nameText = _G["GuildMemberDetailName"]
    if nameText and nameText.GetText then
        local name = CleanName(nameText:GetText())
        if name then return name end
    end

    return nil
end

function Profesjonell.EnsureGuildMemberProfessionLine()
    if not GuildMemberDetailFrame or _G["GuildMemberDetailProfessionLabel"] then return end

    local parent = GuildMemberDetailFrame
    local label = parent:CreateFontString("GuildMemberDetailProfessionLabel", "ARTWORK", "GameFontNormalSmall")
    local value = parent:CreateFontString("GuildMemberDetailProfessionText", "ARTWORK", "GameFontHighlightSmall")

    label:SetText("Profession:")

    local rankLabel = _G["GuildMemberDetailRankLabel"] or _G["GuildMemberDetailRank"]
    local rankText = _G["GuildMemberDetailRankText"] or _G["GuildMemberDetailRank"]
    local onlineLabel = _G["GuildMemberDetailOnlineLabel"] or _G["GuildMemberDetailOnline"]
    local onlineText = _G["GuildMemberDetailOnlineText"] or _G["GuildMemberDetailOnlineTextValue"]

    local anchor = rankLabel or rankText or parent
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    value:SetPoint("LEFT", label, "RIGHT", 4, 0)

    label:Hide()
    value:Hide()
end

local function StoreOriginalPoint(frame)
    if not frame or not frame.GetPoint then return end
    if frame._profOrigPoint then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    frame._profOrigPoint = {point, relativeTo, relativePoint, x, y}
end

local function RestoreOriginalPoint(frame)
    if not frame or not frame._profOrigPoint then return end
    frame:ClearAllPoints()
    frame:SetPoint(frame._profOrigPoint[1], frame._profOrigPoint[2], frame._profOrigPoint[3], frame._profOrigPoint[4], frame._profOrigPoint[5])
end

function Profesjonell.UpdateGuildMemberProfessionInfo()
    if not GuildMemberDetailFrame or not GuildMemberDetailFrame:IsShown() then return end
    Profesjonell.EnsureGuildMemberProfessionLine()

    local label = _G["GuildMemberDetailProfessionLabel"]
    local value = _G["GuildMemberDetailProfessionText"]
    local onlineLabel = _G["GuildMemberDetailOnlineLabel"] or _G["GuildMemberDetailOnline"]
    local onlineText = _G["GuildMemberDetailOnlineText"] or _G["GuildMemberDetailOnlineTextValue"]
    if not label or not value then return end

    local name = GetSelectedGuildMemberName()
    if not name then
        label:Hide()
        value:Hide()
        RestoreOriginalPoint(onlineLabel)
        RestoreOriginalPoint(onlineText)
        return
    end

    local text = Profesjonell.GetGuildMemberProfessionText(name)
    if text then
        label:Show()
        value:SetText(text)
        value:Show()
        StoreOriginalPoint(onlineLabel)
        StoreOriginalPoint(onlineText)
        if onlineLabel and onlineLabel.GetPoint then
            onlineLabel:ClearAllPoints()
            onlineLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        end
        if onlineText and onlineText.GetPoint then
            onlineText:ClearAllPoints()
            if onlineLabel then
                onlineText:SetPoint("LEFT", onlineLabel, "RIGHT", 4, 0)
            else
                onlineText:SetPoint("LEFT", label, "RIGHT", 4, 0)
            end
        end
    else
        label:Hide()
        value:Hide()
        RestoreOriginalPoint(onlineLabel)
        RestoreOriginalPoint(onlineText)
    end
end

function Profesjonell.TryAttachGuildMemberProfessionInfo()
    if Profesjonell.GuildMemberProfessionAttached then return true end
    if not GuildMemberDetailFrame then return false end

    Profesjonell.EnsureGuildMemberProfessionLine()

    local oldOnShow = GuildMemberDetailFrame:GetScript("OnShow")
    GuildMemberDetailFrame:SetScript("OnShow", function()
        if oldOnShow then oldOnShow() end
        Profesjonell.UpdateGuildMemberProfessionInfo()
    end)

    if GuildMemberDetailFrame_Update then
        local oldUpdate = GuildMemberDetailFrame_Update
        GuildMemberDetailFrame_Update = function()
            local r
            if oldUpdate then r = oldUpdate() end
            if Profesjonell.UpdateGuildMemberProfessionInfo then
                Profesjonell.UpdateGuildMemberProfessionInfo()
            end
            return r
        end
    end

    Profesjonell.GuildMemberProfessionAttached = true
    return true
end

function Profesjonell.AttachGuildMemberProfessionInfo()
    if not Profesjonell.TryAttachGuildMemberProfessionInfo() then
        if Profesjonell.Frame then
            Profesjonell.Frame.pendingGuildMemberHook = true
        end
    end
end
