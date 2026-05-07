local _, BCDM = ...

BCDM.BuffGroupContainers = BCDM.BuffGroupContainers or {}

local UPDATE_THROTTLE = 0.05
local updateFrame = CreateFrame("Frame")
local viewerHooked = false
local updateInProgress = false
local ApplyMainBuffFrameStyle

local function GetBuffGroupsDB()
    local profile = BCDM.db and BCDM.db.profile
    local cooldownManager = profile and profile.CooldownManager
    if not cooldownManager then return end
    cooldownManager.BuffGroups = cooldownManager.BuffGroups or {}
    return cooldownManager.BuffGroups
end

local function GetBuffViewer()
    return _G["BuffIconCooldownViewer"]
end

function BCDM:SuspendBuffGroups()
    self.BuffGroupsSuspended = true

    local viewer = GetBuffViewer()
    if not viewer then return end

    for _, container in pairs(self.BuffGroupContainers or {}) do
        if container then
            for _, child in ipairs({ container:GetChildren() }) do
                if child then
                    child:SetParent(viewer)
                    child:ClearAllPoints()
                    ApplyMainBuffFrameStyle(child)
                end
            end
            container:Hide()
        end
    end
end

function BCDM:ResumeBuffGroups()
    self.BuffGroupsSuspended = nil
    self:UpdateBuffGroups(true)
end

function BCDM:GetDefaultBuffGroupConfig(groupIndex)
    return {
        Name = "Buff Group " .. tostring(groupIndex or 1),
        Enabled = true,
        IconSize = 32,
        IconWidth = 32,
        IconHeight = 32,
        KeepAspectRatio = true,
        FrameStrata = "LOW",
        Layout = {"CENTER", "NONE", "CENTER", 0, 0},
        Spacing = 1,
        GrowthDirection = "RIGHT",
        Columns = 0,
        Text = {
            FontSize = 15,
            Colour = {1, 1, 1},
            Layout = {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 3},
        },
        Spells = {},
    }
end

function BCDM:EnsureBuffGroups()
    local groups = GetBuffGroupsDB()
    if not groups then return {} end

    for index, groupDB in ipairs(groups) do
        local defaults = self:GetDefaultBuffGroupConfig(index)
        for key, value in pairs(defaults) do
            if groupDB[key] == nil then
                groupDB[key] = self:CopyTable(value)
            end
        end
        groupDB.Text = groupDB.Text or self:CopyTable(defaults.Text)
        groupDB.Layout = groupDB.Layout or self:CopyTable(defaults.Layout)
        groupDB.Spells = groupDB.Spells or {}
    end

    return groups
end

