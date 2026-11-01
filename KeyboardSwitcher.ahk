; KeyboardSwitcher v0.83
#Requires AutoHotkey v2.0
#SingleInstance Off

if (!WinExist("ahk_class Shell_TrayWnd")) {
    while (!WinExist("ahk_class Shell_TrayWnd"))
        Sleep 1000
    Sleep 3000
}
; Принудительная перерегистрация иконки (нужна, т.к. AHK уже попытался
; её создать при старте — и мог провалиться, пока трей не был готов)
A_IconHidden := true
Sleep 200
A_IconHidden := false
A_IconTip := "KeyboardSwitcher"

iniFile := A_ScriptDir "\KeyboardSwitcher.ini"
taskName := "KeyboardSwitcher"
exePath := A_ScriptFullPath
taskFile := A_WinDir "\System32\Tasks\" taskName

; Глобальные переменные для жесткого отслеживания активных хоткеев раскладки
global currentRuKey := ""
global currentEnKey := ""

; Флаг, чтобы ToolTip не перерисовывался каждую миллисекунду в цикле
global isTipShown := false

; Глобальный массив для хранения кастомных строк (индексы 1..12 соответствуют кнопкам 1..0, -, =)
global customStrings := Array()
loop 12
    customStrings.Push("")

; --- 1. Кастомизация контекстного меню иконки в трее (возле часов) ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Открыть настройки", (*) => OpenSettingsAndWatch()) 
A_TrayMenu.Add()                                    ; ← разделитель
A_TrayMenu.Add("Выход", (*) => ExitApp()) 
A_TrayMenu.Default := "Открыть настройки"           ; ← двойной клик по иконке = открыть настройки

; --- 2. Создание файла настроек по умолчанию, если его нет ---
if (FileExist(iniFile) = "") {
    iniText := "
(
; KeyboardSwitcher settings (не удалять эту строку - поглощает BOM старого Блокнота)
[LanguageSwitch]
; Клавиша для включения РУССКОГО языка. (RShift, LShift или 0 для отключения)
RussianKey=RShift

; Клавиша для включения АНГЛИЙСКОГО языка. (RShift, LShift или 0 для отключения)
EnglishKey=LShift

[Features]
; Режим работы унификации точки и запятой на клавише '/' (SC035 возле правого Shift):
; 0 - Вообще всё выключено (стандартное поведение Windows, по умолчанию).
; 1 - Включено безусловно (Одиночное нажатие - всегда точка, с Shift - всегда запятая).
; 2 - Включено + работают модификаторы: Одиночное нажатие пишет точку (с Shift - запятую). 
;     Но при совместном удержании клавиш поведение меняется:
;       - Зажатый ЛЮБОЙ Alt + клавиша точки = ВСЕГДА выводит косую черту (/)
;       - Зажатый ЛЮБОЙ Ctrl + клавиша точки = ВСЕГДА выводит знак вопроса (?)
FixDotMode=0

; Включение кастомных макросов, спецсимволов или фраз на Правый Alt (AltGr) независимо от режимов точки:
; 1 - Включено (по умолчанию), 0 - Выключено.
CustomAltGr=1

; Умная вставка чистого текста по Ctrl+Alt+V с автопереключением раскладки (RU/EN) под текст.
; 1 - включено, 0 - выключено.
PastePlain=1

; 1 - автозагрузка включена через Планировщик Windows, 0 - выключена
AutoStart=0

[CustomAltGr]
; Напишите здесь любой текст, символ или целую фразу, которая будет мгновенно вставляться при зажатом Правом Альте.
; Если вам нужно сохранить ПРОБЕЛЫ в начале или в конце строки, оберните её в кавычки, например: " ₽ с НДС 22 %"
; Если оставить поле пустым — клавиша сохранит стандартное поведение Windows.
Key_1=
Key_2=
Key_3=
Key_4=
Key_5=
Key_6=
Key_7=
Key_8=" ₽"
Key_9=м²
Key_0=°
Key_Minus=⌀
Key_Equal=≈
)"
    FileAppend(iniText, iniFile, "UTF-8-RAW")
}

