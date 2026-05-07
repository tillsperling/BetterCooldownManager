local _, BCDM = ...
local BetterCooldownManager = LibStub("AceAddon-3.0"):NewAddon("BetterCooldownManager")

function BetterCooldownManager:OnInitialize()
    BCDM.db = LibStub("AceDB-3.0"):New("BCDMDB", BCDM:GetDefaultDB(), true)
    BCDM.LDS:EnhanceDatabase(BCDM.db, "BetterCooldownManager")
    for k, v in pairs(BCDM:GetDefaultDB()) do
        if BCDM.db.profile[k] == nil then
            BCDM.db.profile[k] = v
        end
    end
    if BCDM.db.profile and BCDM.db.profile.CooldownManager then
        local cooldownManagerDB = BCDM.db.profile.CooldownManager
        if cooldownManagerDB.Trinkets == nil and cooldownManagerDB.Trinket ~= nil then
            cooldownManagerDB.Trinkets = BCDM:CopyTable(cooldownManagerDB.Trinket)
            if cooldownManagerDB.Trinkets then
                cooldownManagerDB.Trinkets.Mode = cooldownManagerDB.Trinkets.Mode or "independent"
                if cooldownManagerDB.Trinkets.ShowPassive == nil then
                    cooldownManagerDB.Trinkets.ShowPassive = true
                end
            end
        end
        BCDM:EnsureDefensivesSpellDB()
        BCDM:EnsureBuffGroups()
    end
    if BCDM.db.global.UseGlobalProfile then BCDM.db:SetProfile(BCDM.db.global.GlobalProfile or "Default") end
    BCDM.db.RegisterCallback(BCDM, "OnProfileChanged", function() BCDM:UpdateBCDM() end)
end

function BetterCooldownManager:OnEnable()
    BCDM:CheckAddOns()
    BCDM:Init()
    BCDM:SetupEventManager()
    BCDM:SkinCooldownManager()
    BCDM:DisableAuraOverlay()
    BCDM:SetupCustomGlows()
    BCDM:CreatePowerBar()
    BCDM:CreateSecondaryPowerBar()
    BCDM:CreateCastBar()
    C_Timer.After(0.1, function()
        BCDM:SetupDefensivesViewer()
        BCDM:SetupBuffGroups()
        BCDM:SetupCustomCooldownViewer()
        BCDM:SetupAdditionalCustomCooldownViewer()
        BCDM:SetupCustomItemBar()
        BCDM:SetupTrinketsViewer()
        BCDM:SetupCustomItemsSpellsBar()
        BCDM:CreateCooldownViewerOverlays()
    end)
    BCDM:SetupEditModeManager()
end
