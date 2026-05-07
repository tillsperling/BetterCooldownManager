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
    local viewer = _G["BCDM_DefensivesViewer"]
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

local function GetReadableNumber(value)
    if type(value) ~= "number" then return nil end
    if BCDM:IsSecretValue(value) then return nil end
    return value
end

local function UpdateSpellIconDesaturation(customIcon, spellId)
    if not customIcon or not customIcon.Icon then return end
    local desaturationCurve, gcdFilterCurve = BCDM:GetCooldownDesaturationCurves()

    local cooldownData = C_Spell.GetSpellCooldown(spellId)
    if cooldownData and cooldownData.isOnGCD then
        SetIconDesaturation(customIcon.Icon, 0)
        return
    end

    local spellCharges = C_Spell.GetSpellCharges(spellId)
    local currentCharges = spellCharges and (spellCharges.maxCharges or 0) > 1 and GetReadableNumber(spellCharges.currentCharges)
    if currentCharges then
        if currentCharges > 0 then
            SetIconDesaturation(customIcon.Icon, 0)
            return
        end
        local chargeDuration = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellId)
        if chargeDuration and type(chargeDuration.EvaluateRemainingDuration) == "function" then
            SetIconDesaturation(customIcon.Icon, (desaturationCurve and chargeDuration:EvaluateRemainingDuration(desaturationCurve, 0)) or CalculateFallbackDesaturation(spellCharges.cooldownStartTime, spellCharges.cooldownDuration))
        else
            SetIconDesaturation(customIcon.Icon, CalculateFallbackDesaturation(spellCharges.cooldownStartTime, spellCharges.cooldownDuration))
        end
        return
    end

    local durationObject = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellId)
    if durationObject and type(durationObject.EvaluateRemainingDuration) == "function" then
        local curve = (cooldownData and cooldownData.isOnGCD) and gcdFilterCurve or desaturationCurve
        SetIconDesaturation(customIcon.Icon, (curve and durationObject:EvaluateRemainingDuration(curve, 0)) or 0)
    else
        if not cooldownData then
            SetIconDesaturation(customIcon.Icon, 0)
        else
            SetIconDesaturation(customIcon.Icon, CalculateFallbackDesaturation(cooldownData.startTime, cooldownData.duration))
        end
    end
end

