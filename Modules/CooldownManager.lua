local _, BCDM = ...

local function ShouldSkin()
    if not BCDM.db.profile.CooldownManager.Enable then return false end
    if C_AddOns.IsAddOnLoaded("ElvUI") and ElvUI[1].private.skins.blizzard.cooldownManager then return false end
    if C_AddOns.IsAddOnLoaded("MasqueBlizzBars") then return false end
    return true
end

local function NudgeViewer(viewerName, xOffset, yOffset)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then return end
    local point, relativeTo, relativePoint, currentX, currentY = viewerFrame:GetPoint(1)
    viewerFrame:ClearAllPoints()
    viewerFrame:SetPoint(point, relativeTo, relativePoint, currentX + xOffset, currentY + yOffset)
end

local function FetchCooldownTextRegion(cooldown)
    if not cooldown then return end
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            return region
        end
    end
end

local function ApplyCooldownText(cooldownViewer)
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local CooldownTextDB = CooldownManagerDB.CooldownManager.General.CooldownText
    local Viewer = _G[cooldownViewer]
    if not Viewer then return end
    for _, icon in ipairs({ Viewer:GetChildren() }) do
        if icon and icon.Cooldown then
            local textRegion = FetchCooldownTextRegion(icon.Cooldown)
            if textRegion then
                if CooldownTextDB.ScaleByIconSize then
                    local iconWidth = icon:GetWidth()
                    local scaleFactor = iconWidth / 36
                    textRegion:SetFont(BCDM.Media.Font, CooldownTextDB.FontSize * scaleFactor, GeneralDB.Fonts.FontFlag)
                else
                    textRegion:SetFont(BCDM.Media.Font, CooldownTextDB.FontSize, GeneralDB.Fonts.FontFlag)
                end
                textRegion:SetTextColor(CooldownTextDB.Colour[1], CooldownTextDB.Colour[2], CooldownTextDB.Colour[3], 1)
                textRegion:ClearAllPoints()
                textRegion:SetPoint(CooldownTextDB.Layout[1], icon, CooldownTextDB.Layout[2], CooldownTextDB.Layout[3], CooldownTextDB.Layout[4])
                if GeneralDB.Fonts.Shadow.Enabled then
                    textRegion:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
                    textRegion:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
                else
                    textRegion:SetShadowColor(0, 0, 0, 0)
                    textRegion:SetShadowOffset(0, 0)
                end
            end
        end
    end
end

local ACTION_BAR_BUTTON_PREFIXES = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
    { prefix = "MultiBar5Button", count = 12 },
    { prefix = "MultiBar6Button", count = 12 },
    { prefix = "MultiBar7Button", count = 12 },
}

local function GetIconSpellID(iconFrame)
    if not iconFrame then return end
    if iconFrame.cooldownInfo then
        return iconFrame.cooldownInfo.overrideSpellID or iconFrame.cooldownInfo.spellID
    end
    if iconFrame.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(iconFrame.cooldownID)
        if info then
            return info.overrideSpellID or info.spellID
        end
    end
end

local function NormalizeKeybindText(key)
    if not key or key == "" or key == RANGE_INDICATOR or key == "●" then
        return ""
    end

    local text = key
    if GetBindingText then
        local bindingText = GetBindingText(key, "KEY_", true)
        if bindingText and bindingText ~= "" then
            text = bindingText
        end
    end

    local upperKey = text:upper()
    upperKey = upperKey:gsub("SHIFT%-", "S")
    upperKey = upperKey:gsub("META%-", "M")
    upperKey = upperKey:gsub("CTRL%-", "C")
    upperKey = upperKey:gsub("ALT%-", "A")
    upperKey = upperKey:gsub("STRG%-", "ST")
    upperKey = upperKey:gsub("MOUSE%s?WHEEL%s?UP", "MWU")
    upperKey = upperKey:gsub("MOUSE%s?WHEEL%s?DOWN", "MWD")
    upperKey = upperKey:gsub("MIDDLE%s?MOUSE", "MM")
    upperKey = upperKey:gsub("MOUSE%s?BUTTON%s?", "M")
    upperKey = upperKey:gsub("BUTTON", "M")
    upperKey = upperKey:gsub("%s+", "")
    upperKey = upperKey:gsub("%-", "")

    return upperKey
