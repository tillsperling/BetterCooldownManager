local _, BCDM = ...
local GCD_DUMMY_SPELL_ID = 61304
local INSTANT_CAST_RETRIGGER_DEBOUNCE = 0.15
local lastStartedSpellID = nil
local lastStartedWasRealCast = false

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

local function SetBarValue(bar, value)
    local GeneralDB = BCDM.db.profile.General
    local smoothBars = GeneralDB.Animation and GeneralDB.Animation.SmoothBars
    if smoothBars and Enum and Enum.StatusBarInterpolation then
        bar:SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)
    else
        bar:SetValue(value)
    end
end

local function GetDisplayCastText(text, maxChars)
    if not text then return "" end
    if BCDM:IsSecretValue(text) then
        return text
    end
    return string.sub(text, 1, maxChars)
end

local function FetchCastBarColour()
    local CastBarDB = BCDM.db.profile.CastBar
    if CastBarDB.ColourByClass then
        local _, class = UnitClass("player")
        local colour = RAID_CLASS_COLORS[class]
        return colour.r, colour.g, colour.b, 1
    else
        return CastBarDB.ForegroundColour[1], CastBarDB.ForegroundColour[2], CastBarDB.ForegroundColour[3], CastBarDB.ForegroundColour[4]
    end
end

local function FetchCastBarChannelColour()
    local CastBarDB = BCDM.db.profile.CastBar
    local colour = CastBarDB.ChannelForegroundColour or CastBarDB.ForegroundColour
    return colour[1], colour[2], colour[3], colour[4]
end

local function ApplyCastBarStatusColour(isChanneled)
    if not BCDM.CastBar or not BCDM.CastBar.Status then return end
    if isChanneled then
        BCDM.CastBar.Status:SetStatusBarColor(FetchCastBarChannelColour())
    else
        BCDM.CastBar.Status:SetStatusBarColor(FetchCastBarColour())
    end
end

local function ApplyInstantCastStatusColour()
    if not BCDM.CastBar or not BCDM.CastBar.Status then return end
    local colour = BCDM.db.profile.CastBar.BackgroundColour
    BCDM.CastBar.Status:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4])
end

local function ApplyCastBarBackdropColour(r, g, b, a)
    if not BCDM.CastBar then return end
    BCDM.CastBar:SetBackdropColor(r, g, b, a)
end

local function ApplyDefaultCastBarBackdropColour()
    if not BCDM.CastBar then return end
    local colour = BCDM.db.profile.CastBar.BackgroundColour
    ApplyCastBarBackdropColour(colour[1], colour[2], colour[3], colour[4])
end

local function ApplyInstantCastBackdropColour()
    if not BCDM.CastBar then return end
    local colour = BCDM.db.profile.CastBar.InstantCastForegroundColour or BCDM.db.profile.CastBar.ForegroundColour
    ApplyCastBarBackdropColour(colour[1], colour[2], colour[3], colour[4])
end

local function IsInstantCastOverlayEnabled()
    local castBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.CastBar
    return castBarDB and castBarDB.ShowInstantCastOverlay
end

local function ClearCastBarPips()
    if not BCDM.CastBar then return end
    for _, pip in ipairs(BCDM.CastBar.Pips or {}) do
        pip:Hide()
        pip:SetParent(nil)
    end
    BCDM.CastBar.Pips = {}
end

local function StopInstantCastOverlay()
    if not BCDM.CastBar then return end
    BCDM.CastBar.InstantCastActive = nil
    BCDM.CastBar.InstantCastStartTime = nil
    BCDM.CastBar.InstantCastDuration = nil
    BCDM.CastBar.InstantCastSpellID = nil
end

local function HideCastBarDisplay()
    if not BCDM.CastBar then return end
    StopInstantCastOverlay()
    ApplyDefaultCastBarBackdropColour()
    if BCDM.CastBar.Status.SetReverseFill then
        BCDM.CastBar.Status:SetReverseFill(false)
    end
    BCDM.CastBar:Hide()
    BCDM.CastBar:SetScript("OnUpdate", nil)
    ClearCastBarPips()
end

