-- MinimapButton.lua
-- Minimap button that opens the Profesjonell search window
Profesjonell = Profesjonell or {}

function Profesjonell.CreateMinimapButton()
    if Profesjonell.minimapButton then return end

    local button = CreateFrame("Button", "ProfesjonellMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\ability_hunter_aspectofthemonkey")
    icon:SetPoint("CENTER", 0, 1)

    -- Dragging around the minimap
    local minimapAngle = 220
    local isDragging = false

    local function UpdatePosition()
        local rad = math.rad(minimapAngle)
        local x = 52 * math.cos(rad)
        local y = 52 * math.sin(rad)
        button:SetPoint("TOPLEFT", Minimap, "TOPLEFT",
            54 - (button:GetWidth() / 2) + x,
            (button:GetHeight() / 2) - 55 + y)
    end

    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    button:SetScript("OnDragStart", function()
        isDragging = true
    end)

    button:SetScript("OnDragStop", function()
        isDragging = false
    end)

    button:SetScript("OnUpdate", function()
        if isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end
    end)

    button:SetScript("OnClick", function()
        if Profesjonell.ToggleSearchWindow then
            Profesjonell.ToggleSearchWindow()
        end
    end)

    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("Profesjonell search")
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition()
    Profesjonell.minimapButton = button
end
