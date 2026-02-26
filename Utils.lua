--[[
    LD Combat Stats v0.1 - Utils.lua
    工具函数

    修复:
    - IsGroupUnit 加自身GUID兜底，单人打木桩时也能记录数据
    - IsGroupUnit 掩码从 0x0F 改为 0x07（affiliation 字段只有3位）
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
    
    -- 动态获取当前插件实际使用的语言
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
        -- Western formatting (K and M)
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
-- WoW CLEU flags 结构（低8位）:
--   bit 0-2 (0x07): Affiliation  1=自己 2=队伍 4=团队 8=外部 16=敌对
--   bit 3   (0x08): 未使用
--   bit 4-7 (0xF0): Reaction     1=友好 2=中立 4=敌对
-- ============================================================
local AFFILIATION_MASK = 0x0000000F   -- 取低4位做 affiliation 判断
local AFF_MINE         = 0x00000001   -- 自己
local AFF_PARTY        = 0x00000002   -- 队伍
local AFF_RAID         = 0x00000004   -- 团队

local FLAG_PLAYER      = 0x00000400
local FLAG_PET         = 0x00001000
local FLAG_GUARDIAN    = 0x00002000

-- ============================================================
-- IsGroupUnit：判断 GUID/flags 是否属于L["我方应记录的单位"]
--
-- 修复逻辑：
--   1. 优先用 GUID 判断自己（最可靠，不依赖 flags）
--   2. 再用 flags 的 affiliation 位判断队友
--   这样单人、组队、团队三种情况都能正确识别
-- ============================================================
function ns:IsGroupUnit(flags, guid)
    -- 1. GUID 兜底：自己永远算L["组内单位"]
    if guid and guid == ns.state.playerGUID then
        return true
    end

    if not flags then return false end

    -- 2. flags affiliation 位判断
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
-- GUID → Unit 缓存 (避免每次伤害都遍历团队)
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

    -- 重建缓存
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
    -- 自己的宠物
    if UnitExists("pet") and UnitGUID("pet") == petGUID then
        return UnitGUID("player")
    end

    -- 队友的宠物
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

-- 缩短名称 (不再强制去除服务器后缀，保证底层数据存储全名，实际截断在 DisplayName 进行)
function ns:ShortName(name)
    if not name then return "?" end
    return name
end

-- UI 显示时动态格式化
function ns:DisplayName(name)
    -- 1. 基础存在性判断（加密字符串允许进行是否为 nil 的布尔判断）
    if not name then return "?" end
    
    -- 2. 核心防爆：立刻拦截加密字符串！原样放行！（绝对不能放在比较之后）
    if issecretvalue and issecretvalue(name) then
        return name
    end
    
    -- 3. 拦截完毕后，确认它是普通字符串了，再做空字符串判断
    if name == "" then return "?" end
    
    -- 4. 正常的字符串截断或替换逻辑
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
}

ns.MODE_UNITS = {
    damage      = "DPS",
    healing     = "HPS",
    damageTaken = "DTPS",
}

-- 模式列表 (循环切换)
ns.MODE_ORDER = { "damage", "healing", "damageTaken", "deaths", "interrupts", "dispels" }

function ns:NextMode(current)
    for i, m in ipairs(ns.MODE_ORDER) do
        if m == current then
            return ns.MODE_ORDER[(i % #ns.MODE_ORDER) + 1]
        end
    end
    return "damage"
end

-- 格式化值字符串: L["DPS(总量)"] 样式
function ns:FormatValueStr(perSec, total, mode, dur)
    local unit = ns.MODE_UNITS[mode]
    if unit and dur and dur > 0 then
        return string.format("%s(%s)", ns:FormatNumber(perSec), ns:FormatNumber(total))
    else
        return ns:FormatNumber(total)
    end
end