local function CreateCustomIcon(spellId)
    local cooldownManagerDB = BCDM.db.profile
    local generalDB = cooldownManagerDB.General
    local customDB = cooldownManagerDB.CooldownManager.Defensives
    if not spellId then return end
    if not C_SpellBook.IsSpellInSpellBook(spellId) then return end

    local customIcon = CreateFrame("Button", "BCDM_Defensive_" .. spellId, UIParent, "BackdropTemplate")
    customIcon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = BCDM.db.profile.CooldownManager.General.BorderSize, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    customIcon:SetBackdropColor(0, 0, 0, 0)
    if BCDM.db.profile.CooldownManager.General.BorderSize <= 0 then
        customIcon:SetBackdropBorderColor(0, 0, 0, 0)
    else
        customIcon:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local iconWidth, iconHeight = BCDM:GetIconDimensions(customDB)
    customIcon:SetSize(iconWidth, iconHeight)
    local anchorParent = customDB.Layout[2] == "NONE" and UIParent or _G[customDB.Layout[2]]
    customIcon:SetPoint(customDB.Layout[1], anchorParent, customDB.Layout[3], customDB.Layout[4], customDB.Layout[5])
    customIcon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    customIcon:RegisterEvent("PLAYER_ENTERING_WORLD")
    customIcon:RegisterEvent("SPELL_UPDATE_CHARGES")
    customIcon:EnableMouse(false)

    local highLevelContainer = CreateFrame("Frame", nil, customIcon)
    highLevelContainer:SetAllPoints(customIcon)
    highLevelContainer:SetFrameLevel(customIcon:GetFrameLevel() + 999)

    customIcon.Charges = highLevelContainer:CreateFontString(nil, "OVERLAY")
    customIcon.Charges:SetFont(BCDM.Media.Font, customDB.Text.FontSize, generalDB.Fonts.FontFlag)
    customIcon.Charges:SetPoint(customDB.Text.Layout[1], customIcon, customDB.Text.Layout[2], customDB.Text.Layout[3], customDB.Text.Layout[4])
    customIcon.Charges:SetTextColor(customDB.Text.Colour[1], customDB.Text.Colour[2], customDB.Text.Colour[3], 1)
    if generalDB.Fonts.Shadow.Enabled then
        customIcon.Charges:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
        customIcon.Charges:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
    else
        customIcon.Charges:SetShadowColor(0, 0, 0, 0)
        customIcon.Charges:SetShadowOffset(0, 0)
    end

    customIcon.Cooldown = CreateFrame("Cooldown", nil, customIcon, "CooldownFrameTemplate")
    customIcon.Cooldown:SetAllPoints(customIcon)
    customIcon.Cooldown:SetDrawEdge(false)
    customIcon.Cooldown:SetDrawSwipe(true)
    customIcon.Cooldown:SetDrawBling(false)
    customIcon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    customIcon.Cooldown:SetHideCountdownNumbers(false)
    customIcon.Cooldown:SetReverse(false)

    customIcon:SetScript("OnEvent", function(self, event)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "PLAYER_ENTERING_WORLD" or event == "SPELL_UPDATE_CHARGES" then
            local spellCharges = C_Spell.GetSpellCharges(spellId)
            if spellCharges and (spellCharges.maxCharges or 0) > 1 then
                customIcon.Charges:SetText(C_Spell.GetSpellDisplayCount(spellId))
                local spellChargeCooldown = C_Spell.GetSpellChargeDuration(spellId)
                customIcon.Cooldown:SetCooldownFromDurationObject(spellChargeCooldown, true)
            else
                customIcon.Charges:SetText("")
                local spellCooldown = C_Spell.GetSpellCooldownDuration(spellId)
                customIcon.Cooldown:SetCooldownFromDurationObject(spellCooldown, true)
            end
            UpdateSpellIconDesaturation(self, spellId)
        end
    end)

    customIcon.Icon = customIcon:CreateTexture(nil, "BACKGROUND")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    customIcon.Icon:SetPoint("TOPLEFT", customIcon, "TOPLEFT", borderSize, -borderSize)
    customIcon.Icon:SetPoint("BOTTOMRIGHT", customIcon, "BOTTOMRIGHT", -borderSize, borderSize)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    BCDM:ApplyIconTexCoord(customIcon.Icon, iconWidth, iconHeight, iconZoom)
    customIcon.Icon:SetTexture(C_Spell.GetSpellInfo(spellId).iconID)

    return customIcon
end