local function GetSpellCooldownCompat(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if type(info) == "table" then
            return info.startTime or 0, info.duration or 0, info.isEnabled
        end
    end

    if GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end

    return 0, 0, 0
end

local function GetCurrentGCDDuration()
    local startTime, duration = GetSpellCooldownCompat(GCD_DUMMY_SPELL_ID)
    if type(startTime) ~= "number" or type(duration) ~= "number" then return nil end
    if startTime <= 0 or duration <= 0 then return nil end
    return duration
end

local function ResolveInstantCastDisplayInfo(spellID)
    if not spellID then return nil end

    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if type(spellInfo) ~= "table" or spellInfo.castTime ~= 0 then
        return nil
    end

    local duration = GetCurrentGCDDuration()
    if not duration or duration <= 0 then
        local _, baseGCDMS = GetSpellBaseCooldown(spellID)
        if type(baseGCDMS) == "number" and baseGCDMS > 0 then
            duration = baseGCDMS / 1000
        end
    end

    if not duration or duration <= 0 then
        return nil
    end

    return duration, spellInfo.name or "", spellInfo.iconID
end

local function StartInstantCastOverlay(spellID)
    if not (BCDM.CastBar and IsInstantCastOverlayEnabled()) then return end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

    local duration, spellName, spellIcon = ResolveInstantCastDisplayInfo(spellID)
    if not duration then return end

    ClearCastBarPips()
    ApplyInstantCastStatusColour()
    ApplyInstantCastBackdropColour()

    BCDM.CastBar.InstantCastActive = true
    BCDM.CastBar.InstantCastStartTime = GetTime()
    BCDM.CastBar.InstantCastDuration = duration
    BCDM.CastBar.InstantCastSpellID = spellID

    BCDM.CastBar.Status:SetMinMaxValues(0, duration)
    SetBarValue(BCDM.CastBar.Status, 0)
    if BCDM.CastBar.Status.SetReverseFill then
        BCDM.CastBar.Status:SetReverseFill(true)
    end
    BCDM.CastBar.SpellNameText:SetText(GetDisplayCastText(spellName, BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
    BCDM.CastBar.Icon:SetTexture(spellIcon or nil)
    BCDM.CastBar:SetScript("OnUpdate", function()
        local elapsed = GetTime() - (BCDM.CastBar.InstantCastStartTime or 0)
        local totalDuration = BCDM.CastBar.InstantCastDuration or 0
        local remaining = totalDuration - elapsed

        if remaining <= 0 then
            HideCastBarDisplay()
            return
        end

        SetBarValue(BCDM.CastBar.Status, elapsed)
        if remaining < 5 then
            BCDM.CastBar.CastTimeText:SetText(string.format("%.1f", remaining))
        else
            BCDM.CastBar.CastTimeText:SetText(string.format("%.0f", remaining))
        end
    end)
    BCDM.CastBar:Show()
end

local function HasSecondaryPowerForCurrentSpec()
    local class = select(2, UnitClass("player"))
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)
    local secondaryPowerBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.SecondaryPowerBar
    local showMana = secondaryPowerBarDB and (secondaryPowerBarDB.ShowMana or secondaryPowerBarDB.ShowManaBar)

    if class == "MONK" then
        return specID == 268 or specID == 269
    elseif class == "ROGUE" then
        return true
    elseif class == "DRUID" then
        return GetShapeshiftFormID() == 1
    elseif class == "PALADIN" then
        return true
    elseif class == "WARLOCK" then
        return true
    elseif class == "MAGE" then
        return specID == 62
    elseif class == "EVOKER" then
        return true
    elseif class == "DEATHKNIGHT" then
        return true
    elseif class == "DEMONHUNTER" then
        return specID == 1480 or specID == 581
    elseif class == "SHAMAN" then
        return specID == 263 or (specID == 262 and showMana)
    elseif class == "PRIEST" then
        return specID == 258 and showMana
    elseif class == "WARRIOR" then
        return specID == 72
    end

    return false
end

local function ResolveCastBarAnchorParentName()
    local CastBarDB = BCDM.db.profile.CastBar
    if CastBarDB.Layout[2] == "ACTIVE_RESOURCE" then
        if HasSecondaryPowerForCurrentSpec() then
            return "BCDM_SecondaryPowerBar"
        end
        return "BCDM_PowerBar"
    end
    return CastBarDB.Layout[2]
end

local function CreatePips(empoweredStages)
    if not BCDM.CastBar then return end

    ClearCastBarPips()

    local totalWidth = BCDM.CastBar.Status:GetWidth()
    local cumulativePercentage = 0

    for i, stageProportion in ipairs(empoweredStages) do
        if i < #empoweredStages then
            cumulativePercentage = cumulativePercentage + stageProportion
            local empoweredPip = BCDM.CastBar.Status:CreateTexture(nil, "OVERLAY")
            empoweredPip:SetColorTexture(1, 1, 1, 1)
            local xPos = totalWidth * cumulativePercentage
            empoweredPip:SetSize(1, BCDM.CastBar.Status:GetHeight() - 2)
            empoweredPip:SetPoint("LEFT", BCDM.CastBar.Status, "LEFT", xPos, 0)
            table.insert(BCDM.CastBar.Pips, empoweredPip)
            empoweredPip:Show()
        end
    end
end

local function UpdateCastBarValues(self, event, unit, _, spellID)
    if not BCDM.CastBar then return end

    local EMPOWERED_CAST_START = {
        UNIT_SPELLCAST_EMPOWER_START = true,
    }

    local CAST_START = {
        UNIT_SPELLCAST_START = true,
        UNIT_SPELLCAST_INTERRUPTIBLE = true,
        UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
        UNIT_SPELLCAST_SENT = true,
    }

    local CAST_STOP = {
        UNIT_SPELLCAST_STOP = true,
        UNIT_SPELLCAST_CHANNEL_STOP = true,
        UNIT_SPELLCAST_INTERRUPTED = true,
        UNIT_SPELLCAST_EMPOWER_STOP = true,
    }

    local CHANNEL_START = {
        UNIT_SPELLCAST_CHANNEL_START = true,
    }

    if CAST_START[event] then
        StopInstantCastOverlay()
        if BCDM.CastBar.Status.SetReverseFill then
            BCDM.CastBar.Status:SetReverseFill(false)
        end
        lastStartedSpellID = spellID
        lastStartedWasRealCast = true
        ApplyCastBarStatusColour(false)
        local castDuration = UnitCastingDuration("player")
        if not castDuration then return end
        BCDM.CastBar.Status:SetTimerDuration(castDuration, 0)
        BCDM.CastBar.SpellNameText:SetText(GetDisplayCastText(UnitCastingInfo("player"), BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
        BCDM.CastBar.Icon:SetTexture(select(3, UnitCastingInfo("player")) or nil)
        BCDM.CastBar:SetScript("OnUpdate", function()
            local remainingDuration = castDuration:GetRemainingDuration()
            if remainingDuration < 5 then
                BCDM.CastBar.CastTimeText:SetText(string.format("%.1f", remainingDuration))
            else
                BCDM.CastBar.CastTimeText:SetText(string.format("%.0f", remainingDuration))
            end
            SetBarValue(BCDM.CastBar.Status, remainingDuration)
        end)
        BCDM.CastBar:Show()
    elseif EMPOWERED_CAST_START[event] then
        StopInstantCastOverlay()
        if BCDM.CastBar.Status.SetReverseFill then
            BCDM.CastBar.Status:SetReverseFill(false)
        end
        lastStartedSpellID = spellID
        lastStartedWasRealCast = true
		local isEmpowered = select(9, UnitChannelInfo("player"))
        local empoweredStages = UnitEmpoweredStagePercentages("player")
        if isEmpowered then
            ApplyCastBarStatusColour(true)
            local empowerCastDuration = UnitEmpoweredChannelDuration("player")
            CreatePips(empoweredStages)
            BCDM.CastBar.Status:SetTimerDuration(empowerCastDuration, 0)
            BCDM.CastBar.SpellNameText:SetText(GetDisplayCastText(UnitChannelInfo("player"), BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
            BCDM.CastBar.Icon:SetTexture(select(3, UnitChannelInfo("player")) or nil)
            BCDM.CastBar:SetScript("OnUpdate", function()
                local remainingDuration = empowerCastDuration:GetRemainingDuration()
                if remainingDuration < 5 then
                    BCDM.CastBar.CastTimeText:SetText(string.format("%.1f", remainingDuration))
                else
                    BCDM.CastBar.CastTimeText:SetText(string.format("%.0f", remainingDuration))
                end
                SetBarValue(BCDM.CastBar.Status, remainingDuration)
            end)
            BCDM.CastBar:Show()
        end
    elseif CHANNEL_START[event] then
        StopInstantCastOverlay()
        if BCDM.CastBar.Status.SetReverseFill then
            BCDM.CastBar.Status:SetReverseFill(false)
        end
        lastStartedSpellID = spellID
        lastStartedWasRealCast = true
        ApplyCastBarStatusColour(true)
        local channelDuration = UnitChannelDuration("player")
        if not channelDuration then return end
        BCDM.CastBar.Status:SetTimerDuration(channelDuration, 0)
        BCDM.CastBar.Status:SetMinMaxValues(0, channelDuration:GetTotalDuration())
        BCDM.CastBar.SpellNameText:SetText(GetDisplayCastText(UnitChannelInfo("player"), BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
        BCDM.CastBar.Icon:SetTexture(select(3, UnitChannelInfo("player")) or nil)
        BCDM.CastBar:SetScript("OnUpdate", function()
            local remainingDuration = channelDuration:GetRemainingDuration()
            SetBarValue(BCDM.CastBar.Status, remainingDuration)
            if remainingDuration < 5 then
                BCDM.CastBar.CastTimeText:SetText(string.format("%.1f", remainingDuration))
            else
                BCDM.CastBar.CastTimeText:SetText(string.format("%.0f", remainingDuration))
            end
        end)
        BCDM.CastBar:Show()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not IsInstantCastOverlayEnabled() then
            lastStartedSpellID = nil
            lastStartedWasRealCast = false
            return
        end

        if lastStartedWasRealCast and lastStartedSpellID == spellID then
            lastStartedSpellID = nil
            lastStartedWasRealCast = false
            return
        end

        lastStartedSpellID = nil
        lastStartedWasRealCast = false

        local now = GetTime()
        if BCDM.CastBar.LastInstantCastTriggerTime and (now - BCDM.CastBar.LastInstantCastTriggerTime) < INSTANT_CAST_RETRIGGER_DEBOUNCE then
            if BCDM.CastBar.LastInstantCastTriggerSpellID == spellID then
                return
            end
        end

        if BCDM.CastBar.InstantCastActive and BCDM.CastBar.InstantCastStartTime and BCDM.CastBar.InstantCastDuration then
            local overlayEndsAt = BCDM.CastBar.InstantCastStartTime + BCDM.CastBar.InstantCastDuration
            if now < (overlayEndsAt - 0.05) then
                return
            end
        end

        BCDM.CastBar.LastInstantCastTriggerTime = now
        BCDM.CastBar.LastInstantCastTriggerSpellID = spellID

        C_Timer.After(0, function()
            if not BCDM.CastBar then return end
            if not IsInstantCastOverlayEnabled() then return end
            if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
            StartInstantCastOverlay(spellID)
        end)
    elseif CAST_STOP[event] then
        lastStartedSpellID = nil
        lastStartedWasRealCast = false
        if BCDM.CastBar.InstantCastActive then
            return
        end
        if BCDM.CastBar.Status.SetReverseFill then
            BCDM.CastBar.Status:SetReverseFill(false)
        end
        ApplyCastBarStatusColour(false)
        HideCastBarDisplay()
    end
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end  BCDM:UpdateCastBarWidth() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end  BCDM:UpdateCastBarWidth() end)
end

function BCDM:CreateCastBar()
    local GeneralDB = BCDM.db.profile.General
    local CastBarDB = BCDM.db.profile.CastBar

    SetHooks()

    local CastBar = CreateFrame("Frame", "BCDM_CastBar", UIParent, "BackdropTemplate")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    CastBar.Pips = {}
    CastBar.InstantCastActive = nil
    CastBar.LastInstantCastTriggerTime = nil
    CastBar.LastInstantCastTriggerSpellID = nil


    CastBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        CastBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        CastBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    CastBar:SetBackdropColor(CastBarDB.BackgroundColour[1], CastBarDB.BackgroundColour[2], CastBarDB.BackgroundColour[3], CastBarDB.BackgroundColour[4])
    CastBar:SetSize(CastBarDB.Width, CastBarDB.Height)
    local anchorParentName = ResolveCastBarAnchorParentName()
    CastBar:SetPoint(CastBarDB.Layout[1], _G[anchorParentName] or UIParent, CastBarDB.Layout[3], CastBarDB.Layout[4], CastBarDB.Layout[5])
    CastBar:SetFrameStrata(CastBarDB.FrameStrata or "LOW")

    if CastBarDB.MatchWidthOfAnchor then
        ApplyCachedAnchorWidth(CastBar, anchorParentName, CastBarDB.Width)
    end

    CastBar.Icon = CastBar:CreateTexture(nil, "OVERLAY")
    CastBar.Icon:SetSize(CastBarDB.Height, CastBarDB.Height)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    CastBar.Icon:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)

    CastBar.Status = CreateFrame("StatusBar", nil, CastBar)
    CastBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    if CastBar.Status.SetReverseFill then
        CastBar.Status:SetReverseFill(false)
    end
    if UnitChannelInfo("player") then
        CastBar.Status:SetStatusBarColor(FetchCastBarChannelColour())
    else
        CastBar.Status:SetStatusBarColor(FetchCastBarColour())
    end
    CastBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
    CastBar.Status:SetValue(UnitPower("player"))

    if CastBarDB.Icon.Enabled == false then
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "LEFT" then
        CastBar.Icon:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMLEFT", CastBar, "BOTTOMLEFT", borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar.Icon, "TOPRIGHT", 0, 0)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "RIGHT" then
        CastBar.Icon:SetPoint("TOPRIGHT", CastBar, "TOPRIGHT", -borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar.Icon, "BOTTOMLEFT", 0, 0)
    end

    CastBar.SpellNameText = CastBar.Status:CreateFontString(nil, "OVERLAY")
    CastBar.SpellNameText:SetFont(BCDM.Media.Font, CastBarDB.Text.SpellName.FontSize, GeneralDB.Fonts.FontFlag)
    CastBar.SpellNameText:SetTextColor(CastBarDB.Text.SpellName.Colour[1], CastBarDB.Text.SpellName.Colour[2], CastBarDB.Text.SpellName.Colour[3], 1)
    CastBar.SpellNameText:SetPoint(CastBarDB.Text.SpellName.Layout[1], CastBar.Status, CastBarDB.Text.SpellName.Layout[2], CastBarDB.Text.SpellName.Layout[3], CastBarDB.Text.SpellName.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        CastBar.SpellNameText:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        CastBar.SpellNameText:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        CastBar.SpellNameText:SetShadowColor(0, 0, 0, 0)
        CastBar.SpellNameText:SetShadowOffset(0, 0)
    end
    CastBar.SpellNameText:SetText("")

    CastBar.CastTimeText = CastBar.Status:CreateFontString(nil, "OVERLAY")
    CastBar.CastTimeText:SetFont(BCDM.Media.Font, CastBarDB.Text.CastTime.FontSize, GeneralDB.Fonts.FontFlag)
    CastBar.CastTimeText:SetTextColor(CastBarDB.Text.CastTime.Colour[1], CastBarDB.Text.CastTime.Colour[2], CastBarDB.Text.CastTime.Colour[3], 1)
    CastBar.CastTimeText:SetPoint(CastBarDB.Text.CastTime.Layout[1], CastBar.Status, CastBarDB.Text.CastTime.Layout[2], CastBarDB.Text.CastTime.Layout[3], CastBarDB.Text.CastTime.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        CastBar.CastTimeText:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        CastBar.CastTimeText:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        CastBar.CastTimeText:SetShadowColor(0, 0, 0, 0)
        CastBar.CastTimeText:SetShadowOffset(0, 0)
    end
    CastBar.CastTimeText:SetText("")

    BCDM.CastBar = CastBar

    if CastBarDB.Enabled then
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")

        CastBar:SetScript("OnEvent", UpdateCastBarValues)

        if CastBarDB.Icon.Enabled then CastBar.Icon:Show() else CastBar.Icon:Hide() end

        HideCastBarDisplay()
        if PlayerCastingBarFrame and PlayerCastingBarFrame.UnregisterAllEvents then
            PlayerCastingBarFrame:UnregisterAllEvents()
        end
    end
end

function BCDM:UpdateCastBar()
    local GeneralDB = BCDM.db.profile.General
    local CastBarDB = BCDM.db.profile.CastBar
    local CastBar = BCDM.CastBar
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    if not CastBar then return end

    BCDM.CastBar:SetBackdropColor(CastBarDB.BackgroundColour[1], CastBarDB.BackgroundColour[2], CastBarDB.BackgroundColour[3], CastBarDB.BackgroundColour[4])
    BCDM.CastBar:SetSize(CastBarDB.Width, CastBarDB.Height)
    BCDM.CastBar:ClearAllPoints()
    local anchorParentName = ResolveCastBarAnchorParentName()
    BCDM.CastBar:SetPoint(CastBarDB.Layout[1], _G[anchorParentName] or UIParent, CastBarDB.Layout[3], CastBarDB.Layout[4], CastBarDB.Layout[5])
    BCDM.CastBar:SetFrameStrata(CastBarDB.FrameStrata or "LOW")
    CastBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        CastBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        CastBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    BCDM.CastBar:SetBackdropColor(CastBarDB.BackgroundColour[1], CastBarDB.BackgroundColour[2], CastBarDB.BackgroundColour[3], CastBarDB.BackgroundColour[4])

    if CastBar.Status.SetReverseFill then
        CastBar.Status:SetReverseFill(CastBar.InstantCastActive and true or false)
    end

    if CastBar.InstantCastActive then
        ApplyInstantCastStatusColour()
        ApplyInstantCastBackdropColour()
    else
        ApplyDefaultCastBarBackdropColour()
        ApplyCastBarStatusColour(UnitChannelInfo("player") ~= nil)
    end
    BCDM.CastBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)

    if CastBarDB.MatchWidthOfAnchor then
        ApplyCachedAnchorWidth(CastBar, anchorParentName, CastBarDB.Width)
    end

    CastBar.Icon:SetSize(CastBarDB.Height, CastBarDB.Height)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    CastBar.Icon:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)

    CastBar.Icon:ClearAllPoints()
    if CastBarDB.Icon.Enabled == false then
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "LEFT" then
        CastBar.Icon:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMLEFT", CastBar, "BOTTOMLEFT", borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar.Icon, "TOPRIGHT", 0, 0)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "RIGHT" then
        CastBar.Icon:SetPoint("TOPRIGHT", CastBar, "TOPRIGHT", -borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar.Icon, "BOTTOMLEFT", 0, 0)
    end

    CastBar.SpellNameText:SetFont(BCDM.Media.Font, CastBarDB.Text.SpellName.FontSize, BCDM.db.profile.General.Fonts.FontFlag)
    CastBar.SpellNameText:SetTextColor(CastBarDB.Text.SpellName.Colour[1], CastBarDB.Text.SpellName.Colour[2], CastBarDB.Text.SpellName.Colour[3], 1)
    CastBar.SpellNameText:ClearAllPoints()
    CastBar.SpellNameText:SetPoint(CastBarDB.Text.SpellName.Layout[1], CastBar.Status, CastBarDB.Text.SpellName.Layout[2], CastBarDB.Text.SpellName.Layout[3], CastBarDB.Text.SpellName.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        CastBar.SpellNameText:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        CastBar.SpellNameText:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        CastBar.SpellNameText:SetShadowColor(0, 0, 0, 0)
        CastBar.SpellNameText:SetShadowOffset(0, 0)
    end

    CastBar.CastTimeText:SetFont(BCDM.Media.Font, CastBarDB.Text.CastTime.FontSize, BCDM.db.profile.General.Fonts.FontFlag)
    CastBar.CastTimeText:SetTextColor(CastBarDB.Text.CastTime.Colour[1], CastBarDB.Text.CastTime.Colour[2], CastBarDB.Text.CastTime.Colour[3], 1)
    CastBar.CastTimeText:ClearAllPoints()
    CastBar.CastTimeText:SetPoint(CastBarDB.Text.CastTime.Layout[1], CastBar.Status, CastBarDB.Text.CastTime.Layout[2], CastBarDB.Text.CastTime.Layout[3], CastBarDB.Text.CastTime.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        CastBar.CastTimeText:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        CastBar.CastTimeText:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        CastBar.CastTimeText:SetShadowColor(0, 0, 0, 0)
        CastBar.CastTimeText:SetShadowOffset(0, 0)
    end

    if CastBarDB.Enabled then
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        CastBar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")

        CastBar:SetScript("OnEvent", UpdateCastBarValues)

        if CastBarDB.Icon.Enabled then CastBar.Icon:Show() else CastBar.Icon:Hide() end
        if not CastBarDB.ShowInstantCastOverlay and CastBar.InstantCastActive then
            HideCastBarDisplay()
        end
        local isCasting = UnitCastingInfo("player") or UnitChannelInfo("player") or CastBar.InstantCastActive
        if not isCasting then
            HideCastBarDisplay()
        end
        if PlayerCastingBarFrame and PlayerCastingBarFrame.UnregisterAllEvents then
            PlayerCastingBarFrame:UnregisterAllEvents()
        end
    else
        HideCastBarDisplay()
        CastBar:SetScript("OnEvent", nil)
        CastBar:UnregisterAllEvents()
    end
    if BCDM.CAST_BAR_TEST_MODE then BCDM:CreateTestCastBar() end
end

function BCDM:CreateTestCastBar()
    local CastBarDB = BCDM.db.profile.CastBar
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    if not BCDM.CastBar then return end
    if BCDM.CAST_BAR_TEST_MODE then
        BCDM.CastBar:SetFrameStrata(CastBarDB.FrameStrata or "LOW")
        BCDM.CastBar.SpellNameText:SetText(string.sub("Ethereal Portal", 1, BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
        BCDM.CastBar.Icon:SetTexture("Interface\\Icons\\ability_mage_netherwindpresence")
        BCDM.CastBar.Status:SetMinMaxValues(0, 10)
        BCDM.CastBar.Status:SetValue(5)
        BCDM.CastBar.CastTimeText:SetText("5.0")
        BCDM.CastBar.Icon:ClearAllPoints()
        if CastBarDB.Icon.Enabled == false then
            BCDM.CastBar.Status:SetPoint("TOPLEFT", BCDM.CastBar, "TOPLEFT", borderSize, -borderSize)
            BCDM.CastBar.Status:SetPoint("BOTTOMRIGHT", BCDM.CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
        elseif CastBarDB.Icon.Layout == "LEFT" then
            BCDM.CastBar.Icon:SetPoint("TOPLEFT", BCDM.CastBar, "TOPLEFT", borderSize, -borderSize)
            BCDM.CastBar.Icon:SetPoint("BOTTOMLEFT", BCDM.CastBar, "BOTTOMLEFT", borderSize, borderSize)
            BCDM.CastBar.Status:SetPoint("TOPLEFT", BCDM.CastBar.Icon, "TOPRIGHT", 0, 0)
            BCDM.CastBar.Status:SetPoint("BOTTOMRIGHT", BCDM.CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
        elseif CastBarDB.Icon.Layout == "RIGHT" then
            BCDM.CastBar.Icon:SetPoint("TOPRIGHT", BCDM.CastBar, "TOPRIGHT", -borderSize, -borderSize)
            BCDM.CastBar.Icon:SetPoint("BOTTOMRIGHT", BCDM.CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
            BCDM.CastBar.Status:SetPoint("TOPLEFT", BCDM.CastBar, "TOPLEFT", borderSize, -borderSize)
            BCDM.CastBar.Status:SetPoint("BOTTOMRIGHT", BCDM.CastBar.Icon, "BOTTOMLEFT", 0, 0)
        end
        if CastBarDB.Enabled then BCDM.CastBar:Show() else BCDM.CastBar:Hide() end
    else
        BCDM.CastBar:Hide()
    end
end

function BCDM:UpdateCastBarWidth()
    local CastBarDB = BCDM.db.profile.CastBar
    local CastBar = BCDM.CastBar
    if CastBarDB.Enabled and CastBarDB.MatchWidthOfAnchor then
        ApplyCachedAnchorWidth(CastBar, ResolveCastBarAnchorParentName(), CastBarDB.Width)
    end
end
