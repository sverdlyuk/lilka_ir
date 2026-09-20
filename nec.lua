-- ============================================================================
--  nec.lua — протокол NEC
--
--  Перекладає між кодом команди і послідовністю спалахів світлодіода.
--  Нічого не знає ні про піни, ні про екран — лише числа.
--
--  Щоб додати інший протокол (Sony, RC5), зроби файл із такими самими
--  чотирма полями: name, carrier, encode, decode.
-- ============================================================================

local nec = {}

nec.name = "NEC"
nec.carrier = 38000 -- Гц; у Sony 40000, у RC5 36000

-- Тривалості в мікросекундах
local HDR_MARK = 9000 -- довгий стартовий спалах
local HDR_SPACE = 4500 -- пауза після нього
local BIT_MARK = 560 -- спалах перед кожним бітом
local ONE_SPACE = 1690 -- довга пауза = одиниця
local ZERO_SPACE = 560 -- коротка пауза = нуль

-- --- Кодування --------------------------------------------------------------
-- Повертає список: спалах, пауза, спалах, пауза...

local function push_byte(out, byte)
    for i = 0, 7 do -- NEC передає молодшим бітом уперед
        out[#out + 1] = BIT_MARK
        out[#out + 1] = ((byte >> i) & 1 == 1) and ONE_SPACE or ZERO_SPACE
    end
end

function nec.encode(address, command)
    local out = {HDR_MARK, HDR_SPACE}

    push_byte(out, address)
    push_byte(out, (~address) & 0xFF) -- інверсія адреси
    push_byte(out, command)
    push_byte(out, (~command) & 0xFF) -- інверсія команди

    out[#out + 1] = BIT_MARK -- стоповий біт
    return out
end

-- --- Декодування ------------------------------------------------------------
-- Приймає список тривалостей, повертає {address, command} або nil

local function near(value, target)
    return value > target * 0.7 and value < target * 1.3
end

function nec.decode(edges)
    if not edges or #edges < 67 then return nil end
    if not near(edges[1], HDR_MARK) then return nil end
    if not near(edges[2], HDR_SPACE) then return nil end

    -- збираємо 32 біти у чотири байти
    local bytes = {0, 0, 0, 0}
    for i = 0, 31 do
        local space = edges[4 + i * 2]
        if not space then return nil end
        if space > 1100 then
            bytes[(i // 8) + 1] = bytes[(i // 8) + 1] | (1 << (i % 8))
        end
    end

    -- другий байт має бути інверсією першого, четвертий — третього
    local valid = ((~bytes[1]) & 0xFF) == bytes[2]
        and ((~bytes[3]) & 0xFF) == bytes[4]

    return {
        address = bytes[1],
        command = bytes[3],
        valid = valid,
    }
end

return nec
