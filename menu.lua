-- ============================================================================
--  menu.lua — інтерфейс для застосунків Лілки
--
--  Малює списки, меню і підказки внизу екрана, показує клавіатуру
--  та повідомлення. Нічого не знає про той застосунок, що його викликає,
--  тому файл можна брати в будь-який інший проєкт.
--
--  Використання:
--      local menu = require("menu")
--      menu.init()                         -- один раз у lilka.init
--      local list = menu.new_list()        -- на кожен список свій
--      menu.move(list, #items, 1)          -- рух курсора
--      menu.draw_list("Заголовок", nil, items, list)
--      menu.draw_footer({{key="A", label="Обрати"}})
-- ============================================================================

local menu = {}

-- --- Вигляд -----------------------------------------------------------------

menu.PAD_X = 14 -- відступ від краю; дисплей у корпусі має закруглення,
menu.PAD_Y = 14 -- тому по краях кілька пікселів не видно

local FONT_BIG = "10x20"
local FONT_SMALL = "6x13"
local CHAR_BIG = 10
local CHAR_SMALL = 6
local ROW_H = 24

local BLACK = display.color565(0, 0, 0)
local WHITE = display.color565(255, 255, 255)
local GRAY = display.color565(130, 130, 130)
local CYAN = display.color565(0, 220, 220)
local DIM = display.color565(120, 120, 130) -- невибрані рядки
local DIM_RIGHT = display.color565(80, 80, 90) -- їхні значення праворуч
local OK = display.color565(45, 210, 130) -- смужка в мить надсилання
local LINE = display.color565(60, 60, 60)

-- Колір закріплений за літерою, а не за місцем у ряду: червоний завжди
-- означає "назад", і користувач перестає читати підписи.
local KEY_COLORS = {
    A = display.color565(45, 210, 130),
    B = display.color565(255, 95, 95),
    C = display.color565(255, 193, 40),
    D = display.color565(90, 165, 255),
}

menu.rows = 6 -- скільки рядків списку влазить; рахується в init

-- Довжина рядка в символах, а не в байтах: українські літери займають
-- по два байти, тому #text дав би вдвічі більшу ширину.
local function text_width(text, char_w)
    return (utf8.len(text) or #text) * char_w
end

-- --- Ініціалізація ----------------------------------------------------------

function menu.init()
    menu.rows = math.floor((display.height - 86) / ROW_H)
    if menu.rows < 3 then menu.rows = 3 end
end

-- --- Курсор і прокрутка -----------------------------------------------------

function menu.new_list()
    return {cursor = 1, scroll = 0}
end

-- Рухає курсор і, якщо він сховався за краєм екрана, підкручує прокрутку.
function menu.move(list, count, step)
    if count == 0 then return end

    list.cursor = list.cursor + step
    if list.cursor < 1 then list.cursor = count end
    if list.cursor > count then list.cursor = 1 end

    if list.cursor - 1 < list.scroll then
        list.scroll = list.cursor - 1
    elseif list.cursor > list.scroll + menu.rows then
        list.scroll = list.cursor - menu.rows
    end
end

-- --- Малювання --------------------------------------------------------------

-- items — масив {label = "текст", right = "значення"}
-- highlight — підсвітити обраний рядок зеленим (щось щойно спрацювало)
function menu.draw_list(title, hint, items, list, highlight)
    display.fill_screen(BLACK)

    display.set_font(FONT_BIG)
    display.set_text_color(CYAN)
    display.set_cursor(menu.PAD_X, 26)
    display.print(title)

    if hint then
        display.set_font(FONT_SMALL)
        display.set_text_color(GRAY)
        display.set_cursor(display.width - menu.PAD_X - text_width(hint, CHAR_SMALL), 24)
        display.print(hint)
    end

    display.draw_line(menu.PAD_X - 4, 36, display.width - menu.PAD_X + 4, 36, LINE)

    if #items == 0 then
        display.set_font(FONT_SMALL)
        display.set_text_color(GRAY)
        display.set_cursor(menu.PAD_X, 70)
        display.print("Порожньо. Натисніть C.")
    end

    for i = 1, menu.rows do
        local item = items[list.scroll + i]
        if item then
            local y = 36 + i * ROW_H
            local selected = (list.scroll + i == list.cursor)

            -- Обраний рядок не заливаємо, а навпаки приглушуємо решту:
            -- на маленькому екрані це менше шуму. Кольорова смужка
            -- зліва працює якорем для ока.
            if selected then
                display.fill_rect(
                    menu.PAD_X - 10, y - 15, 4, ROW_H - 8,
                    highlight and OK or CYAN
                )
                display.set_text_color(WHITE)
            else
                display.set_text_color(DIM)
            end

            display.set_font(FONT_BIG)
            display.set_cursor(menu.PAD_X, y)
            display.print(item.label)

            if item.right then
                display.set_font(FONT_SMALL)
                display.set_text_color(selected and WHITE or DIM_RIGHT)
                display.set_cursor(
                    display.width - menu.PAD_X - text_width(item.right, CHAR_SMALL),
                    y - 2
                )
                display.print(item.right)
            end
        end
    end
end

-- buttons — масив {key = "A", label = "Надіслати"}
-- Кружечок повторює форму справжніх кнопок Лілки, тому читається
-- швидше за будь-яку іншу фігуру.
function menu.draw_footer(buttons)
    local R = 11 -- радіус кружечка
    local GAP = 12 -- відстань між кнопками
    local KEY_GAP = 5 -- від кружечка до підпису

    local CHAR = 9 -- ширина символу шрифту 9x15
    local FONT = "9x15"

    -- спершу рахуємо загальну ширину, щоб поставити ряд по центру
    local total = 0
    for i, b in ipairs(buttons) do
        total = total + R * 2 + KEY_GAP + text_width(b.label, CHAR)
        if i < #buttons then total = total + GAP end
    end

    local x = (display.width - total) // 2
    local y = display.height - menu.PAD_Y - R

    display.set_font(FONT)

    for _, b in ipairs(buttons) do
        display.fill_circle(x + R, y, R, KEY_COLORS[b.key] or GRAY)

        -- літера всередині кружечка, темна для контрасту
        display.set_text_color(BLACK)
        display.set_cursor(x + R - CHAR // 2, y + 5)
        display.print(b.key)

        display.set_text_color(WHITE)
        display.set_cursor(x + R * 2 + KEY_GAP, y + 5)
        display.print(b.label)

        x = x + R * 2 + KEY_GAP + text_width(b.label, CHAR) + GAP
    end
end

-- --- Діалоги ----------------------------------------------------------------
-- Обидва зупиняють застосунок, доки користувач не закриє вікно.

function menu.ask_text(title, default)
    local kb = keyboardUI(title)
    if default and default ~= "" then kb:setValue(default) end

    while not kb:isFinished() do
        kb:update()
        kb:draw()
    end

    local value = kb:getValue()
    if value == nil or value == "" then return nil end
    return value
end

function menu.alert(title, message)
    local a = alertUI(title, message)
    while not a:isFinished() do
        a:update()
        a:draw()
    end
end

return menu
