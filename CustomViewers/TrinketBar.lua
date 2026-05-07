local _, BCDM = ...

local function FetchCooldownTextRegion(cooldown)
    if not cooldown then return end
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            return region
        end
    end
end

local function ApplyCooldownText()
    local cooldownManagerDB = BCDM.db.profile
    local generalDB = cooldownManagerDB.General
    local cooldownTextDB = cooldownManagerDB.CooldownManager.General.CooldownText
    local viewer = _G["BCDM_TrinketsViewer"]
    if not viewer then return end
    for _, icon in ipairs({ viewer:GetChildren() }) do
        if icon and icon.Cooldown then
            local textRegion = FetchCooldownTextRegion(icon.Cooldown)
            if textRegion then
                if cooldownTextDB.ScaleByIconSize then
                    local iconWidth = icon:GetWidth()
                    local scaleFactor = iconWidth / 36
                    textRegion:SetFont(BCDM.Media.Font, cooldownTextDB.FontSize * scaleFactor, generalDB.Fonts.FontFlag)
                else
                    textRegion:SetFont(BCDM.Media.Font, cooldownTextDB.FontSize, generalDB.Fonts.FontFlag)
                end
                textRegion:SetTextColor(cooldownTextDB.Colour[1], cooldownTextDB.Colour[2], cooldownTextDB.Colour[3], 1)
                textRegion:ClearAllPoints()
                textRegion:SetPoint(cooldownTextDB.Layout[1], icon, cooldownTextDB.Layout[2], cooldownTextDB.Layout[3], cooldownTextDB.Layout[4])
                if generalDB.Fonts.Shadow.Enabled then
                    textRegion:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
                    textRegion:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
                else
                    textRegion:SetShadowColor(0, 0, 0, 0)
                    textRegion:SetShadowOffset(0, 0)
                end
            end
        end
    end
end

local function SetIconDesaturation(icon, value)
    if not icon then return end
    if icon.SetDesaturation then
        icon:SetDesaturation(value)
        return
    end
    if icon.SetDesaturated then
        icon:SetDesaturated(value > 0)
    end
end

local function CalculateFallbackDesaturation(startTime, duration)
    if not startTime or not duration then return 0 end
    if BCDM:IsSecretValue(startTime) or BCDM:IsSecretValue(duration) then return 0 end
    local remaining = (startTime + duration) - GetTime()
    return remaining > 0.001 and 1 or 0
end

local function FetchItemData(itemId)
    local startTime, durationTime = C_Item.GetItemCooldown(itemId)
    return startTime, durationTime
end

local function IsOnUseTrinket(itemId)
    if not itemId then return false end
    local spellName, spellID = C_Item.GetItemSpell(itemId)
    return (spellID and spellID > 0) or (spellName and spellName ~= "")
end

