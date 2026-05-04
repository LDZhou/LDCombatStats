--[[
    Light Damage - PlayerInfo.lua
    队伍玩家信息扫描器 (装等、大秘境评分、专精)
]]

local addonName, ns = ...

ns.PlayerInfoCache = {}

local inspectScanner = CreateFrame("Frame")
inspectScanner:RegisterEvent("GROUP_ROSTER_UPDATE")
inspectScanner:RegisterEvent("PLAYER_ENTERING_WORLD")
inspectScanner:RegisterEvent("INSPECT_READY")
local currentInspectUnit = nil

inspectScanner:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer > 2 then
        self.timer = 0
        if InCombatLockdown() then return end

        local prefix = IsInRaid() and "raid" or "party"
        local num = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
        local units = {"player"}
        for i = 1, num do table.insert(units, prefix..i) end

        for _, unit in ipairs(units) do
            if UnitExists(unit) and UnitIsConnected(unit) and UnitIsPlayer(unit) then
                local guid = UnitGUID(unit)
                if guid then
                    ns.PlayerInfoCache[guid] = ns.PlayerInfoCache[guid] or { score = 0, ilvl = 0, specID = nil, lastInspect = 0 }
                    local c = ns.PlayerInfoCache[guid]

                    -- 1. 获取大秘境评分 (不需要 Inspect)
                    if c.score == 0 and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
                        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                        if summary and summary.currentSeasonScore then
                            c.score = summary.currentSeasonScore
                        end
                    end

                    -- 2. 获取专精和装等
                    if unit == "player" then
                        local specIdx = GetSpecialization()
                        if specIdx then c.specID = GetSpecializationInfo(specIdx) end
                        local _, equipped = GetAverageItemLevel()
                        c.ilvl = math.floor(equipped or 0)
                    else
                        local needsInspect = (not c.specID) or ((GetTime() - (c.lastInspect or 0)) > 30)
                        if needsInspect and CanInspect(unit) and (GetTime() - (self.lastInspect or 0) > 2) then
                            self.lastInspect = GetTime()
                            currentInspectUnit = unit
                            NotifyInspect(unit)
                            break
                        end
                    end
                end
            end
        end
    end
end)

inspectScanner:SetScript("OnEvent", function(self, event, guid)
    if event == "INSPECT_READY" and currentInspectUnit and UnitGUID(currentInspectUnit) == guid then
        local c = ns.PlayerInfoCache[guid]
        if c then
            c.specID = GetInspectSpecialization(currentInspectUnit)
            local ilvl = C_PaperDollInfo.GetInspectItemLevel(currentInspectUnit)
            if ilvl then c.ilvl = math.floor(ilvl) end
            c.lastInspect = GetTime()
        end
        ClearInspectPlayer()
        currentInspectUnit = nil
    end
end)