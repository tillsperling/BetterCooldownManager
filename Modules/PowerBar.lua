local _, BCDM = ...

local function ApplyCachedAnchorWidth(frame, anchorName, fallbackWidth)
    BCDM._AnchorWidthCache = BCDM._AnchorWidthCache or {}
    local cachedWidth = BCDM._AnchorWidthCache[anchorName]
    if cachedWidth and cachedWidth > 0 then
        frame:SetWidth(cachedWidth)
    elseif fallbackWidth then
        frame:SetWidth(fallbackWidth)
    end

    local anchorFrame = _G[anchorName]
    if not anchorFrame then return end
    local anchorWidth = anchorFrame:GetWidth()
    if anchorWidth and anchorWidth > 0 then
        BCDM._AnchorWidthCache[anchorName] = anchorWidth
        frame:SetWidth(anchorWidth)
    end
end

local function FetchPowerBarColour(customPowerType)
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local PowerBarDB = CooldownManagerDB.PowerBar
    if PowerBarDB then
        if PowerBarDB.ColourByType then
            local powerType = customPowerType or UnitPowerType("player")
            local powerColour = GeneralDB.Colours.PrimaryPower[powerType]
            if powerColour then return GeneralDB.Colours.PrimaryPower[powerType][1], GeneralDB.Colours.PrimaryPower[powerType][2], GeneralDB.Colours.PrimaryPower[powerType][3], GeneralDB.Colours.PrimaryPower[powerType][4] or 1 end
        elseif PowerBarDB.ColourByClass then
            local _, class = UnitClass("player")
            local classColour = RAID_CLASS_COLORS[class]
            if classColour then return classColour.r, classColour.g, classColour.b, 1 end
        else
            return PowerBarDB.ForegroundColour[1], PowerBarDB.ForegroundColour[2], PowerBarDB.ForegroundColour[3], PowerBarDB.ForegroundColour[4]
        end
    end
end

local function ResolveCurrentClassSpecTokens()
    local classToken = select(2, UnitClass("player"))
    if not classToken then return end
    local specIndex = GetSpecialization()
    if not specIndex then return classToken end
    local specID, specName = GetSpecializationInfo(specIndex)
    local specToken = BCDM:NormalizeSpecToken(specName, specID, specIndex)
    return classToken, specToken
end

local function EnsureThresholdTickConfig(thresholdDB)
    if type(thresholdDB) ~= "table" then return end

    if type(thresholdDB.Values) ~= "table" then
        local migratedValues
        if type(thresholdDB.PerSpec) == "table" then
            local classToken, specToken = ResolveCurrentClassSpecTokens()
            if classToken and specToken and thresholdDB.PerSpec[classToken] and type(thresholdDB.PerSpec[classToken][specToken]) == "table" then
                migratedValues = BCDM:CopyTable(thresholdDB.PerSpec[classToken][specToken])
            end
        end
        thresholdDB.Values = migratedValues or {}
    end

    thresholdDB.Mode = thresholdDB.Mode == "PERCENT" and "PERCENT" or "POWER"
    thresholdDB.PerSpec = nil
end

local function ClearPowerBarThresholdTicks(powerBar)
    if not powerBar or not powerBar.ThresholdTicks then return end
    for _, tick in ipairs(powerBar.ThresholdTicks) do
        tick:Hide()
    end
end

local function GetPowerBarThresholdConfig()
    local powerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.PowerBar
    local thresholdDB = powerBarDB and powerBarDB.ThresholdTicks
    if not thresholdDB then return end
    EnsureThresholdTickConfig(thresholdDB)
    return thresholdDB
end