local function CreateCustomIcons(iconTable)
    local playerClass = select(2, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID, specName = specIndex and GetSpecializationInfo(specIndex)
    local playerSpecialization = BCDM:NormalizeSpecToken(specName, specID, specIndex)
    local defensiveSpellsDB = BCDM.db.profile.CooldownManager.Defensives.Spells

    wipe(iconTable)

    if playerSpecialization and defensiveSpellsDB[playerClass] and defensiveSpellsDB[playerClass][playerSpecialization] then
        local defensiveSpells = {}

        for spellId, data in pairs(defensiveSpellsDB[playerClass][playerSpecialization]) do
            if data.isActive then
                table.insert(defensiveSpells, { id = spellId, index = data.layoutIndex })
            end
        end

        table.sort(defensiveSpells, function(a, b) return a.index < b.index end)

        for _, spell in ipairs(defensiveSpells) do
            local customSpell = CreateCustomIcon(spell.id)
            if customSpell then
                table.insert(iconTable, customSpell)
            end
        end
    end
end

local function GetColumnWrapLimit(customDB)
    local wrapLimit = math.floor(tonumber(customDB.Columns) or 0)
    if wrapLimit < 1 then
        return 0
    end
    return wrapLimit
end

local function IsCenteredHorizontalLayout(point, growthDirection)
    return (point == "TOP" or point == "BOTTOM") and (growthDirection == "LEFT" or growthDirection == "RIGHT")
end

local function ShouldGrowUp(point)
    return point and point:find("BOTTOM") ~= nil
end

local function ShouldGrowLeft(point)
    return point and point:find("RIGHT") ~= nil
end

local function LayoutDefensivesViewer()
    local cooldownManagerDB = BCDM.db.profile
    local customDB = cooldownManagerDB.CooldownManager.Defensives
    local customCooldownViewerIcons = {}

    local growthDirection = customDB.GrowthDirection or "RIGHT"

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

    if not BCDM.DefensivesViewerContainer then
        BCDM.DefensivesViewerContainer = CreateFrame("Frame", "BCDM_DefensivesViewer", UIParent, "BackdropTemplate")
        BCDM.DefensivesViewerContainer:SetSize(1, 1)
    end

    BCDM.DefensivesViewerContainer:ClearAllPoints()
    BCDM.DefensivesViewerContainer:SetFrameStrata(customDB.FrameStrata or "LOW")
    local anchorParent = customDB.Layout[2] == "NONE" and UIParent or _G[customDB.Layout[2]]
    BCDM.DefensivesViewerContainer:SetPoint(containerAnchorFrom, anchorParent, customDB.Layout[3], customDB.Layout[4], customDB.Layout[5])

    for _, child in ipairs({ BCDM.DefensivesViewerContainer:GetChildren() }) do
        child:UnregisterAllEvents()
        child:Hide()
        child:SetParent(nil)
    end

    CreateCustomIcons(customCooldownViewerIcons)

    local iconWidth, iconHeight = BCDM:GetIconDimensions(customDB)
    local iconSpacing = customDB.Spacing

    local point = select(1, BCDM.DefensivesViewerContainer:GetPoint(1))
    local isHorizontalGrowth = growthDirection == "LEFT" or growthDirection == "RIGHT"
    local wrapLimit = GetColumnWrapLimit(customDB)
    local lineLimit = (wrapLimit > 0) and wrapLimit or #customCooldownViewerIcons
    local useCenteredLayout = IsCenteredHorizontalLayout(point, growthDirection)

    if #customCooldownViewerIcons == 0 then
        BCDM.DefensivesViewerContainer:SetSize(1, 1)
    else
        local totalWidth, totalHeight
        local lineCount = math.ceil(#customCooldownViewerIcons / lineLimit)

        if isHorizontalGrowth then
            local columnsInRow = math.min(lineLimit, #customCooldownViewerIcons)
            totalWidth = (columnsInRow * iconWidth) + ((columnsInRow - 1) * iconSpacing)
            totalHeight = (lineCount * iconHeight) + ((lineCount - 1) * iconSpacing)
        else
            local rowsInColumn = math.min(lineLimit, #customCooldownViewerIcons)
            totalWidth = (lineCount * iconWidth) + ((lineCount - 1) * iconSpacing)
            totalHeight = (rowsInColumn * iconHeight) + ((rowsInColumn - 1) * iconSpacing)
        end
        BCDM.DefensivesViewerContainer:SetSize(totalWidth, totalHeight)
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

    if useCenteredLayout and #customCooldownViewerIcons > 0 then
        local rowCount = math.ceil(#customCooldownViewerIcons / lineLimit)
        local rowDirection = ShouldGrowUp(point) and 1 or -1

        for rowIndex = 1, rowCount do
            local rowStart = ((rowIndex - 1) * lineLimit) + 1
            local rowEnd = math.min(rowStart + lineLimit - 1, #customCooldownViewerIcons)
            local rowIcons = rowEnd - rowStart + 1
            local rowWidth = (rowIcons * iconWidth) + ((rowIcons - 1) * iconSpacing)
            local startOffset = -(rowWidth / 2) + (iconWidth / 2)
            local yOffset = (rowIndex - 1) * (iconHeight + iconSpacing) * rowDirection

            for i = rowStart, rowEnd do
                local spellIcon = customCooldownViewerIcons[i]
                spellIcon:SetParent(BCDM.DefensivesViewerContainer)
                spellIcon:SetSize(iconWidth, iconHeight)
                spellIcon:ClearAllPoints()

                local xOffset = startOffset + ((i - rowStart) * (iconWidth + iconSpacing))
                spellIcon:SetPoint("CENTER", BCDM.DefensivesViewerContainer, "CENTER", xOffset, yOffset)
                ApplyCooldownText()
                spellIcon:Show()
            end
        end
    else
        for i, spellIcon in ipairs(customCooldownViewerIcons) do
            spellIcon:SetParent(BCDM.DefensivesViewerContainer)
            spellIcon:SetSize(iconWidth, iconHeight)
            spellIcon:ClearAllPoints()

            if i == 1 then
                local config = layoutConfig[point] or layoutConfig.TOPLEFT
                spellIcon:SetPoint(config.anchor, BCDM.DefensivesViewerContainer, config.anchor, 0, 0)
            else
                local isWrappedRowStart = (i - 1) % lineLimit == 0
                if isWrappedRowStart then
                    local lineAnchorIcon = customCooldownViewerIcons[i - lineLimit]
                    if isHorizontalGrowth then
                        if ShouldGrowUp(point) then
                            spellIcon:SetPoint("BOTTOM", lineAnchorIcon, "TOP", 0, iconSpacing)
                        else
                            spellIcon:SetPoint("TOP", lineAnchorIcon, "BOTTOM", 0, -iconSpacing)
                        end
                    else
                        if ShouldGrowLeft(point) then
                            spellIcon:SetPoint("RIGHT", lineAnchorIcon, "LEFT", -iconSpacing, 0)
                        else
                            spellIcon:SetPoint("LEFT", lineAnchorIcon, "RIGHT", iconSpacing, 0)
                        end
                    end
                else
                    if growthDirection == "RIGHT" then
                        spellIcon:SetPoint("LEFT", customCooldownViewerIcons[i - 1], "RIGHT", iconSpacing, 0)
                    elseif growthDirection == "LEFT" then
                        spellIcon:SetPoint("RIGHT", customCooldownViewerIcons[i - 1], "LEFT", -iconSpacing, 0)
                    elseif growthDirection == "UP" then
                        spellIcon:SetPoint("BOTTOM", customCooldownViewerIcons[i - 1], "TOP", 0, iconSpacing)
                    elseif growthDirection == "DOWN" then
                        spellIcon:SetPoint("TOP", customCooldownViewerIcons[i - 1], "BOTTOM", 0, -iconSpacing)
                    end
                end
            end
            ApplyCooldownText()
            spellIcon:Show()
        end
    end

    BCDM.DefensivesViewerContainer:Show()
end

function BCDM:SetupDefensivesViewer()
    BCDM:EnsureDefensivesSpellDB()
    LayoutDefensivesViewer()
end

function BCDM:UpdateDefensivesViewer()
    BCDM:EnsureDefensivesSpellDB()
    local cooldownManagerDB = BCDM.db.profile
    local customDB = cooldownManagerDB.CooldownManager.Defensives
    if BCDM.DefensivesViewerContainer then
        BCDM.DefensivesViewerContainer:ClearAllPoints()
        local anchorParent = customDB.Layout[2] == "NONE" and UIParent or _G[customDB.Layout[2]]
        BCDM.DefensivesViewerContainer:SetPoint(customDB.Layout[1], anchorParent, customDB.Layout[3], customDB.Layout[4], customDB.Layout[5])
    end
    if customDB.Enabled == false then
        if BCDM.DefensivesViewerContainer then
            BCDM.DefensivesViewerContainer:Hide()
        end
        return
    end
    LayoutDefensivesViewer()
end
