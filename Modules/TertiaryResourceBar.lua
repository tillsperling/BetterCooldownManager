local _, BCDM = ...

local tertiaryBarUpdateThrottle = 0.03

local function HasAuraInstanceID(auraInstanceID)
    if auraInstanceID == nil then return false end
    local ok, result = pcall(function() return auraInstanceID == 0 end)
    if not ok then
        return true
    end
    return not result
end

local function ResolveTrackedBuffFrame(cooldownID)
    if not cooldownID or cooldownID <= 0 then return end
    local viewers = {
        _G["BuffBarCooldownViewer"],
        _G["BuffIconCooldownViewer"],
    }
    for _, viewer in ipairs(viewers) do
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child then
                    local frameCooldownID = child.cooldownID
                    if not frameCooldownID and child.cooldownInfo then
                        frameCooldownID = child.cooldownInfo.cooldownID
                    end
                    if not frameCooldownID and child.Icon and child.Icon.cooldownID then
                        frameCooldownID = child.Icon.cooldownID
                    end
                    if frameCooldownID == cooldownID then
                        return child
                    end
                end
            end
        end
    end
end

local function SetTertiaryTrackedSourceVisibility(cooldownID, hideSource)
    BCDM._TertiaryHiddenSourceFrames = BCDM._TertiaryHiddenSourceFrames or {}
    local hiddenFrames = BCDM._TertiaryHiddenSourceFrames

    for frame in pairs(hiddenFrames) do
        if frame and frame.SetAlpha then
            frame:SetAlpha(frame._bcdmTertiaryPrevAlpha or 1)
        end
        if frame then
            frame._bcdmTertiaryPrevAlpha = nil
        end
        hiddenFrames[frame] = nil
    end

    if not hideSource or not cooldownID or cooldownID <= 0 then return end

    local viewers = {
        _G["BuffBarCooldownViewer"],
        _G["BuffIconCooldownViewer"],
    }

    for _, viewer in ipairs(viewers) do
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child then
                    local frameCooldownID = child.cooldownID
                    if not frameCooldownID and child.cooldownInfo then
                        frameCooldownID = child.cooldownInfo.cooldownID
                    end
                    if not frameCooldownID and child.Icon and child.Icon.cooldownID then
                        frameCooldownID = child.Icon.cooldownID
                    end

                    if frameCooldownID == cooldownID then
                        if child._bcdmTertiaryPrevAlpha == nil and child.GetAlpha then
                            child._bcdmTertiaryPrevAlpha = child:GetAlpha()
                        end
                        if child.SetAlpha then
                            child:SetAlpha(0)
                        end
                        hiddenFrames[child] = true
                    end
                end
            end
        end
    end
end

local function ResolveTertiaryAuraData(db)
    local cdmFrame = ResolveTrackedBuffFrame(db.CooldownID or 0)
    if not cdmFrame then return end

    local state = BCDM._TertiaryResourceState or {}
    BCDM._TertiaryResourceState = state

    local sourceSpellID = tonumber(db.SourceSpellID) or 0
    local auraData
    local auraDataUnit = cdmFrame.auraDataUnit or "player"
    local auraInstanceID = cdmFrame.auraInstanceID

    if sourceSpellID > 0 then
        local fromFrameAuraData
        if HasAuraInstanceID(auraInstanceID) then
            fromFrameAuraData = C_UnitAuras.GetAuraDataByAuraInstanceID(auraDataUnit, auraInstanceID)
        end

        if fromFrameAuraData then
            auraData = fromFrameAuraData
            state.trackedAuraInstanceID = auraInstanceID
            state.trackedAuraUnit = auraDataUnit
        elseif HasAuraInstanceID(state.trackedAuraInstanceID) then
            local cachedUnit = state.trackedAuraUnit or "player"
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, state.trackedAuraInstanceID)
            auraDataUnit = cachedUnit
            auraInstanceID = state.trackedAuraInstanceID
            if not auraData then
                state.trackedAuraInstanceID = nil
                state.trackedAuraUnit = nil
            end
        end
    else
        if HasAuraInstanceID(auraInstanceID) then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(auraDataUnit, auraInstanceID)
        end
    end

    if not auraData then return end

    local remaining
    if C_UnitAuras.GetAuraDurationRemaining and HasAuraInstanceID(auraInstanceID) then
        remaining = C_UnitAuras.GetAuraDurationRemaining(auraDataUnit, auraInstanceID)
    end

    if remaining == nil and cdmFrame and cdmFrame.Bar and cdmFrame.Bar.GetValue then
        remaining = cdmFrame.Bar:GetValue()
    end

    local autoDuration = db.AutoDuration ~= false
    local maxDuration = tonumber(db.MaxDuration) or 30
    if autoDuration and cdmFrame and cdmFrame.Bar and cdmFrame.Bar.GetMinMaxValues then
        local _, barMax = cdmFrame.Bar:GetMinMaxValues()
        if barMax ~= nil then
            maxDuration = barMax
        end
    end

    local stackText
    if cdmFrame and cdmFrame.Applications and cdmFrame.Applications.Applications and cdmFrame.Applications.Applications.GetText then
        local okText, value = pcall(cdmFrame.Applications.Applications.GetText, cdmFrame.Applications.Applications)
        if okText and value then
            stackText = value
        end
    end
    if not stackText and cdmFrame and cdmFrame.ChargeCount and cdmFrame.ChargeCount.Current and cdmFrame.ChargeCount.Current.GetText then
        local okText, value = pcall(cdmFrame.ChargeCount.Current.GetText, cdmFrame.ChargeCount.Current)
        if okText and value then
            stackText = value
        end
    end
    if not stackText and auraData then
        local function TryAuraFieldText(field)
            local okField, rawValue = pcall(function() return auraData[field] end)
            if not okField or rawValue == nil then return end
            local okText, textValue = pcall(tostring, rawValue)
            if okText and textValue then
                return textValue
            end
        end
        stackText = TryAuraFieldText("applications") or TryAuraFieldText("stackCount") or TryAuraFieldText("charges")
    end

    return remaining, maxDuration, stackText