end

local function ResolveButtonKeybind(button)
    if not button then return "" end
    if button.HotKey and button.HotKey.GetText then
        local hotKeyText = button.HotKey:GetText()
        if hotKeyText and hotKeyText ~= "" then
            return hotKeyText
        end
    end
    if button.commandName and GetBindingKey then
        local key = GetBindingKey(button.commandName)
        if key then
            return key
        end
    end
    if button.config and button.config.keyBoundTarget and GetBindingKey then
        local key = GetBindingKey(button.config.keyBoundTarget)
        if key then
            return key
        end
    end
    return ""
end

local function AssignSpellKeybind(spellToKeybind, spellID, key)
    if not spellID or spellID == 0 then return end
    if spellToKeybind[spellID] then return end
    local normalized = NormalizeKeybindText(key)
    if normalized == "" then return end
    spellToKeybind[spellID] = normalized
end

local function AssignActionSlotKeybind(spellToKeybind, slot, key)
    if not slot or slot == 0 then return end
    local actionType, id, subType = GetActionInfo(slot)
    if actionType == "spell" then
        AssignSpellKeybind(spellToKeybind, id, key)
        return
    end
    if actionType == "macro" then
        if subType == "spell" then
            AssignSpellKeybind(spellToKeybind, id, key)
            return
        end
        local macroSpellID = GetMacroSpell(id)
        AssignSpellKeybind(spellToKeybind, macroSpellID, key)
    end
end

local function CollectKeybindsFromActionButtons(spellToKeybind)
    for _, bar in ipairs(ACTION_BAR_BUTTON_PREFIXES) do
        for i = 1, bar.count do
            local button = _G[bar.prefix .. i]
            if button and button.action then
                AssignActionSlotKeybind(spellToKeybind, button.action, ResolveButtonKeybind(button))
            end
        end
    end
end

local function CollectKeybindsFromDominos(spellToKeybind)
    if not DominosActionButton1 then return end
    for i = 1, 180 do
        local button = _G["DominosActionButton" .. i]
        if button and button.action then
            AssignActionSlotKeybind(spellToKeybind, button.action, ResolveButtonKeybind(button))
        end
    end
end

local function CollectKeybindsFromBartender(spellToKeybind)
    if not BT4Button1 then return end
    for i = 1, 180 do
        local button = _G["BT4Button" .. i]
        if button and button.action then
            AssignActionSlotKeybind(spellToKeybind, button.action, ResolveButtonKeybind(button))
        end
    end
end

local function CollectKeybindsFromElvUI(spellToKeybind)
    if not ElvUI_Bar1Button1 then return end
    for bar = 1, 15 do
        for buttonIndex = 1, 12 do
            local button = _G["ElvUI_Bar" .. bar .. "Button" .. buttonIndex]
            if button and button.action then
                AssignActionSlotKeybind(spellToKeybind, button.action, ResolveButtonKeybind(button))
            end
        end
    end
end

local function BuildSpellKeybindMap()
    local spellToKeybind = {}
    CollectKeybindsFromActionButtons(spellToKeybind)
    CollectKeybindsFromDominos(spellToKeybind)
    CollectKeybindsFromBartender(spellToKeybind)
    CollectKeybindsFromElvUI(spellToKeybind)
    return spellToKeybind
end

local function ResolveSpellKeybind(spellToKeybind, spellID)
    if not spellID or spellID == 0 then return "" end
    if spellToKeybind[spellID] then
        return spellToKeybind[spellID]
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID and spellToKeybind[overrideSpellID] then
            return spellToKeybind[overrideSpellID]
        end
    end
    if C_Spell and C_Spell.GetBaseSpell then
        local baseSpellID = C_Spell.GetBaseSpell(spellID)
        if baseSpellID and spellToKeybind[baseSpellID] then
            return spellToKeybind[baseSpellID]
        end
    end
    return ""
