--[[
    LD Combat Stats - Analysis.lua
    数据分析: 排序、技能细分、汇总计算
]]

local addonName, ns = ...
local L = ns.L

local Analysis = {}
ns.Analysis = Analysis

function Analysis:Init() end

-- ============================================================
-- 获取排序后的玩家列表
-- ============================================================
function Analysis:GetSorted(segment, mode)
    if not segment then return {} end

    -- 敌人承伤走独立数据结构
    if mode == "damageTaken" and ns.state.damageTakenView == "enemy" then
        local list = segment.enemyDamageTakenList or {}
        local result = {}
        local totalValue = 0
        for _, entry in ipairs(list) do totalValue = totalValue + entry.total end
        for i, entry in ipairs(list) do
            table.insert(result, {
                guid     = "creature_" .. (entry.creatureID or i),
                name     = entry.name,
                class    = "WARRIOR",
                value    = entry.total,
                perSec   = entry.perSec or 0,
                percent  = totalValue > 0 and (entry.total / totalValue * 100) or 0,
                deaths   = 0, interrupts = 0, dispels = 0,
                _isEnemy = true,
                _sources = entry.sources,
            })
        end
        return result
    end

    local viewSuffix = (mode == "damageTaken" and ns.state.damageTakenView == "enemy") and "|enemy" or ""
    local cacheKey = tostring(segment) .. "|" .. mode .. viewSuffix

    -- 检查两个缓存槽
    if self._sortedCache and self._sortedCacheKey == cacheKey then
        return self._sortedCache
    end
    if self._sortedCache2 and self._sortedCacheKey2 == cacheKey then
        return self._sortedCache2
    end

    local result     = {}
    local totalValue = 0

    for guid, pd in pairs(segment.players) do
        local value = self:GetPlayerValue(pd, mode, segment)
        if value > 0 then
            -- ★ 读取暴雪存储的每秒值（活跃时间口径，与官方面板一致）
            local perSec = 0
            if mode == "damage"         then perSec = pd.damagePerSec      or 0
            elseif mode == "healing"    then perSec = pd.healingPerSec     or 0
            elseif mode == "damageTaken" then perSec = pd.damageTakenPerSec or 0
            end

            table.insert(result, {
                guid        = guid,
                name        = pd.name,
                class       = pd.class,
                specID      = pd.specID,
                specIconID  = pd.specIconID, 
                ilvl        = pd.ilvl,
                score       = pd.score,
                value       = value,
                perSec      = perSec,   -- ★ 新增
                deaths      = pd.deaths,
                interrupts  = pd.interrupts,
                dispels     = pd.dispels,
                overhealing = pd.overhealing,
                activeTime  = pd.activeTime,
                petDamage   = self:GetPetTotal(pd, mode),
            })
            totalValue = totalValue + value
        end
    end

    table.sort(result, function(a, b) return a.value > b.value end)

    for _, d in ipairs(result) do
        d.percent = totalValue > 0 and (d.value / totalValue * 100) or 0
    end

    -- 轮替缓存：淘汰最旧的
    self._sortedCache2    = self._sortedCache
    self._sortedCacheKey2 = self._sortedCacheKey
    self._sortedCache     = result
    self._sortedCacheKey  = cacheKey
    return result
end

function Analysis:InvalidateCache()
    self._sortedCache     = nil
    self._sortedCacheKey  = nil
    self._sortedCache2    = nil
    self._sortedCacheKey2 = nil
end


function Analysis:GetPlayerValue(pd, mode, segment)
    if mode == "damage" then
        return pd.damage
    elseif mode == "healing" then
        return pd.healing
    elseif mode == "damageTaken" then
        return pd.damageTaken
    elseif mode == "deaths" then
        return pd.deaths
    elseif mode == "interrupts" then
        return pd.interrupts
    elseif mode == "dispels" then
        return pd.dispels
    end
    return 0
end

function Analysis:GetPetTotal(pd, mode)
    local total = 0
    for _, pet in pairs(pd.pets) do
        if mode == "damage" then
            total = total + (pet.damage or 0)
        elseif mode == "healing" then
            total = total + (pet.healing or 0)
        end
    end
    return total
end