; --- 3. Чтение настроек и динамическая инициализация горячих клавиш ---
ReadSettingsAndInit() {
    global ruKey, enKey, fixDotMode, customAltGr, pastePlain, autoStart, iniFile, customStrings
    global currentRuKey, currentEnKey
    
    ; Удаления старых хоткеев из памяти при перезаписи на лету
    if (currentRuKey != "") {
        try Hotkey("~" currentRuKey " Up", SwitchToRussian, "Off")
    }
    if (currentEnKey != "") {
        try Hotkey("~" currentEnKey " Up", SwitchToEnglish, "Off")
    }
    
    loop 12
        customStrings[A_Index] := ""
        
    ruKey := IniRead(iniFile, "LanguageSwitch", "RussianKey", "")
    enKey := IniRead(iniFile, "LanguageSwitch", "EnglishKey", "")
    fixDotMode := IniRead(iniFile, "Features", "FixDotMode", "0")
    customAltGr := IniRead(iniFile, "Features", "CustomAltGr", "1")
    pastePlain := IniRead(iniFile, "Features", "PastePlain", "1")
    autoStart := IniRead(iniFile, "Features", "AutoStart", "0")
    
    ; UTF-8 парсер макросов
    try {
        fileObj := FileOpen(iniFile, "r", "UTF-8")
        isInSection := false
        while !fileObj.AtEOF {
            line := Trim(fileObj.ReadLine())
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            if (line = "[CustomAltGr]") {
                isInSection := true
                continue
            }
            if (isInSection && SubStr(line, 1, 1) = "[") {
                isInSection := false
            }
            if (isInSection && InStr(line, "=")) {
                parts := SplitIniLine(line)
                keyName := StrLower(parts[1])
                val := parts[2]
                
                if (SubStr(val, 1, 1) = '"' && SubStr(val, -1) = '"' && StrLen(val) >= 2) {
                    val := SubStr(val, 2, StrLen(val) - 2)
                }
                
                if (keyName = "key_1")
                    customStrings[1] := val
                else if (keyName = "key_2")
                    customStrings[2] := val
                else if (keyName = "key_3")
                    customStrings[3] := val
                else if (keyName = "key_4")
                    customStrings[4] := val
                else if (keyName = "key_5")
                    customStrings[5] := val
                else if (keyName = "key_6")
                    customStrings[6] := val
                else if (keyName = "key_7")
                    customStrings[7] := val
                else if (keyName = "key_8")
                    customStrings[8] := val
                else if (keyName = "key_9")
                    customStrings[9] := val
                else if (keyName = "key_0")
                    customStrings[10] := val
                else if (keyName = "key_minus")
                    customStrings[11] := val
                else if (keyName = "key_equal")
                    customStrings[12] := val
            }
        }
        fileObj.Close()
    }
    
    validRu := (ruKey = "0" || ruKey = "") ? "" : ruKey
    validEn := (enKey = "0" || enKey = "") ? "" : enKey
    
    currentRuKey := validRu
    currentEnKey := validEn
    
    if (validRu != "") {
        try Hotkey("~" validRu " Up", SwitchToRussian, "On")
    }
    if (validEn != "") {
        try Hotkey("~" validEn " Up", SwitchToEnglish, "On")
    }
    
    if (customAltGr = "1") {
        SetTimer WatchAltGr, 50
    } else {
        SetTimer WatchAltGr, 0
        ToolTip
    }
}