end

local function GetOrCreateKeybindText(icon)
    if icon.BCDMKeybindText then
        return icon.BCDMKeybindText
    end
    local keybindText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keybindText:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
    keybindText:SetTextColor(1, 1, 1, 1)
    keybindText:SetDrawLayer("OVERLAY", 7)
    icon.BCDMKeybindText = keybindText
    return keybindText
end

local function GetKeybindTextAnchor()
    local keybindSettings = BCDM.db.profile.CooldownManager.General.KeybindText or {}
    local anchor = keybindSettings.Anchor or "TOPRIGHT"
    if anchor == "TOPLEFT" then
        return "TOPLEFT", 2, -2
    end
    if anchor == "BOTTOMLEFT" then
        return "BOTTOMLEFT", 2, 2
    end
    if anchor == "BOTTOMRIGHT" then
        return "BOTTOMRIGHT", -2, 2
    end
    return "TOPRIGHT", -2, -2
end

local function ApplyKeybindTextStyling(keybindText, icon)
    if not keybindText then return end
    local generalSettings = BCDM.db.profile.General
    local keybindSettings = BCDM.db.profile.CooldownManager.General.KeybindText or {}
    local anchor, offsetX, offsetY = GetKeybindTextAnchor()
    local fontSize = keybindSettings.FontSize or 12
    keybindText:ClearAllPoints()
    keybindText:SetPoint(anchor, icon, anchor, offsetX, offsetY)
    keybindText:SetFont(BCDM.Media.Font, fontSize, generalSettings.Fonts.FontFlag)
    if generalSettings.Fonts.Shadow.Enabled then
        keybindText:SetShadowColor(generalSettings.Fonts.Shadow.Colour[1], generalSettings.Fonts.Shadow.Colour[2], generalSettings.Fonts.Shadow.Colour[3], generalSettings.Fonts.Shadow.Colour[4])
        keybindText:SetShadowOffset(generalSettings.Fonts.Shadow.OffsetX, generalSettings.Fonts.Shadow.OffsetY)
    else
        keybindText:SetShadowColor(0, 0, 0, 1)
        keybindText:SetShadowOffset(1, -1)
    end
end