local function UpdatePowerBarThresholdTicks(powerBar, powerMax)
    if not powerBar or not powerBar.Status then return end

    local powerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.PowerBar
    local thresholdDB = powerBarDB and powerBarDB.ThresholdTicks
    if not thresholdDB or not thresholdDB.Enabled then
        ClearPowerBarThresholdTicks(powerBar)
        return
    end

    local thresholdConfig = GetPowerBarThresholdConfig()
    local thresholds = thresholdConfig and thresholdConfig.Values
    if not thresholds or type(thresholds) ~= "table" then
        ClearPowerBarThresholdTicks(powerBar)
        return
    end

    local barWidth = powerBar.Status:GetWidth()
    if not powerMax or powerMax <= 0 or not barWidth or barWidth <= 0 then
        ClearPowerBarThresholdTicks(powerBar)
        return
    end

    local validThresholds = {}
    local seen = {}
    local mode = thresholdConfig.Mode == "PERCENT" and "PERCENT" or "POWER"
    for _, threshold in ipairs(thresholds) do
        local value = tonumber(threshold)
        if value then
            local relativePosition
            if mode == "PERCENT" then
                if value > 0 and value < 100 then
                    relativePosition = value / 100
                end
            elseif value > 0 and value < powerMax then
                relativePosition = value / powerMax
            end

            if relativePosition and relativePosition > 0 and relativePosition < 1 then
                local key = string.format("%.4f", relativePosition)
                if not seen[key] then
                    seen[key] = true
                    validThresholds[#validThresholds + 1] = {
                        value = value,
                        relativePosition = relativePosition,
                    }
                end
            end
        end
    end

    if #validThresholds == 0 then
        ClearPowerBarThresholdTicks(powerBar)
        return
    end

    table.sort(validThresholds, function(a, b)
        return a.relativePosition < b.relativePosition
    end)

    powerBar.ThresholdTicks = powerBar.ThresholdTicks or {}
    for i, thresholdData in ipairs(validThresholds) do
        local tick = powerBar.ThresholdTicks[i]
        if not tick then
            tick = powerBar.Status:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(1, 1, 1, 1)
            powerBar.ThresholdTicks[i] = tick
        end

        local tickPosition = thresholdData.relativePosition * barWidth
        tick:ClearAllPoints()
        tick:SetSize(1, powerBar:GetHeight() - 2)
        tick:SetPoint("LEFT", powerBar.Status, "LEFT", tickPosition - 0.1, 0)
        tick:SetDrawLayer("OVERLAY", 7)
        tick:Show()
    end

    for i = #validThresholds + 1, #powerBar.ThresholdTicks do
        powerBar.ThresholdTicks[i]:Hide()
    end
end

local function DetectSecondaryPower()
    local class = select(2, UnitClass("player"))
    local spec  = GetSpecialization()
    local specID = GetSpecializationInfo(spec)
    local secondaryPowerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.SecondaryPowerBar
    local showMana = secondaryPowerBarDB and (secondaryPowerBarDB.ShowMana or secondaryPowerBarDB.ShowManaBar)
    if class == "MONK" then
        if specID == 268 then return true end
        if specID == 269 then return true end
    elseif class == "ROGUE" then
        return true
    elseif class == "DRUID" then
        local form = GetShapeshiftFormID()
        if form == 1 then return true end
    elseif class == "PALADIN" then
        return true
    elseif class == "WARLOCK" then
        return true
    elseif class == "MAGE" then
        if specID == 62 then return true end
    elseif class == "EVOKER" then
        return true
    elseif class == "DEATHKNIGHT" then
        return true
    elseif class == "DEMONHUNTER" then
        if specID == 581 or specID == 1480 then return true end
    elseif class == "SHAMAN" then
        if specID == 262 and showMana then return true end
        if specID == 263 then return true end
    elseif class == "PRIEST" then
        if specID == 258 and showMana then return true end    
    elseif class == "WARRIOR" then
        if specID == 72 then return true end
    end
    return false
end

local function NudgePowerBar(powerBar, xOffset, yOffset)
    local powerBarFrame = _G[powerBar]
    if not powerBarFrame then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = powerBarFrame:GetPoint(1)
    powerBarFrame:ClearAllPoints()
    powerBarFrame:SetPoint(point, relativeTo, relativePoint, xOfs + xOffset, yOfs + yOffset)
end

local function UpdatePowerValues()
    local PowerBar = BCDM.PowerBar
    local powerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.PowerBar
    local secondaryBar = BCDM.SecondaryPowerBar
    local secondaryPowerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.SecondaryPowerBar

    if BCDM:ShouldHideCDMWhileMounted() then
        if PowerBar then
            PowerBar:Hide()
        end
        return
    end

    if not PowerBar or not powerBarDB or not powerBarDB.Enabled then return end

    local secondaryInPrimarySlot = secondaryBar
        and secondaryBar:IsShown()
        and secondaryPowerBarDB
        and secondaryPowerBarDB.Enabled
        and secondaryPowerBarDB.SwapToPowerBarPosition
        and BCDM.RepositionSecondaryBar
        and BCDM:RepositionSecondaryBar()

    if secondaryInPrimarySlot then
        PowerBar:Hide()
        return
    end

    PowerBar:Show()

    local GeneralDB = BCDM.db.profile.General
    local _, class = UnitClass("player")
    local powerType = UnitPowerType("player")
    if class == "DRUID" then
        local spec = GetSpecialization()
        local form = GetShapeshiftFormID() or 0 
        local isHybridMoonkin = (spec == 2 or spec == 3 or spec == 4) and form == 31 or form == 32 or form == 33 or form == 34 or form == 35
        local isBalanceHumanoid = (spec == 1 and form == 0)
        if isHybridMoonkin or isBalanceHumanoid then
            powerType = 0 
        end
    end
    local powerCurrent = UnitPower("player", powerType)
    local powerMax = UnitPowerMax("player", powerType)
    if PowerBar and PowerBar.Status and powerType then
        if powerType == 0 then
           PowerBar.Text:SetText(string.format("%.0f%%", UnitPowerPercent("player", 0, false, CurveConstants.ScaleTo100)))
        else
            PowerBar.Text:SetText(tostring(powerCurrent))
        end
        PowerBar.Status:SetStatusBarColor(FetchPowerBarColour(powerType))
        PowerBar.Status:SetMinMaxValues(0, powerMax)
        local smoothBars = GeneralDB.Animation and GeneralDB.Animation.SmoothBars
        if smoothBars and Enum and Enum.StatusBarInterpolation then
            PowerBar.Status:SetValue(powerCurrent, Enum.StatusBarInterpolation.ExponentialEaseOut)
        else
            PowerBar.Status:SetValue(powerCurrent)
        end
        UpdatePowerBarThresholdTicks(PowerBar, powerMax)
    end
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end  BCDM:UpdatePowerBarWidth() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end  BCDM:UpdatePowerBarWidth() end)
end