; Горизонтальная шпаргалка над часами Windows с кнопками в скобках [ ]
WatchAltGr() {
    global isTipShown, customStrings

    ; RAlt зажат, а Ctrl / LAlt / Shift — НЕТ
    isPressed := GetKeyState("RAlt", "P")
      && !GetKeyState("LAlt", "P")
      && !GetKeyState("RControl", "P")
      && !GetKeyState("LShift", "P")
      && !GetKeyState("RShift", "P")

    if (isPressed) {
        if (!isTipShown) {
            tipText := ""
            if (customStrings[1] != "")
                tipText .= "[1] → " customStrings[1] "      "
            if (customStrings[2] != "")
                tipText .= "[2] → " customStrings[2] "      "
            if (customStrings[3] != "")
                tipText .= "[3] → " customStrings[3] "      "
            if (customStrings[4] != "")
                tipText .= "[4] → " customStrings[4] "      "
            if (customStrings[5] != "")
                tipText .= "[5] → " customStrings[5] "      "
            if (customStrings[6] != "")
                tipText .= "[6] → " customStrings[6] "      "
            if (customStrings[7] != "")
                tipText .= "[7] → " customStrings[7] "      "
            if (customStrings[8] != "")
                tipText .= "[8] → " customStrings[8] "      "
            if (customStrings[9] != "")
                tipText .= "[9] → " customStrings[9] "      "
            if (customStrings[10] != "")
                tipText .= "[0] → " customStrings[10] "      "
            if (customStrings[11] != "")
                tipText .= "[-] → " customStrings[11] "      "
            if (customStrings[12] != "")
                tipText .= "[=] → " customStrings[12] "      "

            if (Trim(tipText) != "") {
                targetX := A_ScreenWidth - 550
                targetY := A_ScreenHeight - 75
                ToolTip RTrim(tipText), targetX, targetY
                isTipShown := true
            }
        }
    } else {
        if (isTipShown) {
            ToolTip
            isTipShown := false
        }
    }
}
SplitIniLine(line) {
    pos := InStr(line, "=")
    if (pos = 0)
        return [line, ""]
    key := Trim(SubStr(line, 1, pos - 1))
    val := SubStr(line, pos + 1)
    
    valTrim := Trim(val)
    if (!(SubStr(valTrim, 1, 1) = '"' && SubStr(valTrim, -1) = '"')) {
        if (InStr(val, ";") && !InStr(val, " `;")) {
            cPos := InStr(val, ";")
            val := SubStr(val, 1, cPos - 1)
        }
    }
    return [key, Trim(val)]
}

ReadSettingsAndInit()

; --- 4. Проверка и управление копиями ---
myPID := DllCall("GetCurrentProcessId")
DetectHiddenWindows(true)

for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process Where Name = '" A_ScriptName "'") {
    if (proc.ProcessId != myPID) {
        if WinExist("ahk_pid " proc.ProcessId " ahk_class AutoHotkey") {
            WinClose("ahk_pid " proc.ProcessId " ahk_class AutoHotkey")
            Sleep(200)
        }
        
        checkStillExists := RunWait(A_ComSpec " /c tasklist /FI `"PID eq " proc.ProcessId "`" | find `"" proc.ProcessId "`"", , "Hide")
        if (checkStillExists = 0) {
            errCode := RunWait(A_ComSpec " /c taskkill /F /PID " proc.ProcessId, , "Hide")
            
           if (errCode != 0) {
              if (!A_IsAdmin) {
                MsgBox("Предыдущая копия программы запущенна ОТ ИМЕНИ АДМИНИСТРАТОРА!`n`nЧтобы перезапустить программу и обновить настройки, запустите этот файл вручную ОТ ИМЕНИ АДМИНИСТРАТОРА.", "Требуется запуск от Админа", 48)
                ExitApp
            } else {
              MsgBox("Не удалось закрыть предыдущую копию (PID " proc.ProcessId ").", "Ошибка", 48)
              ; опционально ExitApp
            }
          }
        }
    }
}