local function UpdateActionButtonKeybinds(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    local showKeybinds = BCDM.db.profile.CooldownManager.General.ShowActionButtonKeybinds
    local spellToKeybind = showKeybinds and BuildSpellKeybindMap() or nil

    for _, icon in ipairs({ viewer:GetChildren() }) do
        if icon and icon.Icon then
            local keybindText = icon.BCDMKeybindText
            if not showKeybinds then
                if keybindText then
                    keybindText:Hide()
                end
            else
                local spellID = GetIconSpellID(icon)
                local binding = ResolveSpellKeybind(spellToKeybind, spellID)
                if binding ~= "" then
                    keybindText = GetOrCreateKeybindText(icon)
                    ApplyKeybindTextStyling(keybindText, icon)
                    keybindText:SetText(binding)
                    keybindText:Show()
                elseif keybindText then
                    keybindText:Hide()
                end
            end
        end
    end
end

local function UpdateAllActionButtonKeybinds()
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        UpdateActionButtonKeybinds(viewerName)
    end
end

local keybindEventFrame = CreateFrame("Frame")

local function SetupActionButtonKeybindEvents()
    keybindEventFrame:UnregisterAllEvents()
    keybindEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    keybindEventFrame:RegisterEvent("UPDATE_BINDINGS")
    keybindEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    keybindEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    keybindEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    keybindEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    keybindEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    keybindEventFrame:SetScript("OnEvent", function()
        C_Timer.After(0.05, UpdateAllActionButtonKeybinds)
    end)
end

local ASSIST_FLIPBOOK = {
    atlas = "RotationHelper_Ants_Flipbook_2x",
    rows = 6,
    columns = 5,
    frames = 30,
    duration = 1.0,
    scale = 1.5,
}

local assistEventFrame = CreateFrame("Frame")
local assistManagerHooked = false
local assistViewerHooksInitialized = false

local function IsAssistEnabled()
    return BCDM.db
        and BCDM.db.profile
        and BCDM.db.profile.CooldownManager
        and BCDM.db.profile.CooldownManager.General
        and BCDM.db.profile.CooldownManager.General.HighlightAssist
end

local function GetOrCreateAssistFlipbook(icon)
    if icon.BCDMAssistFlipbook then
        local iconWidth, iconHeight = icon:GetSize()
        icon.BCDMAssistFlipbook.Texture:SetSize(iconWidth * ASSIST_FLIPBOOK.scale, iconHeight * ASSIST_FLIPBOOK.scale)
        return icon.BCDMAssistFlipbook
    end

    local flipbookFrame = CreateFrame("Frame", nil, icon)
    flipbookFrame:SetFrameLevel(icon:GetFrameLevel() + 10)
    flipbookFrame:SetAllPoints(icon)

    local flipbookTexture = flipbookFrame:CreateTexture(nil, "OVERLAY")
    flipbookTexture:SetAtlas(ASSIST_FLIPBOOK.atlas)
    flipbookTexture:SetBlendMode("ADD")
    flipbookTexture:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local iconWidth, iconHeight = icon:GetSize()
    flipbookTexture:SetSize(iconWidth * ASSIST_FLIPBOOK.scale, iconHeight * ASSIST_FLIPBOOK.scale)
    flipbookFrame.Texture = flipbookTexture

    local animGroup = flipbookFrame:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    animGroup:SetToFinalAlpha(true)
    flipbookFrame.Anim = animGroup

    local alphaAnim = animGroup:CreateAnimation("Alpha")
    alphaAnim:SetChildKey("Texture")
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(1)
    alphaAnim:SetDuration(0.001)
    alphaAnim:SetOrder(0)

    local flipAnim = animGroup:CreateAnimation("FlipBook")
    flipAnim:SetChildKey("Texture")
    flipAnim:SetDuration(ASSIST_FLIPBOOK.duration)
    flipAnim:SetOrder(0)
    flipAnim:SetFlipBookRows(ASSIST_FLIPBOOK.rows)
    flipAnim:SetFlipBookColumns(ASSIST_FLIPBOOK.columns)
    flipAnim:SetFlipBookFrames(ASSIST_FLIPBOOK.frames)
    flipAnim:SetFlipBookFrameWidth(0)
    flipAnim:SetFlipBookFrameHeight(0)

    flipbookFrame:SetAlpha(0)
    flipbookFrame:Show()
    icon.BCDMAssistFlipbook = flipbookFrame
    return flipbookFrame
end

local function HideAssistFlipbook(icon)
    if not icon or not icon.BCDMAssistFlipbook then return end
    icon.BCDMAssistFlipbook:SetAlpha(0)
    if icon.BCDMAssistFlipbook.Anim and icon.BCDMAssistFlipbook.Anim:IsPlaying() then
        icon.BCDMAssistFlipbook.Anim:Stop()
    end
end

local function HideAllAssistFlipbooks()
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        if viewer then
            for _, icon in ipairs({ viewer:GetChildren() }) do
                HideAssistFlipbook(icon)
            end
        end
    end
end

local function GetSuggestedAssistSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
        return nil
    end
    return C_AssistedCombat.GetNextCastSpell()
end

local function UpdateAssistHighlightForIcon(icon, suggestedSpellID)
    if not icon or not icon.Icon then return end
    if not IsAssistEnabled() then
        HideAssistFlipbook(icon)
        return
    end
    if not suggestedSpellID then
        HideAssistFlipbook(icon)
        return
    end

    local iconSpellID, overrideSpellID = GetIconSpellID(icon), nil
    if icon.cooldownInfo then
        overrideSpellID = icon.cooldownInfo.overrideSpellID
    elseif icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
        overrideSpellID = info and info.overrideSpellID or nil
    end

    local isSuggested = iconSpellID and (iconSpellID == suggestedSpellID or (overrideSpellID and overrideSpellID == suggestedSpellID))
    local flipbook = GetOrCreateAssistFlipbook(icon)
    if isSuggested then
        flipbook:SetAlpha(1)
        if flipbook.Anim and not flipbook.Anim:IsPlaying() then
            flipbook.Anim:Play()
        end
    else
        HideAssistFlipbook(icon)
    end
end

local function UpdateAssistHighlightsForViewer(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end
    local suggestedSpellID = GetSuggestedAssistSpell()
    for _, icon in ipairs({ viewer:GetChildren() }) do
        UpdateAssistHighlightForIcon(icon, suggestedSpellID)
    end
end

local function UpdateAllAssistHighlights()
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        UpdateAssistHighlightsForViewer(viewerName)
    end
end

local function HookAssistManager()
    if assistManagerHooked then return end
    if not AssistedCombatManager then return end
    if not AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then return end
    hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
        if IsAssistEnabled() then
            UpdateAllAssistHighlights()
        end
    end)
    assistManagerHooked = true
end

local function SetupAssistViewerHooks()
    if assistViewerHooksInitialized then return end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        if viewer and viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                if IsAssistEnabled() then
                    UpdateAssistHighlightsForViewer(viewerName)
                end
            end)
        end
    end
    assistViewerHooksInitialized = true