function BCDM:CreateBuffGroup()
    local groups = self:EnsureBuffGroups()
    groups[#groups + 1] = self:GetDefaultBuffGroupConfig(#groups + 1)
    self:UpdateBuffGroups(true)
    return #groups
end

function BCDM:DeleteBuffGroup(groupIndex)
    local groups = self:EnsureBuffGroups()
    table.remove(groups, groupIndex)

    for index, groupDB in ipairs(groups) do
        if not groupDB.Name or groupDB.Name == "" or groupDB.Name:match("^Buff Group %d+$") then
            groupDB.Name = "Buff Group " .. index
        end
    end

    local container = self.BuffGroupContainers[groupIndex]
    if container then
        for _, child in ipairs({ container:GetChildren() }) do
            if child then
                child:SetParent(_G["BuffIconCooldownViewer"] or UIParent)
            end
        end
        container:Hide()
        container:SetParent(nil)
        self.BuffGroupContainers[groupIndex] = nil
    end

    local compacted = {}
    for index, existingContainer in pairs(self.BuffGroupContainers) do
        compacted[index > groupIndex and (index - 1) or index] = existingContainer
    end
    self.BuffGroupContainers = compacted

    self:UpdateBuffGroups(true)
end

function BCDM:NormalizeBuffGroupSpellLayout(groupIndex)
    local groups = self:EnsureBuffGroups()
    local groupDB = groups[groupIndex]
    if not groupDB or not groupDB.Spells then return end

    local ordered = {}
    for spellID, data in pairs(groupDB.Spells) do
        ordered[#ordered + 1] = {
            spellID = spellID,
            data = data,
            sortIndex = data.layoutIndex or math.huge,
        }
    end

    table.sort(ordered, function(a, b)
        if a.sortIndex == b.sortIndex then
            return tostring(a.spellID) < tostring(b.spellID)
        end
        return a.sortIndex < b.sortIndex
    end)

    for index, entry in ipairs(ordered) do
        entry.data.layoutIndex = index
        entry.data.isActive = entry.data.isActive ~= false
    end
end

function BCDM:AdjustBuffGroupSpellList(groupIndex, spellID, action)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return end

    local groups = self:EnsureBuffGroups()
    local groupDB = groups[groupIndex]
    if not groupDB then return end
    groupDB.Spells = groupDB.Spells or {}

    if action == "add" then
        if not groupDB.Spells[spellID] then
            local maxIndex = 0
            for _, data in pairs(groupDB.Spells) do
                if (data.layoutIndex or 0) > maxIndex then
                    maxIndex = data.layoutIndex or 0
                end
            end
            groupDB.Spells[spellID] = { isActive = true, layoutIndex = maxIndex + 1 }
        else
            groupDB.Spells[spellID].isActive = true
        end
    elseif action == "remove" then
        groupDB.Spells[spellID] = nil
    end

    self:NormalizeBuffGroupSpellLayout(groupIndex)
    self:UpdateBuffGroups(true)
end

function BCDM:AdjustBuffGroupSpellLayout(groupIndex, spellID, direction)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return end

    local groups = self:EnsureBuffGroups()
    local groupDB = groups[groupIndex]
    local spellDB = groupDB and groupDB.Spells and groupDB.Spells[spellID]
    if not spellDB then return end

    local currentIndex = spellDB.layoutIndex or 1
    local newIndex = currentIndex + direction
    local totalSpells = 0
    for _ in pairs(groupDB.Spells) do
        totalSpells = totalSpells + 1
    end
    if newIndex < 1 or newIndex > totalSpells then return end

    for otherSpellID, otherData in pairs(groupDB.Spells) do
        if otherSpellID ~= spellID and otherData.layoutIndex == newIndex then
            otherData.layoutIndex = currentIndex
            break
        end
    end

    spellDB.layoutIndex = newIndex
    self:NormalizeBuffGroupSpellLayout(groupIndex)
    self:UpdateBuffGroups(true)
end

function BCDM:SetBuffGroupSpellGlow(groupIndex, spellID, enabled, glowType, useDefaultColor, color)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return end

    local groups = self:EnsureBuffGroups()
    local groupDB = groups[groupIndex]
    local spellDB = groupDB and groupDB.Spells and groupDB.Spells[spellID]
    if not spellDB then return end

    spellDB.GlowEnabled = enabled and true or nil
    spellDB.GlowType = enabled and glowType or nil
    spellDB.GlowUseDefaultColor = enabled and (useDefaultColor ~= false) or nil
    if enabled and useDefaultColor == false and color then
        spellDB.GlowColor = {
            color[1] or 1,
            color[2] or 1,
            color[3] or 1,
            color[4] or 1,
        }
    elseif not enabled or useDefaultColor ~= false then
        spellDB.GlowColor = nil
    end

    self:UpdateBuffGroups(true)
end

local function ResolveFrameCooldownInfo(frame)
    if not frame then return end
    if frame.cooldownInfo then return frame.cooldownInfo end
    if frame.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return C_CooldownViewer.GetCooldownViewerCooldownInfo(frame.cooldownID)
    end
end

local function ResolveFrameSpellID(frame)
    local info = ResolveFrameCooldownInfo(frame)
    if info then
        return info.overrideSpellID or info.spellID
    end
    return nil
end

local function GetOrCreateContainer(groupIndex)
    local container = BCDM.BuffGroupContainers[groupIndex]
    if container then
        return container
    end

    container = CreateFrame("Frame", "BCDM_BuffGroup_" .. groupIndex, UIParent, "BackdropTemplate")
    container:SetSize(1, 1)
    BCDM.BuffGroupContainers[groupIndex] = container
    return container
end

local function UpdateContainerPosition(container, groupDB)
    if not container or not groupDB then return end
    local anchorParent = groupDB.Layout[2] == "NONE" and UIParent or _G[groupDB.Layout[2]]
    container:ClearAllPoints()
    container:SetPoint(groupDB.Layout[1], anchorParent or UIParent, groupDB.Layout[3], groupDB.Layout[4], groupDB.Layout[5])
    container:SetFrameStrata(groupDB.FrameStrata or "LOW")
end

local function ApplyGroupedFrameStyle(frame, groupDB)
    if not frame or not groupDB then return end

    local iconWidth, iconHeight = BCDM:GetIconDimensions(groupDB)
    frame:SetSize(iconWidth, iconHeight)
    if frame.Icon then
        local iconZoom = (BCDM.db.profile.CooldownManager.General.IconZoom or 0) * 0.5
        BCDM:ApplyIconTexCoord(frame.Icon, iconWidth, iconHeight, iconZoom)
    end

    local generalDB = BCDM.db.profile.General
    local textDB = groupDB.Text or {}
    local textColour = textDB.Colour or {1, 1, 1}
    local textLayout = textDB.Layout or {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 3}

    local currentChargeText = frame.ChargeCount and frame.ChargeCount.Current
    if currentChargeText then
        currentChargeText:SetFont(BCDM.Media.Font, textDB.FontSize or 15, generalDB.Fonts.FontFlag)
        currentChargeText:ClearAllPoints()
        currentChargeText:SetPoint(textLayout[1], frame, textLayout[2], textLayout[3], textLayout[4])
        currentChargeText:SetTextColor(textColour[1], textColour[2], textColour[3], 1)
    end

    local applicationsText = frame.Applications and frame.Applications.Applications
    if applicationsText then
        applicationsText:SetFont(BCDM.Media.Font, textDB.FontSize or 15, generalDB.Fonts.FontFlag)
        applicationsText:ClearAllPoints()
        applicationsText:SetPoint(textLayout[1], frame, textLayout[2], textLayout[3], textLayout[4])
        applicationsText:SetTextColor(textColour[1], textColour[2], textColour[3], 1)
    end

    local spellID = ResolveFrameSpellID(frame)
    local spellData = spellID and groupDB.Spells and groupDB.Spells[spellID] or nil
    if spellData and spellData.GlowEnabled then
        local glowColor = (spellData.GlowUseDefaultColor == false) and spellData.GlowColor or nil
        BCDM:StartBuffGroupGlow(frame, spellData.GlowType, glowColor)
    else
        BCDM:StopBuffGroupGlow(frame)
    end
end

ApplyMainBuffFrameStyle = function(frame)
    local buffsDB = BCDM.db.profile.CooldownManager.Buffs
    if not frame or not buffsDB then return end

    local iconWidth, iconHeight = BCDM:GetIconDimensions(buffsDB)
    frame:SetSize(iconWidth, iconHeight)
    if frame.Icon then
        local iconZoom = (BCDM.db.profile.CooldownManager.General.IconZoom or 0) * 0.5
        BCDM:ApplyIconTexCoord(frame.Icon, iconWidth, iconHeight, iconZoom)
    end

    local generalDB = BCDM.db.profile.General
    local textDB = buffsDB.Text or {}
    local textColour = textDB.Colour or {1, 1, 1}
    local textLayout = textDB.Layout or {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 3}

    local currentChargeText = frame.ChargeCount and frame.ChargeCount.Current
    if currentChargeText then
        currentChargeText:SetFont(BCDM.Media.Font, textDB.FontSize or 15, generalDB.Fonts.FontFlag)
        currentChargeText:ClearAllPoints()
        currentChargeText:SetPoint(textLayout[1], frame, textLayout[2], textLayout[3], textLayout[4])
        currentChargeText:SetTextColor(textColour[1], textColour[2], textColour[3], 1)
    end

    local applicationsText = frame.Applications and frame.Applications.Applications
    if applicationsText then
        applicationsText:SetFont(BCDM.Media.Font, textDB.FontSize or 15, generalDB.Fonts.FontFlag)
        applicationsText:ClearAllPoints()
        applicationsText:SetPoint(textLayout[1], frame, textLayout[2], textLayout[3], textLayout[4])
        applicationsText:SetTextColor(textColour[1], textColour[2], textColour[3], 1)
    end

    BCDM:StopBuffGroupGlow(frame)
end

local function GetActiveManagedFrames()
    local frames = {}
    local seen = {}
    local viewer = GetBuffViewer()
    if viewer then
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child and not seen[child] then
                seen[child] = true
                frames[#frames + 1] = child
            end
        end
    end

    for _, container in pairs(BCDM.BuffGroupContainers) do
        if container then
            for _, child in ipairs({ container:GetChildren() }) do
                if child and not seen[child] then
                    seen[child] = true
                    frames[#frames + 1] = child
                end
            end
        end
    end

    return frames
end

local function BuildSpellGroupLookup(groups)
    local spellToGroup = {}
    for groupIndex, groupDB in ipairs(groups) do
        if groupDB.Enabled ~= false and groupDB.Spells then
            for spellID, spellData in pairs(groupDB.Spells) do
                if spellData and spellData.isActive ~= false then
                    spellToGroup[tonumber(spellID)] = groupIndex
                end
            end
        end
    end
    return spellToGroup
end

function BCDM:BuildTrackedBuffGroupSpellList()
    local labels, values = {}, {}
    local seen = {}
    local viewers = {
        _G["BuffBarCooldownViewer"],
        _G["BuffIconCooldownViewer"],
    }

    local function AddSpellID(spellID, cooldownID)
        spellID = tonumber(spellID)
        if not spellID or spellID <= 0 or seen[spellID] then return end
        seen[spellID] = true

        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        local label = spellName and spellName ~= "" and spellName or tostring(spellID)
        if cooldownID and cooldownID > 0 then
            label = string.format("%s [%d] (%d)", label, spellID, cooldownID)
        else
            label = string.format("%s [%d]", label, spellID)
        end

        labels[spellID] = label
        values[#values + 1] = spellID
    end

    for _, viewer in ipairs(viewers) do
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child then
                    local info = ResolveFrameCooldownInfo(child)
                    local cooldownID = child.cooldownID or (info and info.cooldownID)
                    local spellID = info and (info.overrideSpellID or info.spellID) or nil
                    AddSpellID(spellID, cooldownID)
                end
            end
        end
    end

    table.sort(values, function(a, b)
        local nameA = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(a) or tostring(a)
        local nameB = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(b) or tostring(b)
        if nameA == nameB then
            return a < b
        end
        return tostring(nameA) < tostring(nameB)
    end)

    return labels, values
end

local function LayoutGroupedFrames(groupIndex, groupDB, frames)
    local container = GetOrCreateContainer(groupIndex)
    UpdateContainerPosition(container, groupDB)

    if #frames == 0 then
        container:Hide()
        return
    end

    table.sort(frames, function(a, b)
        local aSpellID = ResolveFrameSpellID(a)
        local bSpellID = ResolveFrameSpellID(b)
        local aLayout = aSpellID and groupDB.Spells[aSpellID] and groupDB.Spells[aSpellID].layoutIndex or (a.layoutIndex or math.huge)
        local bLayout = bSpellID and groupDB.Spells[bSpellID] and groupDB.Spells[bSpellID].layoutIndex or (b.layoutIndex or math.huge)
        if aLayout == bLayout then
            return tostring(aSpellID or "") < tostring(bSpellID or "")
        end
        return aLayout < bLayout
    end)

    local iconWidth, iconHeight = BCDM:GetIconDimensions(groupDB)
    local spacing = tonumber(groupDB.Spacing) or 1
    local growthDirection = groupDB.GrowthDirection or "RIGHT"
    local wrapLimit = math.floor(tonumber(groupDB.Columns) or 0)
    local itemsPerLine = wrapLimit > 0 and wrapLimit or #frames
    local isHorizontalGrowth = growthDirection == "LEFT" or growthDirection == "RIGHT"
    local lineCount = math.ceil(#frames / itemsPerLine)

    local totalWidth
    local totalHeight
    if isHorizontalGrowth then
        local columnsInRow = math.min(itemsPerLine, #frames)
        totalWidth = (columnsInRow * iconWidth) + ((columnsInRow - 1) * spacing)
        totalHeight = (lineCount * iconHeight) + ((lineCount - 1) * spacing)
    else
        local rowsInColumn = math.min(itemsPerLine, #frames)
        totalWidth = (lineCount * iconWidth) + ((lineCount - 1) * spacing)
        totalHeight = (rowsInColumn * iconHeight) + ((rowsInColumn - 1) * spacing)
    end

    container:SetSize(math.max(totalWidth, 1), math.max(totalHeight, 1))

    for index, frame in ipairs(frames) do
        frame:SetParent(container)
        frame:ClearAllPoints()
        ApplyGroupedFrameStyle(frame, groupDB)

        local lineIndex = math.floor((index - 1) / itemsPerLine)
        local itemIndex = (index - 1) % itemsPerLine

        if growthDirection == "RIGHT" then
            frame:SetPoint("TOPLEFT", container, "TOPLEFT", itemIndex * (iconWidth + spacing), -(lineIndex * (iconHeight + spacing)))
        elseif growthDirection == "LEFT" then
            frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", -(itemIndex * (iconWidth + spacing)), -(lineIndex * (iconHeight + spacing)))
        elseif growthDirection == "DOWN" then
            frame:SetPoint("TOPLEFT", container, "TOPLEFT", lineIndex * (iconWidth + spacing), -(itemIndex * (iconHeight + spacing)))
        else
            frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", lineIndex * (iconWidth + spacing), itemIndex * (iconHeight + spacing))
        end
        frame:Show()
    end

    container:Show()
end

function BCDM:UpdateBuffGroups(forceViewerRefresh)
    if updateInProgress then return end

    local viewer = GetBuffViewer()
    if not viewer then return end
    if self.BuffGroupsSuspended or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        return
    end

    local groups = self:EnsureBuffGroups()
    local spellToGroup = BuildSpellGroupLookup(groups)
    local groupedFrames = {}
    local activeContainers = {}
    local needsViewerRefresh = forceViewerRefresh and true or false

    updateInProgress = true

    for groupIndex = 1, #groups do
        groupedFrames[groupIndex] = {}
    end

    for _, frame in ipairs(GetActiveManagedFrames()) do
        local spellID = ResolveFrameSpellID(frame)
        local targetGroup = spellID and spellToGroup[spellID]
        local isShown = frame:IsShown()

        if targetGroup and isShown then
            groupedFrames[targetGroup][#groupedFrames[targetGroup] + 1] = frame
            if frame:GetParent() ~= GetOrCreateContainer(targetGroup) then
                needsViewerRefresh = true
            end
        else
            local parent = frame:GetParent()
            if parent and parent:GetName() and parent:GetName():match("^BCDM_BuffGroup_%d+$") then
                frame:SetParent(viewer)
                frame:ClearAllPoints()
                ApplyMainBuffFrameStyle(frame)
                needsViewerRefresh = true
            end
        end
    end

    for groupIndex, groupDB in ipairs(groups) do
        activeContainers[groupIndex] = true
        LayoutGroupedFrames(groupIndex, groupDB, groupedFrames[groupIndex] or {})
    end

    for groupIndex, container in pairs(self.BuffGroupContainers) do
        if container and not activeContainers[groupIndex] then
            container:Hide()
        end
    end

    updateInProgress = false

end

function BCDM:SetupBuffGroups()
    self:EnsureBuffGroups()

    if not viewerHooked then
        local viewer = GetBuffViewer()
        if viewer and viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                BCDM:UpdateBuffGroups()
            end)
            viewerHooked = true
        end
    end

    updateFrame.elapsed = 0
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        updateFrame.elapsed = updateFrame.elapsed + elapsed
        if updateFrame.elapsed < UPDATE_THROTTLE then return end
        updateFrame.elapsed = 0
        BCDM:UpdateBuffGroups()
    end)

    self:UpdateBuffGroups(true)
end
