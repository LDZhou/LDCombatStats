--[[
    Light Damage - Utils.lua
    工具函数
]]

local addonName, ns = ...
local L = ns.L

-- 职业颜色
ns.CLASS_COLORS = {
    WARRIOR     = {0.78, 0.61, 0.43}, PALADIN     = {0.96, 0.55, 0.73},
    HUNTER      = {0.67, 0.83, 0.45}, ROGUE       = {1.00, 0.96, 0.41},
    PRIEST      = {1.00, 1.00, 1.00}, DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN      = {0.00, 0.44, 0.87}, MAGE        = {0.25, 0.78, 0.92},
    WARLOCK     = {0.53, 0.53, 0.93}, MONK        = {0.00, 1.00, 0.60},
    DRUID       = {1.00, 0.49, 0.04}, DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER      = {0.20, 0.58, 0.50},
}

-- NPC GUID 判断（用于区分玩家与生物，避免 NPC 被误染战士色）
function ns:IsNPCGUID(guid)
    if not guid then return false end
    return guid:match("^Creature%-") ~= nil
        or guid:match("^Vehicle%-") ~= nil
        or guid:match("^Pet%-") ~= nil
        or guid:match("^GameObject%-") ~= nil
end

function ns:GetClassColor(class)
    return ns.CLASS_COLORS[class] or {0.5, 0.5, 0.5}
end

function ns:GetClassHex(class)
    local c = ns:GetClassColor(class)
    return string.format("|cff%02x%02x%02x", c[1]*255, c[2]*255, c[3]*255)
end

-- 学校颜色 (伤害类型)
ns.SCHOOL_COLORS = {
    [1]  = {0.6, 0.6, 0.6},   -- Physical
    [2]  = {1.0, 0.9, 0.5},   -- Holy
    [4]  = {1.0, 0.5, 0.0},   -- Fire
    [8]  = {0.3, 1.0, 0.3},   -- Nature
    [16] = {0.5, 0.5, 1.0},   -- Frost
    [32] = {0.5, 0.0, 0.5},   -- Shadow
    [64] = {1.0, 0.5, 1.0},   -- Arcane
}

-- 格式化数字
function ns:FormatNumber(num)
    if not num or num == 0 then return "0" end
    local abs = math.abs(num)
    
    local lang = ns.currentLang
    if not lang or lang == "auto" then
        lang = (ns.db and ns.db.display and ns.db.display.language) or "auto"
    end
    if lang == "auto" then
        lang = GetLocale()
    end

    if lang == "zhCN" or lang == "zhTW" then
        if abs >= 1e8 then return string.format("%.2f亿", num / 1e8)
        elseif abs >= 1e4 then return string.format("%.2f万", num / 1e4)
        else return string.format("%.0f", num) end
    else
        if abs >= 1e6 then return string.format("%.2fM", num / 1e6)
        elseif abs >= 1e3 then return string.format("%.1fK", num / 1e3)
        else return string.format("%.0f", num) end
    end
end

-- 格式化时间
function ns:FormatTime(sec)
    if not sec or sec <= 0 then return "0:00" end
    return string.format("%d:%02d", math.floor(sec/60), math.floor(sec%60))
end

-- 格式化时间戳 (HH:MM:SS)
function ns:FormatTimestamp(t)
    if not t then return "--:--:--" end
    return date("%H:%M:%S", t)
end

-- 安全数值读取 (12.0 Secret Values 兼容)
function ns:SafeNum(val)
    if val == nil then return 0 end
    if type(val) == "number" then return val end
    local ok, n = pcall(tonumber, val)
    return (ok and n) or 0
end

function ns:SafeStr(val)
    if type(val) == "string" then return val end
    if val == nil then return "" end
    local ok, s = pcall(tostring, val)
    return (ok and s) or ""
end

-- GUID相关
function ns:IsPlayerGUID(guid)
    return guid and guid:match("^Player%-") ~= nil
end

function ns:IsPetGUID(guid)
    return guid and (guid:match("^Pet%-") ~= nil or guid:match("^Creature%-") ~= nil)