-- ============================================================
-- 技能细分 (供DetailView使用)
-- ============================================================
function Analysis:GetSpellBreakdown(segment, guid, mode)
    if not segment or not guid then return {} end

    local pd = segment.players[guid]
    if not pd then return {} end

    local result     = {}
    local totalValue = 0

    local sourceTable = pd.spells
    if mode == "interrupts" then sourceTable = pd.interruptSpells or {}
    elseif mode == "dispels" then sourceTable = pd.dispelSpells or {} end

    for spellID, sd in pairs(sourceTable) do
        local value = 0
        if mode == "damage"  then value = sd.damage
        elseif mode == "healing" then value = sd.healing end

        if value > 0 then
            table.insert(result, {
                spellID     = spellID,
                name        = sd.name,
                school      = sd.school,
                value       = value,
                hits        = sd.hits,
                crits       = sd.crits,
                maxHit      = sd.maxHit,
                minHit      = sd.minHit ~= 999999999 and sd.minHit or 0,
                critPercent = sd.hits > 0 and (sd.crits / sd.hits * 100) or 0,
                overhealing = sd.overhealing,
                isPet       = false,
            })
            totalValue = totalValue + value
        end
    end

    -- 宠物技能
    if ns.db.tracking.mergePlayerPets then
        for petGUID, pet in pairs(pd.pets) do
            for spellID, sd in pairs(pet.spells or {}) do
                local value = 0
                if mode == "damage"  then value = sd.damage
                elseif mode == "healing" then value = sd.healing end

                if value > 0 then
                    table.insert(result, {
                        spellID     = spellID,
                        name        = (pet.name or "Pet") .. ": " .. sd.name,
                        school      = sd.school,
                        value       = value,
                        hits        = sd.hits,
                        crits       = sd.crits,
                        maxHit      = sd.maxHit,
                        minHit      = sd.minHit ~= 999999999 and sd.minHit or 0,
                        critPercent = sd.hits > 0 and (sd.crits / sd.hits * 100) or 0,
                        isPet       = true,
                        petName     = pet.name,
                    })
                    totalValue = totalValue + value
                end
            end

            -- 宠物无技能细分时，显示总计行
            if not next(pet.spells or {}) then
                local petVal = mode == "damage" and (pet.damage or 0) or (pet.healing or 0)
                if petVal > 0 then
                    table.insert(result, {
                        spellID     = 0,
                        name        = (pet.name or "Pet") .. L[" (合计)"],
                        value       = petVal,
                        hits        = 0, crits = 0, maxHit = 0, minHit = 0, critPercent = 0,
                        isPet       = true,
                    })
                    totalValue = totalValue + petVal
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.value > b.value end)

    for _, d in ipairs(result) do
        d.percent = totalValue > 0 and (d.value / totalValue * 100) or 0
    end

    return result
end

-- ============================================================
-- 段落时长计算
-- ============================================================
function Analysis:GetSegmentDuration(segment)
    if not segment then return 0 end
    if segment.isActive then
        return C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current) or 0
    end

    return segment.duration or 0
end

-- ============================================================
-- 综合战斗报告数据
-- ============================================================
function Analysis:GetFightSummary(segment)
    if not segment then return nil end

    local dur           = self:GetSegmentDuration(segment)
    local playerCount   = 0
    local totalDeaths   = 0
    local totalInts     = 0
    local totalDisp     = 0

    for _, pd in pairs(segment.players) do
        playerCount = playerCount + 1
        totalDeaths = totalDeaths + pd.deaths
        totalInts   = totalInts   + pd.interrupts
        totalDisp   = totalDisp   + pd.dispels
    end

    return {
        duration         = dur,
        playerCount      = playerCount,
        totalDamage      = segment.totalDamage,
        totalHealing     = segment.totalHealing,
        totalDamageTaken = segment.totalDamageTaken,
        groupDPS         = dur > 0 and (segment.totalDamage      / dur) or 0,
        groupHPS         = dur > 0 and (segment.totalHealing     / dur) or 0,
        groupDTPS        = dur > 0 and (segment.totalDamageTaken / dur) or 0,
        totalDeaths      = totalDeaths,
        totalInterrupts  = totalInts,
        totalDispels     = totalDisp,
        encounterName    = segment.encounterName,
        success          = segment.success,
    }
end

-- ============================================================
-- M+ 全程：获取某玩家在 overall 段的数据（供UI双列显示）
-- 返回 { value, perSec, percent } 或 nil
-- ============================================================
function Analysis:GetOverallPlayerData(guid, mode)
    -- ★ 战斗中 overall 数据可能含 Secret Value，禁止做除法运算
    if ns.state.inCombat then return nil end

    local ovr = ns.Segments and ns.Segments:GetOverallSegment()
    if not ovr then return nil end

    local pd = ovr.players[guid]
    if not pd then return nil end

    local dur   = self:GetSegmentDuration(ovr)
    local value = self:GetPlayerValue(pd, mode, ovr)
    if value <= 0 then return nil end

    local total = 0
    for _, opd in pairs(ovr.players) do
        total = total + self:GetPlayerValue(opd, mode, ovr)
    end

    return {
        value   = value,
        perSec  = dur > 0 and (value / dur) or 0,
        percent = total > 0 and (value / total * 100) or 0,
        dur     = dur,
    }
end