local function FetchEquippedTrinkets(showPassive)
    local equipped = {}
    for _, slotID in ipairs({ 13, 14 }) do
        local itemId = GetInventoryItemID("player", slotID)
        if itemId and (showPassive or IsOnUseTrinket(itemId)) then
            equipped[#equipped + 1] = { itemId = itemId, slotID = slotID }
        end
    end
    return equipped
end

local function CreateCustomIcon(itemId, slotID)
    local cooldownManagerDB = BCDM.db.profile
    local customDB = cooldownManagerDB.CooldownManager.Trinkets
    if not itemId then return end
    if not C_Item.GetItemInfo(itemId) then return end

    local uniqueFrameId = slotID or itemId
    local customIcon = CreateFrame("Button", "BCDM_Trinket_" .. uniqueFrameId, UIParent, "BackdropTemplate")
    customIcon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = BCDM.db.profile.CooldownManager.General.BorderSize, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    customIcon:SetBackdropColor(0, 0, 0, 0)
    if BCDM.db.profile.CooldownManager.General.BorderSize <= 0 then
        customIcon:SetBackdropBorderColor(0, 0, 0, 0)
    else
        customIcon:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local iconWidth, iconHeight = BCDM:GetIconDimensions(customDB)
    customIcon:SetSize(iconWidth, iconHeight)
    customIcon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    customIcon:RegisterEvent("PLAYER_ENTERING_WORLD")
    customIcon:EnableMouse(false)
    customIcon:SetFrameStrata(customDB.FrameStrata or "LOW")

    customIcon.Cooldown = CreateFrame("Cooldown", nil, customIcon, "CooldownFrameTemplate")
    customIcon.Cooldown:SetAllPoints(customIcon)
    customIcon.Cooldown:SetDrawEdge(false)
    customIcon.Cooldown:SetDrawSwipe(true)
    customIcon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    customIcon.Cooldown:SetHideCountdownNumbers(false)
    customIcon.Cooldown:SetReverse(false)

    customIcon:HookScript("OnEvent", function()
        local startTime, durationTime = FetchItemData(itemId)
        local hasActiveCooldown = (startTime and durationTime and startTime > 0 and durationTime > 0) or false
        if hasActiveCooldown then
            local durationObject = C_DurationUtil.CreateDuration()
            durationObject:SetTimeFromStart(startTime, durationTime)
            customIcon.Cooldown:SetCooldownFromDurationObject(durationObject, true)
            if BCDM:IsSecretValue(startTime) or BCDM:IsSecretValue(durationTime) then
                SetIconDesaturation(customIcon.Icon, 0)
            else
                SetIconDesaturation(customIcon.Icon, CalculateFallbackDesaturation(startTime, durationTime))
            end
        else
            customIcon.Cooldown:SetCooldownFromDurationObject(C_DurationUtil.CreateDuration(), true)
            SetIconDesaturation(customIcon.Icon, 0)
        end
    end)

    customIcon.Icon = customIcon:CreateTexture(nil, "BACKGROUND")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    customIcon.Icon:SetPoint("TOPLEFT", customIcon, "TOPLEFT", borderSize, -borderSize)
    customIcon.Icon:SetPoint("BOTTOMRIGHT", customIcon, "BOTTOMRIGHT", -borderSize, borderSize)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    BCDM:ApplyIconTexCoord(customIcon.Icon, iconWidth, iconHeight, iconZoom)
    customIcon.Icon:SetTexture(select(10, C_Item.GetItemInfo(itemId)))

    return customIcon
end

local function CreateCustomIcons(iconTable)
    wipe(iconTable)

    local trinketsDB = BCDM.db.profile.CooldownManager.Trinkets
    local trinkets = FetchEquippedTrinkets(trinketsDB.ShowPassive ~= false)
    for _, trinketEntry in ipairs(trinkets) do
        local customTrinket = CreateCustomIcon(trinketEntry.itemId, trinketEntry.slotID)
        if customTrinket then
            table.insert(iconTable, customTrinket)
        end
    end
end

local function GetContainerAnchor(customDB, growthDirection)
    local containerAnchorFrom = customDB.Layout[1]
    if growthDirection == "UP" then
        local verticalFlipMap = {
            ["TOPLEFT"] = "BOTTOMLEFT",
            ["TOP"] = "BOTTOM",
            ["TOPRIGHT"] = "BOTTOMRIGHT",
            ["BOTTOMLEFT"] = "TOPLEFT",
            ["BOTTOM"] = "TOP",
            ["BOTTOMRIGHT"] = "TOPRIGHT",
        }
        containerAnchorFrom = verticalFlipMap[customDB.Layout[1]] or customDB.Layout[1]
    end
    return containerAnchorFrom
end

local function PositionTrinketsContainer(customDB, growthDirection)
    local anchorFrom = GetContainerAnchor(customDB, growthDirection)
    BCDM.TrinketsViewerContainer:ClearAllPoints()

    if customDB.Mode == "defensives" then
        local defensives = BCDM.DefensivesViewerContainer
        if defensives and defensives:IsShown() then
            local defensivesPoint = select(1, defensives:GetPoint(1)) or "TOPLEFT"
            if defensivesPoint:find("RIGHT") then
                BCDM.TrinketsViewerContainer:SetPoint("TOPLEFT", defensives, "TOPRIGHT", customDB.Spacing or 1, 0)
            else
                BCDM.TrinketsViewerContainer:SetPoint("TOPRIGHT", defensives, "TOPLEFT", -(customDB.Spacing or 1), 0)
            end
            return
        end
    end

    local anchorParent = customDB.Layout[2] == "NONE" and UIParent or _G[customDB.Layout[2]]
    BCDM.TrinketsViewerContainer:SetPoint(anchorFrom, anchorParent, customDB.Layout[3], customDB.Layout[4], customDB.Layout[5])
end

local function LayoutTrinketsViewer()
    local cooldownManagerDB = BCDM.db.profile
    local customDB = cooldownManagerDB.CooldownManager.Trinkets
    local customTrinketIcons = {}

    local growthDirection = customDB.GrowthDirection or "RIGHT"

    if not BCDM.TrinketsViewerContainer then
        BCDM.TrinketsViewerContainer = CreateFrame("Frame", "BCDM_TrinketsViewer", UIParent, "BackdropTemplate")
        BCDM.TrinketsViewerContainer:SetSize(1, 1)
    end

    BCDM.TrinketsViewerContainer:SetFrameStrata(customDB.FrameStrata or "LOW")
    PositionTrinketsContainer(customDB, growthDirection)

    for _, child in ipairs({ BCDM.TrinketsViewerContainer:GetChildren() }) do
        child:UnregisterAllEvents()
        child:Hide()
        child:SetParent(nil)
    end

    CreateCustomIcons(customTrinketIcons)

    local iconWidth, iconHeight = BCDM:GetIconDimensions(customDB)
    local iconSpacing = customDB.Spacing

    if #customTrinketIcons == 0 then
        BCDM.TrinketsViewerContainer:SetSize(1, 1)
    else
        local point = select(1, BCDM.TrinketsViewerContainer:GetPoint(1))
        local useCenteredLayout = (point == "TOP" or point == "BOTTOM") and (growthDirection == "LEFT" or growthDirection == "RIGHT")

        local totalWidth, totalHeight = 0, 0
        if useCenteredLayout or growthDirection == "RIGHT" or growthDirection == "LEFT" then
            totalWidth = (#customTrinketIcons * iconWidth) + ((#customTrinketIcons - 1) * iconSpacing)
            totalHeight = iconHeight
        else
            totalWidth = iconWidth
            totalHeight = (#customTrinketIcons * iconHeight) + ((#customTrinketIcons - 1) * iconSpacing)
        end
        BCDM.TrinketsViewerContainer:SetWidth(totalWidth)
        BCDM.TrinketsViewerContainer:SetHeight(totalHeight)
    end

    local layoutConfig = {
        TOPLEFT = { anchor = "TOPLEFT" },
        TOP = { anchor = "TOP" },
        TOPRIGHT = { anchor = "TOPRIGHT" },
        BOTTOMLEFT = { anchor = "BOTTOMLEFT" },
        BOTTOM = { anchor = "BOTTOM" },
        BOTTOMRIGHT = { anchor = "BOTTOMRIGHT" },
        LEFT = { anchor = "LEFT" },
        RIGHT = { anchor = "RIGHT" },
        CENTER = { anchor = "CENTER" },
    }

    local point = select(1, BCDM.TrinketsViewerContainer:GetPoint(1))
    local useCenteredLayout = (point == "TOP" or point == "BOTTOM") and (growthDirection == "LEFT" or growthDirection == "RIGHT")

    if useCenteredLayout and #customTrinketIcons > 0 then
        local totalWidth = (#customTrinketIcons * iconWidth) + ((#customTrinketIcons - 1) * iconSpacing)
        local startOffset = -(totalWidth / 2) + (iconWidth / 2)

        for i, spellIcon in ipairs(customTrinketIcons) do
            spellIcon:SetParent(BCDM.TrinketsViewerContainer)
            spellIcon:SetSize(iconWidth, iconHeight)
            spellIcon:ClearAllPoints()

            local xOffset = startOffset + ((i - 1) * (iconWidth + iconSpacing))
            spellIcon:SetPoint("CENTER", BCDM.TrinketsViewerContainer, "CENTER", xOffset, 0)
            ApplyCooldownText()
            spellIcon:Show()
        end
    else
        for i, spellIcon in ipairs(customTrinketIcons) do
            spellIcon:SetParent(BCDM.TrinketsViewerContainer)
            spellIcon:SetSize(iconWidth, iconHeight)
            spellIcon:ClearAllPoints()

            if i == 1 then
                local config = layoutConfig[point] or layoutConfig.TOPLEFT
                spellIcon:SetPoint(config.anchor, BCDM.TrinketsViewerContainer, config.anchor, 0, 0)
            else
                if growthDirection == "RIGHT" then
                    spellIcon:SetPoint("LEFT", customTrinketIcons[i - 1], "RIGHT", iconSpacing, 0)
                elseif growthDirection == "LEFT" then
                    spellIcon:SetPoint("RIGHT", customTrinketIcons[i - 1], "LEFT", -iconSpacing, 0)
                elseif growthDirection == "UP" then
                    spellIcon:SetPoint("BOTTOM", customTrinketIcons[i - 1], "TOP", 0, iconSpacing)
                elseif growthDirection == "DOWN" then
                    spellIcon:SetPoint("TOP", customTrinketIcons[i - 1], "BOTTOM", 0, -iconSpacing)
                end
            end
            ApplyCooldownText()
            spellIcon:Show()
        end
    end

    BCDM.TrinketsViewerContainer:Show()
end

function BCDM:SetupTrinketsViewer()
    LayoutTrinketsViewer()
    if BCDM:ShouldHideCDMWhileMounted() and BCDM.TrinketsViewerContainer then
        BCDM:SetFrameShownWithFade(BCDM.TrinketsViewerContainer, false)
    end
end

function BCDM:UpdateTrinketsViewer()
    local customDB = BCDM.db.profile.CooldownManager.Trinkets
    if customDB.Enabled == false then
        if BCDM.TrinketsViewerContainer then
            BCDM.TrinketsViewerContainer:Hide()
        end
        return
    end
    LayoutTrinketsViewer()
    if BCDM:ShouldHideCDMWhileMounted() and BCDM.TrinketsViewerContainer then
        BCDM:SetFrameShownWithFade(BCDM.TrinketsViewerContainer, false)
    end
end

function BCDM:SetupTrinketBar()
    BCDM:SetupTrinketsViewer()
end

function BCDM:UpdateTrinketBar()
    BCDM:UpdateTrinketsViewer()
end

local trinketCheckEvent = CreateFrame("Frame")
trinketCheckEvent:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
trinketCheckEvent:RegisterEvent("PLAYER_LOGIN")
trinketCheckEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
trinketCheckEvent:SetScript("OnEvent", function(_, event, slot)
    if InCombatLockdown() then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            BCDM:UpdateTrinketsViewer()
        end)
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" and (slot == 13 or slot == 14) then
        BCDM:UpdateTrinketsViewer()
    end
end)
