local _, BCDM = ...
local resizeTimer = nil
local trackedAuraCache = {}

-- Define tracked tertiary buffs per class/spec here.
local TERTIARY_TRACKED_BUFFS = {
    DEMONHUNTER = {
        [581] = 203819, -- Vengeance: Demon Spikes
    },
}

local function ResolveTrackedBuffSpellID()
    local class = select(2, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    if not class or not specID then return end
    local classTracking = TERTIARY_TRACKED_BUFFS[class]
    local spellID = classTracking and classTracking[specID]
    if spellID and spellID > 0 then
        return spellID
    end
end

local function FindPlayerAuraBySpellID(spellID)
    if not spellID or spellID <= 0 then return nil end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if auraData then
            return auraData
        end
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local name, _, applications, _, duration, expirationTime, _, _, _, foundSpellID =
            AuraUtil.FindAuraBySpellID(spellID, "player", "HELPFUL")
        if name then
            return {
                spellId = foundSpellID or spellID,
                applications = applications,
                duration = duration,
                expirationTime = expirationTime,
            }
        end
    end

    return nil
end

local function GetTrackedAuraData(spellID)
    local now = GetTime()
    local auraData = FindPlayerAuraBySpellID(spellID)
    if auraData then
        local duration = auraData.duration or 0
        local expirationTime = auraData.expirationTime or 0
        trackedAuraCache[spellID] = {
            duration = duration,
            expirationTime = expirationTime,
        }
        return auraData
    end

    local cached = trackedAuraCache[spellID]
    if cached and (cached.expirationTime or 0) > now then
        return cached
    end

    trackedAuraCache[spellID] = nil
    return nil
end

function BCDM:HasActiveTertiaryResource()
    local db = BCDM.db and BCDM.db.profile and BCDM.db.profile.TertiaryResourceBar
    if not db or not db.Enabled then return false end
    return ResolveTrackedBuffSpellID() ~= nil
end

local function UpdateTertiaryResourceBarValues()
    local bar = BCDM.TertiaryResourceBar
    local db = BCDM.db.profile.TertiaryResourceBar
    if not bar or not db then return end

    if not db.Enabled then
        bar:Hide()
        return
    end

    local trackedSpellID = ResolveTrackedBuffSpellID()
    bar:Show()
    bar.Status:SetMinMaxValues(0, 1)
    bar.Status:SetValue(0)
    bar.Status:SetStatusBarColor(db.ForegroundColour[1], db.ForegroundColour[2], db.ForegroundColour[3], db.ForegroundColour[4] or 1)

    if not trackedSpellID then return end

    local auraData = GetTrackedAuraData(trackedSpellID)
    if not auraData then return end

    local duration = auraData.duration or 0
    local expirationTime = auraData.expirationTime or 0
    local remaining = expirationTime - GetTime()

    if duration <= 0 or remaining <= 0 then return end

    bar.Status:SetMinMaxValues(0, duration)
    bar.Status:SetValue(remaining)
    bar.Status:SetStatusBarColor(db.ForegroundColour[1], db.ForegroundColour[2], db.ForegroundColour[3], db.ForegroundColour[4] or 1)
end

local function UpdateBarWidth()
    local bar = BCDM.TertiaryResourceBar
    local db = BCDM.db.profile.TertiaryResourceBar
    if not bar or not db or not db.MatchWidthOfAnchor then return end
    local anchorFrame = _G[db.Layout[2]]
    if not anchorFrame then return end

    if resizeTimer then
        resizeTimer:Cancel()
    end

    resizeTimer = C_Timer.After(0.5, function()
        if not bar or not db.MatchWidthOfAnchor then
            resizeTimer = nil
            return
        end
        bar:SetWidth(anchorFrame:GetWidth())
        resizeTimer = nil
    end)
end

function BCDM:CreateTertiaryResourceBar()
    local db = BCDM.db.profile.TertiaryResourceBar
    if not db then return end

    local bar = CreateFrame("Frame", "BCDM_TertiaryResourceBar", UIParent, "BackdropTemplate")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    bar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        bar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        bar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    bar:SetBackdropColor(db.BackgroundColour[1], db.BackgroundColour[2], db.BackgroundColour[3], db.BackgroundColour[4])
    bar:SetSize(db.Width, db.Height)
    bar:SetPoint(db.Layout[1], _G[db.Layout[2]] or UIParent, db.Layout[3], db.Layout[4], db.Layout[5])
    bar:SetFrameStrata(db.FrameStrata or "LOW")

    bar.Status = CreateFrame("StatusBar", nil, bar)
    bar.Status:SetPoint("TOPLEFT", bar, "TOPLEFT", borderSize, -borderSize)
    bar.Status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
    bar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    bar.Status:SetStatusBarColor(db.ForegroundColour[1], db.ForegroundColour[2], db.ForegroundColour[3], db.ForegroundColour[4] or 1)

    BCDM.TertiaryResourceBar = bar

    bar:UnregisterAllEvents()
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    bar:RegisterEvent("TRAIT_CONFIG_UPDATED")
    bar:RegisterEvent("UNIT_AURA")
    bar:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit and unit ~= "player" then return end
        UpdateTertiaryResourceBarValues()
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "TRAIT_CONFIG_UPDATED" then
            BCDM:UpdateCastBar()
        end
    end)

    bar:SetScript("OnUpdate", function()
        if not db.Enabled then return end
        UpdateTertiaryResourceBarValues()
    end)

    UpdateBarWidth()
    UpdateTertiaryResourceBarValues()
end

function BCDM:UpdateTertiaryResourceBar()
    local db = BCDM.db.profile.TertiaryResourceBar
    local bar = BCDM.TertiaryResourceBar
    if not db then return end
    if not bar then
        BCDM:CreateTertiaryResourceBar()
        return
    end

    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    bar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        bar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        bar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    bar:SetBackdropColor(db.BackgroundColour[1], db.BackgroundColour[2], db.BackgroundColour[3], db.BackgroundColour[4])
    bar:SetSize(db.Width, db.Height)
    bar:ClearAllPoints()
    bar:SetPoint(db.Layout[1], _G[db.Layout[2]] or UIParent, db.Layout[3], db.Layout[4], db.Layout[5])
    bar:SetFrameStrata(db.FrameStrata or "LOW")
    bar.Status:SetPoint("TOPLEFT", bar, "TOPLEFT", borderSize, -borderSize)
    bar.Status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
    bar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    bar.Status:SetStatusBarColor(db.ForegroundColour[1], db.ForegroundColour[2], db.ForegroundColour[3], db.ForegroundColour[4] or 1)

    UpdateBarWidth()
    UpdateTertiaryResourceBarValues()
end

function BCDM:UpdateTertiaryResourceBarWidth()
    UpdateBarWidth()
end
