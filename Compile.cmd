@echo off
chcp 65001 > nul

:: Определение путей относительно папки с батником
set "SCRIPT_DIR=%~dp0"
set "AHK_ROOT=%SCRIPT_DIR%..\AutoHotkey_2.0.31"

:: Запуск компиляции
"%AHK_ROOT%\Compiler\Ahk2Exe.exe" /in "%SCRIPT_DIR%KeyboardSwitcher.ahk" /icon "%SCRIPT_DIR%KeyboardSwitcher.ico" /base "%AHK_ROOT%\AutoHotkey64.exe"

if %errorlevel% equ 0 (
    echo [УСПЕШНО] Скрипт KeyboardSwitcher.exe собран с вашей иконкой!
) else (
    echo [ОШИБКА] Не удалось скомпилировать скрипт. Проверьте пути.
    pause
)