end

local function UpdateTertiaryResourceBarValue(self, elapsed)
    self._bcdmElapsed = (self._bcdmElapsed or 0) + elapsed
    if self._bcdmElapsed < tertiaryBarUpdateThrottle then return end
    self._bcdmElapsed = 0

    local db = BCDM:GetActiveTertiaryResourceBarDB(true)
    if not db or not db.Enabled then return end
    if BCDM:ShouldHideCDMWhileMounted() then return end

    SetTertiaryTrackedSourceVisibility(db.CooldownID or 0, db.HideTrackedSource == true)

    local remaining, maxDuration, stackText = ResolveTertiaryAuraData(db)
    if remaining and maxDuration then
        local okRange = pcall(self.Status.SetMinMaxValues, self.Status, 0, maxDuration)
        local okValue = pcall(self.Status.SetValue, self.Status, remaining)
        if not okRange or not okValue then
            self.Status:SetMinMaxValues(0, 1)
            self.Status:SetValue(0)
        end
        if not self:IsShown() then
            self:Show()
        end
        if self.StackText then
            local stackTextDB = db.StackText or {}
            if stackTextDB.Enabled ~= false and stackText then
                self.StackText:SetText(stackText)
                self.StackText:Show()
            else
                self.StackText:SetText("")
                self.StackText:Hide()
            end
        end
    else
        self.Status:SetMinMaxValues(0, 1)
        self.Status:SetValue(0)
        if db.HideWhenInactive then
            self:Hide()
        else
            self:Show()
        end
        if self.StackText then
            self.StackText:SetText("")
            self.StackText:Hide()
        end
    end
end

function BCDM:BuildTrackedBuffSourceList()
    local labels, values = {}, {}
    local seen = {}
    local function AddCooldownID(cooldownID)
        if not cooldownID or cooldownID <= 0 or seen[cooldownID] then return end
        seen[cooldownID] = true
        local label = tostring(cooldownID)
        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
            if info then
                local spellID = info.overrideSpellID or info.spellID
                local name = spellID and C_Spell.GetSpellName(spellID)
                if name and name ~= "" then
                    label = name .. " (" .. cooldownID .. ")"
                end
            end
        end
        labels[cooldownID] = label
        table.insert(values, cooldownID)
    end

    local viewers = {
        _G["BuffBarCooldownViewer"],
        _G["BuffIconCooldownViewer"],
    }
    for _, viewer in ipairs(viewers) do
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child then
                    local cooldownID = child.cooldownID
                    if not cooldownID and child.cooldownInfo then
                        cooldownID = child.cooldownInfo.cooldownID
                    end
                    if not cooldownID and child.Icon and child.Icon.cooldownID then
                        cooldownID = child.Icon.cooldownID
                    end
                    AddCooldownID(cooldownID)
                end
            end
        end
    end
    table.sort(values)
    return labels, values
end