end

function BCDM:RefreshAssistHighlight()
    assistEventFrame:UnregisterAllEvents()
    assistEventFrame:SetScript("OnEvent", nil)

    if not IsAssistEnabled() then
        HideAllAssistFlipbooks()
        return
    end

    if C_CVar and C_CVar.GetCVar and C_CVar.SetCVar and C_CVar.GetCVar("assistedCombatHighlight") ~= "1" then
        C_CVar.SetCVar("assistedCombatHighlight", "1")
    end

    HookAssistManager()
    SetupAssistViewerHooks()

    assistEventFrame:RegisterEvent("ADDON_LOADED")
    assistEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    assistEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    assistEventFrame:RegisterEvent("SPELLS_CHANGED")
    assistEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    assistEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    assistEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    assistEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    assistEventFrame:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon == "Blizzard_AssistedCombat" then
            HookAssistManager()
        end
        C_Timer.After(0.05, UpdateAllAssistHighlights)
    end)

    C_Timer.After(0.05, UpdateAllAssistHighlights)
end

local function Position()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local viewerFrame = _G[viewerName]
        if viewerFrame and (viewerName == "UtilityCooldownViewer" or viewerName == "BuffIconCooldownViewer") then
            viewerFrame:ClearAllPoints()
            local anchorParent = viewerSettings.Layout[2] == "NONE" and UIParent or _G[viewerSettings.Layout[2]]
            viewerFrame:SetPoint(viewerSettings.Layout[1], anchorParent, viewerSettings.Layout[3], viewerSettings.Layout[4], viewerSettings.Layout[5])
            viewerFrame:SetFrameStrata("LOW")
        elseif viewerFrame then
            viewerFrame:ClearAllPoints()
            viewerFrame:SetPoint(viewerSettings.Layout[1], UIParent, viewerSettings.Layout[3], viewerSettings.Layout[4], viewerSettings.Layout[5])
            viewerFrame:SetFrameStrata("LOW")
        end
        NudgeViewer(viewerName, -0.1, 0)
    end
end

local function StyleIcons()
    if not ShouldSkin() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
        for _, childFrame in ipairs({_G[viewerName]:GetChildren()}) do
            if childFrame then
                if childFrame.Icon then
                    BCDM:StripTextures(childFrame.Icon)
                    local iconZoomAmount = cooldownManagerSettings.General.IconZoom * 0.5
                    BCDM:ApplyIconTexCoord(childFrame.Icon, iconWidth, iconHeight, iconZoomAmount)
                end
                if childFrame.Cooldown then
                    local borderSize = cooldownManagerSettings.General.BorderSize
                    childFrame.Cooldown:ClearAllPoints()
                    childFrame.Cooldown:SetPoint("TOPLEFT", childFrame, "TOPLEFT", borderSize, -borderSize)
                    childFrame.Cooldown:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -borderSize, borderSize)
                    childFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
                    childFrame.Cooldown:SetDrawEdge(false)
                    childFrame.Cooldown:SetDrawSwipe(true)
                    childFrame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                end
                if childFrame.CooldownFlash then childFrame.CooldownFlash:SetAlpha(0) end
                if childFrame.DebuffBorder then childFrame.DebuffBorder:SetAlpha(0) end
                childFrame:SetSize(iconWidth, iconHeight)
                BCDM:AddBorder(childFrame)
                if not childFrame.layoutIndex then childFrame:SetShown(false) end
            end
        end
    end
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end Position() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end BCDM.LEMO:LoadLayouts() Position() end)
    hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function() if InCombatLockdown() then return end BCDM:UpdateBCDM() end)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        if viewer and viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                UpdateActionButtonKeybinds(viewerName)
            end)
        end
    end
