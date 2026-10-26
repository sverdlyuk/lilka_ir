-- ============================================================================
--  lang.lua — написи застосунку українською та англійською
--
--  Кожен напис має короткий англійський ключ. У коді замість тексту
--  пишеться T.ключ, наприклад T.devices.
--
--  %s і %d — місця, куди підставляються назви й числа. Речення
--  тримається цілим, щоб кожна мова сама ставила слова в своєму порядку.
--
--  Щоб додати мову: скопіювати блок en, перекласти, дописати код мови
--  в LANG_ORDER у remote.lua. Чого бракує в перекладі — показується
--  українською.
-- ============================================================================

return {
    uk = {
        lang_name = "Українська",
        app_name = "ІЧ-пульт",

        -- екрани
        devices = "Пристрої",
        menu = "Меню",
        settings = "Налаштування",
        about = "Про застосунок",
        learning = "Вивчення",
        test = "Тест передавача",

        -- пункти меню
        add = "Додати",
        rename = "Перейменувати",
        delete = "Видалити",
        learn = "Вивчити",

        -- налаштування
        tx = "Передавач",
        rx = "Приймач",
        language = "Мова",
        ready = "готовий",
        not_seen = "не бачу",

        -- кнопки внизу екрана
        open = "Відкрити",
        send = "Надіслати",
        choose = "Обрати",
        back = "Назад",
        exit = "Вихід",
        change = "Змінити",
        start = "Почати",
        protocol = "Протокол",

        -- клавіатура
        device_name = "Назва пристрою",
        new_name = "Нова назва",
        command_name = "Назва команди",

        -- списки
        empty = "Порожньо. Натисніть C.",

        -- вивчення
        listening = "Слухаю...",
        auto = "Авто",
        cancelled = "Скасовано",
        saved = "Збережено: %s",
        capture_failed = "Збій запису, натисніть ще раз",
        unknown_signal = "Невідомий сигнал (%d)",
        foreign_address = "Чужа адреса 0x%02X",
        already = "Це вже %s",
        receiver_missing = "приймач не бачу",

        -- тест передавача
        test_hint_1 = "Подивіться фронтальною",
        test_hint_2 = "камерою телефону —",
        test_hint_3 = "має блимати фіолетовим.",
    },

    en = {
        lang_name = "English",
        app_name = "IR Remote",

        devices = "Devices",
        menu = "Menu",
        settings = "Settings",
        about = "About",
        learning = "Learning",
        test = "Transmitter test",

        add = "Add",
        rename = "Rename",
        delete = "Delete",
        learn = "Learn",

        tx = "Transmitter",
        rx = "Receiver",
        language = "Language",
        ready = "ready",
        not_seen = "not found",

        open = "Open",
        send = "Send",
        choose = "Select",
        back = "Back",
        exit = "Exit",
        change = "Change",
        start = "Start",
        protocol = "Protocol",

        device_name = "Device name",
        new_name = "New name",
        command_name = "Command name",

        empty = "Empty. Press C.",

        listening = "Listening...",
        auto = "Auto",
        cancelled = "Cancelled",
        saved = "Saved: %s",
        capture_failed = "Capture failed, press again",
        unknown_signal = "Unknown signal (%d)",
        foreign_address = "Other address 0x%02X",
        already = "Already saved as %s",
        receiver_missing = "no receiver",

        test_hint_1 = "Look at the LED with",
        test_hint_2 = "the phone's front camera —",
        test_hint_3 = "it should blink purple.",
    },
}