function BCDM:UpdateTertiaryResourceBar()
    local db = BCDM:GetActiveTertiaryResourceBarDB(true)
    if not db then return end

    BCDM.TertiaryResourceBar = BCDM.TertiaryResourceBar or CreateFrame("Frame", "BCDM_TertiaryResourceBar", UIParent, "BackdropTemplate")
    local tertiaryBar = BCDM.TertiaryResourceBar

    if not tertiaryBar.Status then
        tertiaryBar.Status = CreateFrame("StatusBar", nil, tertiaryBar)
        tertiaryBar.Status:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        tertiaryBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    end
    if not tertiaryBar.StackTextFrame then
        tertiaryBar.StackTextFrame = CreateFrame("Frame", nil, tertiaryBar)
    end
    if not tertiaryBar.StackText then
        tertiaryBar.StackText = tertiaryBar.StackTextFrame:CreateFontString(nil, "OVERLAY")
    end
    if not tertiaryBar._bcdmStackTextFontInitialized then
        local fontFlag = (BCDM.db and BCDM.db.profile and BCDM.db.profile.General and BCDM.db.profile.General.Fonts and BCDM.db.profile.General.Fonts.FontFlag) or "OUTLINE"
        tertiaryBar.StackText:SetFont(BCDM.Media and BCDM.Media.Font or STANDARD_TEXT_FONT, 12, fontFlag)
        tertiaryBar._bcdmStackTextFontInitialized = true
    end

    if not db.Enabled then
        tertiaryBar:SetScript("OnUpdate", nil)
        SetTertiaryTrackedSourceVisibility(0, false)
        tertiaryBar.StackTextFrame:Hide()
        tertiaryBar.StackText:Hide()
        tertiaryBar:Hide()
        return
    end

    local anchorParentName = db.Layout and db.Layout[2] or "BCDM_SecondaryPowerBar"
    local anchorParent = anchorParentName == "NONE" and UIParent or _G[anchorParentName]
    tertiaryBar:ClearAllPoints()
    tertiaryBar:SetPoint(db.Layout[1], anchorParent or UIParent, db.Layout[3], db.Layout[4], db.Layout[5])
    tertiaryBar:SetHeight(db.Height)
    tertiaryBar:SetWidth(db.Width)

    if db.MatchWidthOfAnchor and anchorParent and anchorParent.GetWidth then
        local anchorWidth = anchorParent:GetWidth()
        if anchorWidth and anchorWidth > 0 then
            tertiaryBar:SetWidth(anchorWidth)
        end
    end

    tertiaryBar:SetFrameStrata(db.FrameStrata or "LOW")
    tertiaryBar:SetBackdropColor(db.BackgroundColour[1], db.BackgroundColour[2], db.BackgroundColour[3], db.BackgroundColour[4])
    tertiaryBar.Status:SetStatusBarTexture(BCDM.Media and BCDM.Media.Foreground or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    tertiaryBar.Status:SetStatusBarColor(db.ForegroundColour[1], db.ForegroundColour[2], db.ForegroundColour[3], db.ForegroundColour[4] or 1)

    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize or 1
    tertiaryBar.Status:ClearAllPoints()
    tertiaryBar.Status:SetPoint("TOPLEFT", tertiaryBar, "TOPLEFT", borderSize, -borderSize)
    tertiaryBar.Status:SetPoint("BOTTOMRIGHT", tertiaryBar, "BOTTOMRIGHT", -borderSize, borderSize)
    BCDM:AddBorder(tertiaryBar)

    local stackTextDB = db.StackText or {}
    stackTextDB.Layout = stackTextDB.Layout or {"CENTER", "CENTER", 0, 0}
    local stackTextLayout = stackTextDB.Layout
    local fontFlag = (BCDM.db and BCDM.db.profile and BCDM.db.profile.General and BCDM.db.profile.General.Fonts and BCDM.db.profile.General.Fonts.FontFlag) or "OUTLINE"
    tertiaryBar.StackTextFrame:ClearAllPoints()
    tertiaryBar.StackTextFrame:SetAllPoints(tertiaryBar.Status)
    tertiaryBar.StackTextFrame:SetFrameStrata(stackTextDB.FrameStrata or "HIGH")
    tertiaryBar.StackTextFrame:SetFrameLevel((tertiaryBar:GetFrameLevel() or 0) + 20)
    tertiaryBar.StackTextFrame:Show()
    tertiaryBar.StackText:SetFont(BCDM.Media and BCDM.Media.Font or STANDARD_TEXT_FONT, stackTextDB.FontSize or 12, fontFlag)
    tertiaryBar.StackText:SetDrawLayer("OVERLAY")
    tertiaryBar.StackText:ClearAllPoints()
    tertiaryBar.StackText:SetPoint(stackTextLayout[1] or "CENTER", tertiaryBar.StackTextFrame, stackTextLayout[2] or "CENTER", stackTextLayout[3] or 0, stackTextLayout[4] or 0)
    local stackTextColour = stackTextDB.Colour or {1, 1, 1, 1}
    tertiaryBar.StackText:SetTextColor(stackTextColour[1] or 1, stackTextColour[2] or 1, stackTextColour[3] or 1, stackTextColour[4] or 1)
    tertiaryBar.StackText:SetText("")
    tertiaryBar.StackText:Hide()

    tertiaryBar:SetScript("OnUpdate", UpdateTertiaryResourceBarValue)
    UpdateTertiaryResourceBarValue(tertiaryBar, tertiaryBarUpdateThrottle)
    SetTertiaryTrackedSourceVisibility(db.CooldownID or 0, db.HideTrackedSource == true)
end