local updatePowerBarHeightEventFrame = CreateFrame("Frame")
updatePowerBarHeightEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
updatePowerBarHeightEventFrame:SetScript("OnEvent", function(self, event, ...)
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    if PowerBarDB.Enabled and PowerBar then
        local hasSecondary = DetectSecondaryPower()
        PowerBar:SetHeight(hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
    end
end)

function BCDM:CreatePowerBar()
    local GeneralDB = BCDM.db.profile.General
    local PowerBarDB = BCDM.db.profile.PowerBar

    SetHooks()

    local PowerBar = CreateFrame("Frame", "BCDM_PowerBar", UIParent, "BackdropTemplate")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    PowerBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        PowerBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        PowerBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    PowerBar:SetBackdropColor(PowerBarDB.BackgroundColour[1], PowerBarDB.BackgroundColour[2], PowerBarDB.BackgroundColour[3], PowerBarDB.BackgroundColour[4])
    local hasSecondary = DetectSecondaryPower()
    PowerBar:SetSize(PowerBarDB.Width, hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
    PowerBar:SetPoint(PowerBarDB.Layout[1], _G[PowerBarDB.Layout[2]], PowerBarDB.Layout[3], PowerBarDB.Layout[4], PowerBarDB.Layout[5])
    PowerBar:SetFrameStrata(PowerBarDB.FrameStrata or "LOW")

    if PowerBarDB.MatchWidthOfAnchor then
        ApplyCachedAnchorWidth(PowerBar, PowerBarDB.Layout[2], PowerBarDB.Width)
    end

    PowerBar.Status = CreateFrame("StatusBar", nil, PowerBar)
    PowerBar.Status:SetPoint("TOPLEFT", PowerBar, "TOPLEFT", borderSize, -borderSize)
    PowerBar.Status:SetPoint("BOTTOMRIGHT", PowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
    PowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    PowerBar.Status:SetStatusBarColor(FetchPowerBarColour())
    PowerBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
    PowerBar.Status:SetValue(UnitPower("player"))
    PowerBar.ThresholdTicks = {}
    PowerBar.Status:SetScript("OnSizeChanged", function()
        local powerType = UnitPowerType("player")
        UpdatePowerBarThresholdTicks(PowerBar, UnitPowerMax("player", powerType))
    end)

    PowerBar.Text = PowerBar.Status:CreateFontString(nil, "OVERLAY")
    PowerBar.Text:SetFont(BCDM.Media.Font, PowerBarDB.Text.FontSize, GeneralDB.Fonts.FontFlag)
    PowerBar.Text:SetTextColor(PowerBarDB.Text.Colour[1], PowerBarDB.Text.Colour[2], PowerBarDB.Text.Colour[3], 1)
    PowerBar.Text:SetPoint(PowerBarDB.Text.Layout[1], PowerBar, PowerBarDB.Text.Layout[2], PowerBarDB.Text.Layout[3], PowerBarDB.Text.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        PowerBar.Text:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        PowerBar.Text:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        PowerBar.Text:SetShadowColor(0, 0, 0, 0)
        PowerBar.Text:SetShadowOffset(0, 0)
    end
    PowerBar.Text:SetText("")
    if PowerBarDB.Text.Enabled then PowerBar.Text:Show() else PowerBar.Text:Hide() end

    BCDM.PowerBar = PowerBar

    if PowerBarDB.Enabled then
        PowerBar:RegisterEvent("UNIT_POWER_UPDATE")
        PowerBar:RegisterEvent("UNIT_MAXPOWER")
        PowerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
        PowerBar:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
        if PowerBarDB.FrequentUpdates then PowerBar:RegisterEvent("UNIT_POWER_FREQUENT") else PowerBar:UnregisterEvent("UNIT_POWER_FREQUENT") end
        PowerBar:SetScript("OnEvent", UpdatePowerValues)
        NudgePowerBar("BCDM_PowerBar", -0.1, 0)
    else
        PowerBar:Hide()
        ClearPowerBarThresholdTicks(PowerBar)
        PowerBar.Status:SetScript("OnSizeChanged", nil)
        PowerBar:SetScript("OnEvent", nil)
        PowerBar:UnregisterAllEvents()
    end

    BCDM:ApplyMountedCDMVisibility()
end

function BCDM:UpdatePowerBar()
    local GeneralDB = BCDM.db.profile.General
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    if PowerBar then
        if PowerBarDB.Enabled then
            PowerBar:SetBackdrop(BCDM.BACKDROP)
            if borderSize > 0 then
                PowerBar:SetBackdropBorderColor(0, 0, 0, 1)
            else
                PowerBar:SetBackdropBorderColor(0, 0, 0, 0)
            end
            PowerBar.Status:SetPoint("TOPLEFT", PowerBar, "TOPLEFT", borderSize, -borderSize)
            PowerBar.Status:SetPoint("BOTTOMRIGHT", PowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
            PowerBar:ClearAllPoints()
            PowerBar:SetPoint(PowerBarDB.Layout[1], _G[PowerBarDB.Layout[2]], PowerBarDB.Layout[3], PowerBarDB.Layout[4], PowerBarDB.Layout[5])
            PowerBar:SetFrameStrata(PowerBarDB.FrameStrata or "LOW")
            if PowerBarDB.MatchWidthOfAnchor then
                ApplyCachedAnchorWidth(PowerBar, PowerBarDB.Layout[2], PowerBarDB.Width)
            else
                PowerBar:SetWidth(PowerBarDB.Width)
            end
            local hasSecondary = DetectSecondaryPower()
            PowerBar:SetHeight(hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
            PowerBar:SetBackdropColor(PowerBarDB.BackgroundColour[1], PowerBarDB.BackgroundColour[2], PowerBarDB.BackgroundColour[3], PowerBarDB.BackgroundColour[4])
            PowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
            PowerBar.Status:SetScript("OnSizeChanged", function()
                local powerType = UnitPowerType("player")
                UpdatePowerBarThresholdTicks(PowerBar, UnitPowerMax("player", powerType))
            end)
            PowerBar.Text:SetFont(BCDM.Media.Font, PowerBarDB.Text.FontSize, BCDM.db.profile.General.Fonts.FontFlag)
            PowerBar.Text:SetTextColor(PowerBarDB.Text.Colour[1], PowerBarDB.Text.Colour[2], PowerBarDB.Text.Colour[3], 1)
            PowerBar.Text:SetPoint(PowerBarDB.Text.Layout[1], PowerBar, PowerBarDB.Text.Layout[2], PowerBarDB.Text.Layout[3], PowerBarDB.Text.Layout[4])
            if GeneralDB.Fonts.Shadow.Enabled then
                PowerBar.Text:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
                PowerBar.Text:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
            else
                PowerBar.Text:SetShadowColor(0, 0, 0, 0)
                PowerBar.Text:SetShadowOffset(0, 0)
            end
            PowerBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
            PowerBar.Status:SetStatusBarColor(FetchPowerBarColour())
            PowerBar:RegisterEvent("UNIT_POWER_UPDATE")
            PowerBar:RegisterEvent("UNIT_MAXPOWER")
            PowerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
            PowerBar:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
            if PowerBarDB.FrequentUpdates then PowerBar:RegisterEvent("UNIT_POWER_FREQUENT") else PowerBar:UnregisterEvent("UNIT_POWER_FREQUENT") end
            PowerBar:SetScript("OnEvent", UpdatePowerValues)
            UpdatePowerValues()
            if PowerBarDB.Text.Enabled then PowerBar.Text:Show() else PowerBar.Text:Hide() end
            NudgePowerBar("BCDM_PowerBar", -0.1, 0)
            if PowerBarDB.Enabled and not BCDM.db.profile.SecondaryPowerBar.SwapToPowerBarPosition then PowerBar:Show() end
            BCDM:ApplyMountedCDMVisibility()
        else
            PowerBar:Hide()
            ClearPowerBarThresholdTicks(PowerBar)
            PowerBar:SetScript("OnEvent", nil)
            PowerBar.Status:SetScript("OnSizeChanged", nil)
            PowerBar:UnregisterAllEvents()
        end
    end
end

function BCDM:UpdatePowerBarWidth()
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    if PowerBarDB.Enabled and PowerBarDB.MatchWidthOfAnchor then
        ApplyCachedAnchorWidth(PowerBar, PowerBarDB.Layout[2], PowerBarDB.Width)
    end
end
