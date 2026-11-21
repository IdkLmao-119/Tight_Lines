@echo off
REM Copies the Tight Lines debug/demo saves into the game's save folder.
REM slot_1.json = "Slot 2" (Demo)   slot_2.json = "Slot 3" (Ending)
REM Slot 1 (slot_0.json) is never touched.
set "DEST=%APPDATA%\Godot\app_userdata\Tight Lines (Capstone Edition)\saves"
if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0slot_1.json" "%DEST%\slot_1.json" >nul
copy /Y "%~dp0slot_2.json" "%DEST%\slot_2.json" >nul
echo Installed debug saves to:
echo   %DEST%
echo   Slot 2 = DEMO (late game)    Slot 3 = ENDING (100%% Almanac)
pause