; --- 5. Логика управления Планировщиком заданий ---
ManageTaskScheduler() {
    global taskFile, autoStart, taskName, exePath
    taskExists := FileExist(taskFile)

    if (autoStart = "1") {
        needCreate := (taskExists = "")

        if (!needCreate) {
            try {
                taskContent := FileRead(taskFile)   ; авто-детект UTF-16 BOM
                if (!InStr(taskContent, exePath))
                    needCreate := true
            } catch {
                needCreate := true
            }
        }

        if (needCreate) {
            if (!A_IsAdmin) {
                MsgBox("В настройках изменен AutoStart, требуется создание задачи автозагрузки.`n`nПрограмма откроет папку в Проводнике ...", "Требуется запуск от Admina", 48)
                Run("explorer.exe /select,`"" exePath "`"")
                ExitApp
            }

            cmd := 'schtasks /create /tn "' taskName '" /tr "\"' exePath '\"" /sc onlogon /rl highest /f'
            psCmd := '$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries; Set-ScheduledTask -TaskName "' taskName '" -Settings $s'

            exitCreate := RunWait(A_ComSpec " /c " cmd, , "Hide")
            exitPs := RunWait("powershell -Command " psCmd, , "Hide")

            if (exitCreate != 0) {
                MsgBox("schtasks /create вернул код " exitCreate " — задача НЕ создана.", "Ошибка", 48)
            } else if (exitPs != 0) {
                MsgBox("Задача создана, но настройки батареи не применены (PowerShell код " exitPs ").`nЗадача может не запускаться от батареи.", "Предупреждение", 48)
            } else if (taskExists = "") {
                MsgBox("Программа успешно добавлена в автозагрузку Планировщика задач!", "Успешно", 64)
            }
        }
    } else if (autoStart = "0") {
        if (taskExists != "") {
            if (!A_IsAdmin) {
                MsgBox("Вы отключили AutoStart в настройках, но задача автозагрузки осталась в системе.`n`nПрограмма откроет папку в Проводнике ...", "Требуется запуск от Admina", 48)
                Run("explorer.exe /select,`"" exePath "`"")
                ExitApp
            }
            exitDelete := RunWait(A_ComSpec ' /c schtasks /delete /tn "' taskName '" /f', , "Hide")
            if (exitDelete = 0)
                MsgBox("Задача автозагрузки успешно удалена.", "Успешно", 64)
            else
                MsgBox("schtasks /delete вернул код " exitDelete " — задача НЕ удалена.", "Ошибка", 48)
        }
    }
}

ManageTaskScheduler()

; --- 6. Функция динамического отслеживания Блокнота ---
OpenSettingsAndWatch() {
    global iniFile, autoStart
    oldAutoStart := autoStart 
    
    RunWait('notepad.exe "' . iniFile . '"')
    
    ReadSettingsAndInit()
    
    if (autoStart != oldAutoStart) {
        ManageTaskScheduler()
    }
}

; --- 7. Функции переключения языков (Регистронезависимое сравнение строк) ---
SwitchToRussian(hk) {
    cleanKey := RegExReplace(hk, "[~*$!^+]")
    cleanKey := StrReplace(cleanKey, " Up")
    
    sysKey := cleanKey
    if (StrCompare(cleanKey, "LShift", false) = 0 || StrCompare(cleanKey, "RShift", false) = 0)
        sysKey := "Shift"
        
    if (StrCompare(A_PriorKey, sysKey, false) = 0 || StrCompare(A_PriorKey, cleanKey, false) = 0) {
        ForceSwitchLang(0x04190419)
    }
}

SwitchToEnglish(hk) {
    cleanKey := RegExReplace(hk, "[~*$!^+]")
    cleanKey := StrReplace(cleanKey, " Up")
    
    sysKey := cleanKey
    if (StrCompare(cleanKey, "LShift", false) = 0 || StrCompare(cleanKey, "RShift", false) = 0)
        sysKey := "Shift"
        
    if (StrCompare(A_PriorKey, sysKey, false) = 0 || StrCompare(A_PriorKey, cleanKey, false) = 0) {
        ForceSwitchLang(0x04090409)
    }
}

ForceSwitchLang(hkl) {
    hwnd := WinExist("A")
    if (!hwnd)
        return
        
    ; 1. Безопасно пытаемся отправить в элемент с фокусом (список файлов, поле ввода)
    try {
        focusClass := ControlGetFocus("A")
        if (focusClass != "") {
            focusHwnd := ControlGetHwnd(focusClass, "A")
            if (focusHwnd) {
                PostMessage(0x0050, 0, hkl, , "ahk_id " focusHwnd)
                return ; Успешно отправили в поле ввода, в окно уже не шлем
            }
        }
    }
    
    ; 2. Если поля ввода нет, отправляем в само окно
    PostMessage(0x0050, 0, hkl, , "ahk_id " hwnd)
}

; --- 8. Обработка режимов FixDotMode ---
#HotIf fixDotMode = "1"
*SC035:: {
    if GetKeyState("Shift", "P")
        SendChar(",")
    else
        SendChar(".")
}
#HotIf

#HotIf fixDotMode = "2"
*!SC035:: SendChar("/")
*^SC035:: {
    ; В русской раскладке RAlt = AltGr (Ctrl+Alt), поэтому срабатывает и этот хоткей.
    ; Различаем по физическому состоянию правого Alt.
    if GetKeyState("RAlt", "P")
        SendChar("/")
    else
        SendChar("?")
}
*SC035:: {
    if GetKeyState("Shift", "P")
        SendChar(",")
    else
        SendChar(".")
}
#HotIf

; Отправка символа: PostMessage только для привилегированных консолей, иначе — обычный Send
SendChar(char) {
    if (WinActive("ahk_class ConsoleWindowClass") && A_IsAdmin) {
        hwnd := WinExist("A")
        if (hwnd)
            PostMessage(0x0102, Ord(char), 1, , "ahk_id " hwnd)
        return
    }
    Send char
}

; --- 9. Блок ввода макросов ---
#HotIf customAltGr = "1" && GetKeyState("RAlt", "P") && !GetKeyState("LAlt", "P") && !GetKeyState("RControl", "P") && !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")
*$sc002:: HandleAltGrKey(1, "sc002")
*$sc003:: HandleAltGrKey(2, "sc003")
*$sc004:: HandleAltGrKey(3, "sc004")
*$sc005:: HandleAltGrKey(4, "sc005")
*$sc006:: HandleAltGrKey(5, "sc006")
*$sc007:: HandleAltGrKey(6, "sc007")
*$sc008:: HandleAltGrKey(7, "sc008")
*$sc009:: HandleAltGrKey(8, "sc009")
*$sc00A:: HandleAltGrKey(9, "sc00A")
*$sc00B:: HandleAltGrKey(10, "sc00B")
*$sc00C:: HandleAltGrKey(11, "sc00C")
*$sc00D:: HandleAltGrKey(12, "sc00D")

HandleAltGrKey(index, scanCode) {
    global customStrings
    if (GetKeyState("RAlt", "P")) {
        if (customStrings[index] != "")
            SendText customStrings[index]
        else
            Send "{Blind}{" scanCode "}"
    }
}
#HotIf

; --- 10. Умная вставка текста ---
#HotIf pastePlain = "1"
^!v:: {
    KeyWait "Ctrl"
    KeyWait "Alt"
    text := A_Clipboard
    if (text == "")
        return
        
    bak := ClipboardAll()

    ; 1. Считаем ВСЕ буквы в тексте (игнорируем смайлики и знаки)
    ruCount := 0, enCount := 0
    Loop Parse, text {
        if (A_LoopField ~= "[а-яА-ЯёЁ]")
            ruCount++
        else if (A_LoopField ~= "[a-zA-Z]")
            enCount++
    }

    ; 2. Переключаем раскладку один раз на весь текст
    if (ruCount >= enCount && ruCount > 0) {
        ForceSwitchLang(0x04190419) ; Включаем русский
        Sleep 50
    } else if (enCount > ruCount) {
        ForceSwitchLang(0x04090409) ; Включаем английский
        Sleep 50
    }

    ; 3. Вставляем ТЕКСТ
    A_Clipboard := text
    Sleep 50
    SendEvent "{Ctrl Down}v{Ctrl Up}"
    Sleep 150 
    
    ; 4. Возвращаем буфер обмена
    A_Clipboard := bak 
}
#HotIf
