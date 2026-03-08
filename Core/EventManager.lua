local _, BCDM = ...
local LEMO = LibStub("LibEditModeOverride-1.0")

function BCDM:SetupEventManager()
    local BCDMEventManager = CreateFrame("Frame", "BCDMEventManagerFrame")
    BCDMEventManager:RegisterEvent("PLAYER_ENTERING_WORLD")
    BCDMEventManager:RegisterEvent("LOADING_SCREEN_DISABLED")
    BCDMEventManager:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    BCDMEventManager:RegisterEvent("TRAIT_CONFIG_UPDATED")
    BCDMEventManager:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    BCDMEventManager:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    BCDMEventManager:RegisterEvent("PLAYER_REGEN_DISABLED")
    BCDMEventManager:RegisterEvent("PLAYER_REGEN_ENABLED")
    BCDMEventManager:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            if BCDM.db and BCDM.db.global and BCDM.db.global.HideCDMWhileMounted then
                BCDM:QueueMountedVisibilityRefresh()
            end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                BCDM:ApplyMountedCDMVisibility()
            end)
            return
        end
        if InCombatLockdown() then
            if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
                BCDM:ApplyMountedCDMVisibility()
            end
            return
        end
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                BCDM:ApplyMountedCDMVisibility()
            end)
            C_Timer.After(0.2, function()
                if InCombatLockdown() then return end
                BCDM:ApplyMountedCDMVisibility()
            end)
            return
        end
        if event == "UPDATE_SHAPESHIFT_FORM" then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                BCDM:ApplyMountedCDMVisibility()
            end)
            return
        end
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if unit ~= "player" then return end
            LEMO:ApplyChanges()
            BCDM:UpdateBCDM()
        else
            BCDM:UpdateBCDM()
        end
    end)
end
