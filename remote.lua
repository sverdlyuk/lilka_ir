-- ============================================================================
--  remote.lua — ІЧ-пульт для Лілки v2
--
--  Модуль за схемою IR.md (vaddieg):
--      TX  GPIO21 (контакт 7 роз'єму розширення)
--      RX  GPIO14 (контакт 8)
--
--  Поряд мають лежати menu.lua і nec.lua.
--
--  Керування: стрілки — вибір, A — дія, B — назад, C — меню.
--
--  Пристрої зберігаються як звичайні txt просто на SD-карті:
--
--      name: Світильник
--      protocol: NEC
--      address: 0xA0
--
--      Увімкнути   0x13
--      Вимкнути    0x1A
--
--  Назва файлу не має значення — застосунок упізнає свої файли за
--  рядком "address:". Інші txt на картці не чіпаються.
-- ============================================================================

local menu = require("menu")
local nec = require("nec")

-- ---------------------------------------------------------------------------
-- 1. НАЛАШТУВАННЯ
-- ---------------------------------------------------------------------------

local TX_PIN = 21
local RX_PIN = 14
local PWM_CH = 6 -- канал LEDC; низькі зайняті бузером
local DUTY_ON = 85 -- ~1/3 від 255, стандарт для ІЧ

local CARD = "/sd" -- де шукати файли пристроїв

-- Компенсація часу виклику pwm.write(). Якщо приймач вередує — 0..30.
local MARK_TRIM = 0

local HOLD_DELAY = 0.5 -- скільки тримати A, перш ніж почнеться повтор
local HOLD_PERIOD = 0.12 -- як часто повторювати далі
local FLASH_TIME = 0.15 -- скільки підсвічувати рядок після надсилання

local APP_NAME = "ІЧ-пульт"
local APP_VERSION = "1.0"

-- ---------------------------------------------------------------------------
-- 2. ПРОТОКОЛИ
--    Щоб додати Sony — створити sony.lua і дописати його сюди.
-- ---------------------------------------------------------------------------

local protocols = {nec}

local function protocol_by_name(name)
    for _, p in ipairs(protocols) do
        if p.name == name then return p end
    end
    return protocols[1] -- якщо не впізнали — беремо перший
end

-- ---------------------------------------------------------------------------
-- 3. ЗАЛІЗО
-- ---------------------------------------------------------------------------

local spin_per_us = 1 -- скільки обертів порожнього циклу в одній мікросекунді

-- util.sleep() уміє лише мілісекунди, а нам потрібні сотні мікросекунд.
-- Тому заміряємо, наскільки швидка Лілка, і далі відмірюємо обертами.
local function calibrate()
    local N = 200000
    local t0 = util.time()
    for _ = 1, N do
    end
    local dt = util.time() - t0
    if dt > 0 then spin_per_us = N / (dt * 1000000) end
end

local function wait_us(us)
    for _ = 1, math.floor(us * spin_per_us) do
    end
end

local function carrier_on() pwm.write(PWM_CH, DUTY_ON) end
local function carrier_off() pwm.write(PWM_CH, 0) end

-- Блимає світлодіодом за списком: непарні числа — світити, парні — ні.
local function send_raw(durations, carrier)
    pwm.setup(PWM_CH, carrier, 8)
    pwm.attach_pin(TX_PIN, PWM_CH)

    for i, us in ipairs(durations) do
        if i % 2 == 1 then
            carrier_on()
            wait_us(us - MARK_TRIM)
            carrier_off()
        else
            wait_us(us)
        end
    end

    carrier_off()
end

-- Записує тривалості спалахів. Вихід приймача інверсний:
-- спокій = 1, несуча = 0.
local function capture_frame()
    local edges = {}
    local level = 0
    local t_prev = util.time()

    while #edges < 200 do
        local v = gpio.read(RX_PIN)
        local now = util.time()
        if v ~= level then
            edges[#edges + 1] = (now - t_prev) * 1000000
            t_prev = now
            level = v
        elseif level == 1 and (now - t_prev) > 0.015 then
            break -- 15 мс тиші = кадр скінчився
        end
    end

    return edges
end

-- Чекає початку кадру не довше за window секунд. Повертає true,
-- якщо кадр почався саме зараз (лінія була в спокої і впала).
local function wait_for_frame(window)
    if gpio.read(RX_PIN) == 0 then return false end -- кадр уже йде, пропускаємо

    local t0 = util.time()
    while (util.time() - t0) < window do
        if gpio.read(RX_PIN) == 0 then return true end
    end

    return false
end

-- Чи підключений приймач: у спокої на піні має бути одиниця.
local function receiver_ready()
    return gpio.read(RX_PIN) == 1
end

-- ---------------------------------------------------------------------------
-- 4. ФАЙЛИ
-- ---------------------------------------------------------------------------

local devices = {}

-- Читає один txt і складає з нього пристрій.
-- Повертає nil, якщо це чужий файл (немає рядка "address:").
local function read_device(path, filename)
    local f = fs.open(path, "r")
    if not f or not f:exists() then return nil end

    local text = f:read(f:size())
    if not text then return nil end

    local dev = {
        file = filename,
        name = filename,
        protocol = "NEC",
        address = 0,
        commands = {},
    }
    local is_ours = false

    for line in text:gmatch("[^\r\n]+") do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            local key, value = line:match("^(%a+):%s*(.-)%s*$")

            if key == "name" then
                dev.name = value
            elseif key == "protocol" then
                dev.protocol = value
            elseif key == "address" then
                dev.address = tonumber(value) or 0
                is_ours = true
            else
                -- рядок команди: назва, пробіли, шістнадцятковий код
                local name, code = line:match("^(.-)%s+(0[xX]%x+)%s*$")
                if name and code then
                    dev.commands[#dev.commands + 1] = {
                        name = name:gsub("%s+$", ""),
                        code = tonumber(code),
                    }
                end
            end
        end
    end

    if not is_ours then return nil end
    return dev
end

local function save_device(dev)
    local f = fs.open(CARD .. "/" .. dev.file, "w")
    if not f or not f:exists() then return false end

    f:write("# Пристрій для застосунку remote.lua на Лілці\n")
    f:write(string.format("name: %s\n", dev.name))
    f:write(string.format("protocol: %s\n", dev.protocol))
    f:write(string.format("address: 0x%02X\n\n", dev.address))

    for _, c in ipairs(dev.commands) do
        f:write(string.format("%-20s 0x%02X\n", c.name, c.code))
    end

    return true
end

local function load_devices()
    devices = {}

    local ok, entries = pcall(fs.ls, CARD)
    if not ok or not entries then return end

    for _, name in ipairs(entries) do
        if type(name) == "string" and name:lower():match("%.txt$") then
            local dev = read_device(CARD .. "/" .. name, name)
            if dev then devices[#devices + 1] = dev end
        end
    end

    table.sort(devices, function(a, b) return a.name < b.name end)
end

local function next_filename()
    local n = 1
    while true do
        local candidate = string.format("ir_%d.txt", n)
        local busy = false
        for _, d in ipairs(devices) do
            if d.file == candidate then busy = true end
        end
        if not busy then return candidate end
        n = n + 1
    end
end

-- ---------------------------------------------------------------------------
-- 5. СТАН
-- ---------------------------------------------------------------------------

local screen = "devices" -- devices | commands | learn | test | menu | about
local back_screen = nil -- куди повертає меню

local dev_list = menu.new_list()
local cmd_list = menu.new_list()
local menu_list = menu.new_list()
local menu_items = {}

local device = nil -- обраний пристрій

local flash = 0 -- підсвічування рядка після надсилання
local hold_timer = 0 -- скільки тримають A

local learn_status = "Натисніть кнопку на пульті"
local learn_last = nil -- останній спійманий код

local test_on = false
local test_timer = 0

-- ---------------------------------------------------------------------------
-- 6. МЕНЮ
-- ---------------------------------------------------------------------------

local function open_menu(items)
    menu_items = items
    menu_list = menu.new_list()
    back_screen = screen
    screen = "menu"
end

local function device_new()
    local name = menu.ask_text("Назва пристрою", "")
    if not name then return end

    local dev = {
        file = next_filename(),
        name = name,
        protocol = protocols[1].name,
        address = 0,
        commands = {},
    }

    save_device(dev)
    load_devices()

    for i, d in ipairs(devices) do
        if d.file == dev.file then dev_list.cursor = i end
    end
end

local function device_rename()
    local dev = devices[dev_list.cursor]
    if not dev then return end

    local name = menu.ask_text("Нова назва", dev.name)
    if not name then return end

    dev.name = name
    save_device(dev)
    load_devices()
end

local function device_delete()
    local dev = devices[dev_list.cursor]
    if not dev then return end

    fs.remove(CARD .. "/" .. dev.file)
    load_devices()
    dev_list = menu.new_list()
end

local function command_rename()
    local c = device.commands[cmd_list.cursor]
    if not c then return end

    local name = menu.ask_text("Нова назва", c.name)
    if not name then return end

    c.name = name
    save_device(device)
end

local function command_delete()
    if not device.commands[cmd_list.cursor] then return end

    table.remove(device.commands, cmd_list.cursor)
    save_device(device)
    cmd_list = menu.new_list()
end

local function menu_devices()
    open_menu({
        {label = "Новий пристрій", action = device_new},
        {label = "Перейменувати", action = device_rename},
        {label = "Видалити пристрій", action = device_delete},
        {label = "Оновити список", action = load_devices},
        {label = "Тест передавача", action = function() screen = "test" end},
        {label = "Про застосунок", action = function() screen = "about" end},
    })
end

local function menu_commands()
    open_menu({
        {label = "Вивчити команди", action = function()
            screen = "learn"
            learn_status = "Натисніть кнопку на пульті"
            learn_last = nil
        end},
        {label = "Перейменувати", action = command_rename},
        {label = "Видалити команду", action = command_delete},
        {label = "Тест передавача", action = function() screen = "test" end},
    })
end

-- ---------------------------------------------------------------------------
-- 7. ЕКРАНИ
-- ---------------------------------------------------------------------------

local function quit()
    carrier_off()
    pwm.detach_pin(TX_PIN)
    gpio.set_mode(TX_PIN, gpio.OUTPUT)
    gpio.write(TX_PIN, gpio.LOW)
    util.exit()
end

-- --- пристрої ---------------------------------------------------------------

local function update_devices(state)
    if state.up.just_pressed then menu.move(dev_list, #devices, -1) end
    if state.down.just_pressed then menu.move(dev_list, #devices, 1) end
    if state.c.just_pressed then menu_devices() end
    if state.b.just_pressed then quit() end

    if state.a.just_pressed and devices[dev_list.cursor] then
        device = devices[dev_list.cursor]
        cmd_list = menu.new_list()
        screen = "commands"
    end
end

local function draw_devices()
    local items = {}
    for _, d in ipairs(devices) do
        items[#items + 1] = {
            label = d.name,
            right = string.format("%d", #d.commands),
        }
    end

    menu.draw_list("Пристрої", nil, items, dev_list, false)
    menu.draw_footer({
        {key = "A", label = "Відкрити"},
        {key = "C", label = "Меню"},
        {key = "B", label = "Вихід"},
    })
end

-- --- команди ----------------------------------------------------------------

local function send_command(c)
    local proto = protocol_by_name(device.protocol)
    send_raw(proto.encode(device.address, c.code), proto.carrier)
    c.count = (c.count or 0) + 1
    flash = FLASH_TIME
end

local function update_commands(state, delta)
    local items = device.commands

    if state.up.just_pressed then menu.move(cmd_list, #items, -1) end
    if state.down.just_pressed then menu.move(cmd_list, #items, 1) end
    if state.c.just_pressed then menu_commands() end
    if state.b.just_pressed then
        screen = "devices"
        return
    end

    local c = items[cmd_list.cursor]
    if not c then return end

    -- Натиснув і відпустив — одне надсилання. Потримав — пішов повтор,
    -- як на клавіатурі.
    if state.a.just_pressed then
        send_command(c)
        hold_timer = 0
    elseif state.a.pressed then
        hold_timer = hold_timer + delta
        if hold_timer >= HOLD_DELAY then
            send_command(c)
            hold_timer = HOLD_DELAY - HOLD_PERIOD
        end
    end
end

local function draw_commands()
    local items = {}
    for _, c in ipairs(device.commands) do
        local right = string.format("%02X", c.code)
        if c.count and c.count > 0 then
            right = string.format("x%d  %s", c.count, right)
        end
        items[#items + 1] = {label = c.name, right = right}
    end

    menu.draw_list(
        device.name,
        string.format("%s %02X", device.protocol, device.address),
        items, cmd_list, flash > 0
    )
    menu.draw_footer({
        {key = "A", label = "Надіслати"},
        {key = "C", label = "Меню"},
        {key = "B", label = "Назад"},
    })
end

-- --- вивчення ---------------------------------------------------------------

-- Чи є вже така команда в пристрої
local function find_command(code)
    for _, c in ipairs(device.commands) do
        if c.code == code then return c end
    end
    return nil
end

local function learn_save(result)
    local name = menu.ask_text("Назва команди", "")
    if not name then
        learn_status = "Скасовано"
        return
    end

    if device.address == 0 then device.address = result.address end

    device.commands[#device.commands + 1] = {name = name, code = result.command}
    save_device(device)

    learn_status = string.format("Збережено: %s", name)
end

local function update_learn(state)
    if state.b.just_pressed then
        screen = "commands"
        return
    end

    -- Слухаємо постійно, без натискання кнопки.
    if not wait_for_frame(0.05) then return end

    local edges = capture_frame()

    -- пробуємо всі відомі протоколи, доки хтось не впізнає кадр
    local result, proto = nil, nil
    for _, p in ipairs(protocols) do
        result = p.decode(edges)
        if result then
            proto = p
            break
        end
    end

    if not result then
        learn_status = string.format("Невідомий сигнал (%d)", #edges)
        learn_last = nil
        return
    end

    learn_last = result

    if device.address ~= 0 and result.address ~= device.address then
        learn_status = string.format("Чужа адреса 0x%02X", result.address)
        return
    end

    local existing = find_command(result.command)
    if existing then
        learn_status = string.format("Це вже %s", existing.name)
        return
    end

    if device.protocol ~= proto.name then device.protocol = proto.name end
    learn_save(result)
end

local function draw_learn()
    local items = {}

    if learn_last then
        items[#items + 1] = {
            label = string.format("addr 0x%02X", learn_last.address),
        }
        items[#items + 1] = {
            label = string.format("cmd  0x%02X", learn_last.command),
        }
    end

    menu.draw_list(
        "Вивчення",
        receiver_ready() and "приймач готовий" or "приймач не бачу",
        items, menu.new_list(), false
    )

    display.set_font("6x13")
    display.set_text_color(display.color565(255, 255, 255))
    display.set_cursor(menu.PAD_X, display.height - 46)
    display.print(learn_status)

    menu.draw_footer({{key = "B", label = "Досить"}})
end

-- --- тест -------------------------------------------------------------------

local function update_test(state, delta)
    if state.b.just_pressed then
        carrier_off()
        test_on = false
        screen = device and "commands" or "devices"
        return
    end

    test_timer = test_timer + delta
    if test_timer >= 0.5 then
        test_timer = 0
        test_on = not test_on
        if test_on then carrier_on() else carrier_off() end
    end
end

local function draw_test()
    display.fill_screen(display.color565(0, 0, 0))

    display.set_font("10x20")
    display.set_text_color(display.color565(0, 220, 220))
    display.set_cursor(menu.PAD_X, 26)
    display.print("Тест передавача")
    display.draw_line(menu.PAD_X - 4, 36, display.width - menu.PAD_X + 4, 36,
                      display.color565(60, 60, 60))

    display.set_font("6x13")
    display.set_text_color(display.color565(130, 130, 130))
    display.set_cursor(menu.PAD_X, 60)
    display.print("Подивіться фронтальною")
    display.set_cursor(menu.PAD_X, 76)
    display.print("камерою телефону —")
    display.set_cursor(menu.PAD_X, 92)
    display.print("має блимати фіолетовим.")

    local cx = display.width // 2
    local cy = 150
    if test_on then
        display.fill_circle(cx, cy, 24, display.color565(240, 180, 40))
    else
        display.draw_circle(cx, cy, 24, display.color565(60, 60, 60))
    end

    menu.draw_footer({{key = "B", label = "Назад"}})
end

-- --- про застосунок ---------------------------------------------------------

local function update_about(state)
    if state.b.just_pressed then screen = "devices" end
end

local function draw_about()
    display.fill_screen(display.color565(0, 0, 0))

    display.set_font("10x20")
    display.set_text_color(display.color565(0, 220, 220))
    display.set_cursor(menu.PAD_X, 26)
    display.print(APP_NAME .. "  " .. APP_VERSION)
    display.draw_line(menu.PAD_X - 4, 36, display.width - menu.PAD_X + 4, 36,
                      display.color565(60, 60, 60))

    local lines = {
        "Схема модуля: IR.md",
        "",
        "TX  GPIO21  (контакт 7)",
        "RX  GPIO14  (контакт 8)",
        "",
        "Пристрої: /sd/*.txt",
        "Протоколи: " .. protocols[1].name,
    }

    display.set_font("6x13")
    for i, line in ipairs(lines) do
        display.set_text_color(display.color565(190, 190, 190))
        display.set_cursor(menu.PAD_X, 58 + (i - 1) * 16)
        display.print(line)
    end

    menu.draw_footer({{key = "B", label = "Назад"}})
end

-- --- меню -------------------------------------------------------------------

local function update_menu(state)
    if state.up.just_pressed then menu.move(menu_list, #menu_items, -1) end
    if state.down.just_pressed then menu.move(menu_list, #menu_items, 1) end

    if state.b.just_pressed or state.c.just_pressed then
        screen = back_screen
        return
    end

    if state.a.just_pressed then
        local item = menu_items[menu_list.cursor]
        screen = back_screen -- дія може перемкнути екран сама
        if item and item.action then item.action() end
    end
end

local function draw_menu()
    local items = {}
    for _, m in ipairs(menu_items) do
        items[#items + 1] = {label = m.label}
    end

    menu.draw_list("Меню", nil, items, menu_list, false)
    menu.draw_footer({
        {key = "A", label = "Обрати"},
        {key = "B", label = "Назад"},
    })
end

-- ---------------------------------------------------------------------------
-- 8. ЖИТТЄВИЙ ЦИКЛ
-- ---------------------------------------------------------------------------

function lilka.init()
    calibrate()

    pwm.setup(PWM_CH, protocols[1].carrier, 8)
    pwm.attach_pin(TX_PIN, PWM_CH)
    carrier_off()

    gpio.set_mode(RX_PIN, gpio.INPUT)

    menu.init()
    load_devices()
end

function lilka.update(delta)
    local state = controller.get_state()
    if flash > 0 then flash = flash - delta end

    if screen == "devices" then
        update_devices(state)
    elseif screen == "commands" then
        update_commands(state, delta)
    elseif screen == "learn" then
        update_learn(state)
    elseif screen == "test" then
        update_test(state, delta)
    elseif screen == "about" then
        update_about(state)
    elseif screen == "menu" then
        update_menu(state)
    end
end

function lilka.draw()
    if screen == "devices" then
        draw_devices()
    elseif screen == "commands" then
        draw_commands()
    elseif screen == "learn" then
        draw_learn()
    elseif screen == "test" then
        draw_test()
    elseif screen == "about" then
        draw_about()
    elseif screen == "menu" then
        draw_menu()
    end
end