end

local function StyleChargeCount()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local generalSettings = BCDM.db.profile.General
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        for _, childFrame in ipairs({ _G[viewerName]:GetChildren() }) do
            if childFrame and childFrame.ChargeCount and childFrame.ChargeCount.Current then
                local currentChargeText = childFrame.ChargeCount.Current
                currentChargeText:SetFont(BCDM.Media.Font, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.FontSize, generalSettings.Fonts.FontFlag)
                currentChargeText:ClearAllPoints()
                currentChargeText:SetPoint(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[1], childFrame, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[3], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[4])
                currentChargeText:SetTextColor(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[1], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[3], 1)
                if generalSettings.Fonts.Shadow.Enabled then
                    currentChargeText:SetShadowColor(generalSettings.Fonts.Shadow.Colour[1], generalSettings.Fonts.Shadow.Colour[2], generalSettings.Fonts.Shadow.Colour[3], generalSettings.Fonts.Shadow.Colour[4])
                    currentChargeText:SetShadowOffset(generalSettings.Fonts.Shadow.OffsetX, generalSettings.Fonts.Shadow.OffsetY)
                else
                    currentChargeText:SetShadowColor(0, 0, 0, 0)
                    currentChargeText:SetShadowOffset(0, 0)
                end
                currentChargeText:SetDrawLayer("OVERLAY")
            end
        end
        for _, childFrame in ipairs({ _G[viewerName]:GetChildren() }) do
            if childFrame and childFrame.Applications then
                local applicationsText = childFrame.Applications.Applications
                applicationsText:SetFont(BCDM.Media.Font, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.FontSize, generalSettings.Fonts.FontFlag)
                applicationsText:ClearAllPoints()
                applicationsText:SetPoint(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[1], childFrame, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[3], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[4])
                applicationsText:SetTextColor(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[1], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[3], 1)
                if generalSettings.Fonts.Shadow.Enabled then
                    applicationsText:SetShadowColor(generalSettings.Fonts.Shadow.Colour[1], generalSettings.Fonts.Shadow.Colour[2], generalSettings.Fonts.Shadow.Colour[3], generalSettings.Fonts.Shadow.Colour[4])
                    applicationsText:SetShadowOffset(generalSettings.Fonts.Shadow.OffsetX, generalSettings.Fonts.Shadow.OffsetY)
                else
                    applicationsText:SetShadowColor(0, 0, 0, 0)
                    applicationsText:SetShadowOffset(0, 0)
                end
                applicationsText:SetDrawLayer("OVERLAY")
            end
        end
    end
end

local centerBuffsUpdateThrottle = 0.01
local nextcenterBuffsUpdate = 0