end

-- ============================================================
-- Flag 常量
-- ============================================================
local AFFILIATION_MASK = 0x0000000F
local AFF_MINE         = 0x00000001
local AFF_PARTY        = 0x00000002
local AFF_RAID         = 0x00000004

local FLAG_PLAYER      = 0x00000400
local FLAG_PET         = 0x00001000
local FLAG_GUARDIAN    = 0x00002000

function ns:IsGroupUnit(flags, guid)
    if guid and guid == ns.state.playerGUID then
        return true
    end
    if not flags then return false end
    local aff = bit.band(flags, AFFILIATION_MASK)
    return aff == AFF_MINE or aff == AFF_PARTY or aff == AFF_RAID
end

function ns:IsPlayerType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PLAYER) ~= 0
end

function ns:IsPetType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PET + FLAG_GUARDIAN) ~= 0
end

-- ============================================================
-- GUID → Unit 缓存
-- ============================================================
ns._guidUnitCache    = {}
ns._guidUnitCacheAge = 0

function ns:InvalidateGUIDCache()
    ns._guidUnitCache    = {}
    ns._guidUnitCacheAge = GetTime()
end

function ns:FindUnitByGUID(guid)
    if guid == ns.state.playerGUID then return "player" end

    local cached = ns._guidUnitCache[guid]
    if cached and UnitExists(cached) and UnitGUID(cached) == guid then
        return cached
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local g = UnitGUID(unit)
            if g then
                ns._guidUnitCache[g] = unit
                if g == guid then return unit end
            end
        end
    end
    return nil
end

-- 获取宠物主人GUID
function ns:FindPetOwner(petGUID)
    if UnitExists("pet") and UnitGUID("pet") == petGUID then
        return UnitGUID("player")
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local petUnit = prefix .. "pet" .. i
        if UnitExists(petUnit) and UnitGUID(petUnit) == petGUID then
            return UnitGUID(prefix .. i)
        end
    end
    return nil
end

function ns:ShortName(name)
    if not name then return "?" end
    return name
end

function ns:DisplayName(name)
    if not name then return "?" end
    if issecretvalue and issecretvalue(name) then
        return name
    end
    if name == "" then return "?" end
    
    local ok, result = pcall(function()
        if ns.db and ns.db.display and ns.db.display.showRealm then
            return name:gsub("%-", " - ")
        else
            return name:match("^([^%-]+)") or name
        end
    end)
    
    if ok and result then return result end
    return name
end

-- 模式名称映射
ns.MODE_NAMES = {
    damage      = "伤害",
    healing     = "治疗",
    damageTaken = "承伤",
    deaths      = "死亡",
    interrupts  = "打断",
    dispels     = "驱散",
    enemyDamageTaken = "敌人承伤",
}

ns.MODE_SHORT = {
    damage          = "伤",
    healing         = "治",
    damageTaken     = "承",
    enemyDamageTaken= "敌",
    deaths          = "死",
    interrupts      = "断",
    dispels         = "驱",
    enemyDamageTaken= "敌",
}

ns.MODE_UNITS = {
    damage      = "DPS",
    healing     = "HPS",
    damageTaken = "DTPS",
}

ns.MODE_ORDER = { "damage", "healing", "damageTaken", "deaths", "interrupts", "dispels" }

function ns:NextMode(current)
    for i, m in ipairs(ns.MODE_ORDER) do
        if m == current then
            return ns.MODE_ORDER[(i % #ns.MODE_ORDER) + 1]
        end
    end
    return "damage"
end

function ns:FormatValueStr(perSec, total, mode, dur)
    local unit = ns.MODE_UNITS[mode]
    if unit and dur and dur > 0 then
        return string.format("%s(%s)", ns:FormatNumber(perSec), ns:FormatNumber(total))
    else
        return ns:FormatNumber(total)
    end
end

-- ============================================================
-- 工具函数 (从原 Core.lua 搬入)
-- ============================================================
function ns:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = CopyTable(v)
            else
                ns:MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end