local function CenterBuffs()
    local currentTime = GetTime()
    if currentTime < nextcenterBuffsUpdate then return end
    nextcenterBuffsUpdate = currentTime + centerBuffsUpdateThrottle
    local visibleBuffIcons = {}

    for _, childFrame in ipairs({ BuffIconCooldownViewer:GetChildren() }) do
        if childFrame and childFrame.Icon and childFrame:IsShown() then
            table.insert(visibleBuffIcons, childFrame)
        end
    end

    table.sort(visibleBuffIcons, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

    local visibleCount = #visibleBuffIcons
    if visibleCount == 0 then return 0 end

    local iconWidth = visibleBuffIcons[1]:GetWidth()
    local iconHeight = visibleBuffIcons[1]:GetHeight()
    local startX = 0
    local startY = 0
    local iconSpacing = 0

    if BuffIconCooldownViewer.isHorizontal then
        iconSpacing = BuffIconCooldownViewer.childXPadding or 0
        local totalWidth = (visibleCount * iconWidth) + ((visibleCount - 1) * iconSpacing)
        startX = -totalWidth / 2 + iconWidth / 2
    else
        iconSpacing = BuffIconCooldownViewer.childYPadding or 0
        local totalHeight = (visibleCount * iconHeight) + ((visibleCount - 1) * iconSpacing)
        startY = totalHeight / 2 - iconHeight / 2
    end

    for index, iconFrame in ipairs(visibleBuffIcons) do
        if BuffIconCooldownViewer.isHorizontal then
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("CENTER", BuffIconCooldownViewer, "CENTER", startX + (index - 1) * (iconWidth + iconSpacing), 0)
        else
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("CENTER", BuffIconCooldownViewer, "CENTER", 0, startY - (index - 1) * (iconHeight + iconSpacing))
        end
    end

    return visibleCount
end

local centerBuffsEventFrame = CreateFrame("Frame")

local function SetupCenterBuffs()
    local buffsSettings = BCDM.db.profile.CooldownManager.Buffs

    if buffsSettings.CenterBuffs then
        centerBuffsEventFrame:SetScript("OnUpdate", CenterBuffs)
    else
        centerBuffsEventFrame:SetScript("OnUpdate", nil)
        centerBuffsEventFrame:Hide()
    end
end

local function CenterWrappedRows(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    local iconLimit = viewer.iconLimit
    if not iconLimit or iconLimit <= 0 then return end

    local visibleIcons = {}
    for _, childFrame in ipairs({ viewer:GetChildren() }) do
        if childFrame and childFrame:IsShown() and childFrame.layoutIndex then
            table.insert(visibleIcons, childFrame)
        end
    end

    table.sort(visibleIcons, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

    local visibleCount = #visibleIcons
    if visibleCount == 0 then return end

    local iconWidth = visibleIcons[1]:GetWidth()
    local iconHeight = visibleIcons[1]:GetHeight()
    local iconSpacing = viewer.childXPadding or 0
    local rowSpacing = viewer.childYPadding or 0
    local rowHeight = (iconHeight > 0 and iconHeight or iconWidth) + rowSpacing

    local basePoint, _, _, _, baseY = visibleIcons[1]:GetPoint(1)
    if not basePoint or not baseY then return end
    local anchorPoint = "TOP"
    local relativePoint = "TOP"
    local yDirection = -1
    if basePoint and basePoint:find("BOTTOM") then
        anchorPoint = "BOTTOM"
        relativePoint = "BOTTOM"
        yDirection = 1
    end

    local rowCount = math.ceil(visibleCount / iconLimit)
    for rowIndex = 1, rowCount do
        local rowStart = (rowIndex - 1) * iconLimit + 1
        local rowEnd = math.min(rowStart + iconLimit - 1, visibleCount)
        local rowIcons = rowEnd - rowStart + 1
        local rowWidth = (rowIcons * iconWidth) + ((rowIcons - 1) * iconSpacing)
        local startX = -rowWidth / 2 + iconWidth / 2
        local rowY = baseY + yDirection * (rowIndex - 1) * rowHeight

        for index = rowStart, rowEnd do
            local iconFrame = visibleIcons[index]
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint(anchorPoint, viewer, relativePoint, startX + (index - rowStart) * (iconWidth + iconSpacing), rowY)
        end
    end
end

local function CenterWrappedIcons()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local essentialSettings = cooldownManagerSettings.Essential
    local utilitySettings = cooldownManagerSettings.Utility

    if essentialSettings and essentialSettings.CenterHorizontally then CenterWrappedRows("EssentialCooldownViewer") end
    if utilitySettings and utilitySettings.CenterHorizontally then CenterWrappedRows("UtilityCooldownViewer") end
end

function BCDM:SkinCooldownManager()
    local LEMO = BCDM.LEMO
    LEMO:LoadLayouts()
    C_CVar.SetCVar("cooldownViewerEnabled", 1)
    StyleIcons()
    StyleChargeCount()
    Position()
    SetHooks()
    SetupActionButtonKeybindEvents()
    SetupCenterBuffs()
    BCDM:RefreshAssistHighlight()
    if EssentialCooldownViewer and EssentialCooldownViewer.RefreshLayout then hooksecurefunc(EssentialCooldownViewer, "RefreshLayout", function() CenterWrappedIcons() end) end
    if UtilityCooldownViewer and UtilityCooldownViewer.RefreshLayout then hooksecurefunc(UtilityCooldownViewer, "RefreshLayout", function() CenterWrappedIcons() end) end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        C_Timer.After(0.1, function()
            ApplyCooldownText(viewerName)
            UpdateActionButtonKeybinds(viewerName)
            UpdateAssistHighlightsForViewer(viewerName)
        end)
    end

    C_Timer.After(1, function()
        if not InCombatLockdown() then
            LEMO:ApplyChanges()
        end
    end)
end

function BCDM:UpdateCooldownViewer(viewerType)
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local cooldownViewerFrame = _G[BCDM.DBViewerToCooldownManagerViewer[viewerType]]
    local viewerSettings = cooldownManagerSettings[viewerType]
    local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
    if viewerType == "Custom" then BCDM:UpdateCustomCooldownViewer() return end
    if viewerType == "AdditionalCustom" then BCDM:UpdateAdditionalCustomCooldownViewer() return end
    if viewerType == "Item" then BCDM:UpdateCustomItemBar() return end
    if viewerType == "Trinket" then BCDM:UpdateTrinketBar() return end
    if viewerType == "ItemSpell" then BCDM:UpdateCustomItemsSpellsBar() return end
    if viewerType == "Buffs" then SetupCenterBuffs() end

    for _, childFrame in ipairs({cooldownViewerFrame:GetChildren()}) do
        if childFrame then
            if childFrame.Icon and ShouldSkin() then
                BCDM:StripTextures(childFrame.Icon)
                BCDM:ApplyIconTexCoord(childFrame.Icon, iconWidth, iconHeight, cooldownManagerSettings.General.IconZoom)
            end
            if childFrame.Cooldown then
                childFrame.Cooldown:ClearAllPoints()
                childFrame.Cooldown:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, -1)
                childFrame.Cooldown:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -1, 1)
                childFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
                childFrame.Cooldown:SetDrawEdge(false)
                childFrame.Cooldown:SetDrawSwipe(true)
                childFrame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            end
            if childFrame.CooldownFlash then childFrame.CooldownFlash:SetAlpha(0) end
            childFrame:SetSize(iconWidth, iconHeight)
        end
    end

    StyleIcons()

    Position()

    StyleChargeCount()

    ApplyCooldownText(BCDM.DBViewerToCooldownManagerViewer[viewerType])
    UpdateActionButtonKeybinds(BCDM.DBViewerToCooldownManagerViewer[viewerType])
    UpdateAssistHighlightsForViewer(BCDM.DBViewerToCooldownManagerViewer[viewerType])

    BCDM:UpdatePowerBarWidth()
    BCDM:UpdateSecondaryPowerBarWidth()
    BCDM:UpdateCastBarWidth()
end

function BCDM:UpdateCooldownViewers()
    BCDM:UpdateCooldownViewer("Essential")
    BCDM:UpdateCooldownViewer("Utility")
    BCDM:UpdateCooldownViewer("Buffs")
    BCDM:UpdateCustomCooldownViewer()
    BCDM:UpdateAdditionalCustomCooldownViewer()
    BCDM:UpdateCustomItemBar()
    BCDM:UpdateCustomItemsSpellsBar()
    BCDM:UpdateTrinketBar()
    BCDM:UpdatePowerBar()
    BCDM:UpdateSecondaryPowerBar()
    BCDM:UpdateCastBar()
end
