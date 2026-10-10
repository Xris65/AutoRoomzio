@echo off
:start
cls
echo Lancement de AutoRoomzio sur web (localhost 8085)
cd app
call flutter run -d web-server --web-port 8085
cd ..
echo.
echo =======================================================
echo [r] Relancer le script
echo [q] Quitter
set /p RESTART="Choix (r/q) > "
if /i "%RESTART%"=="r" goto start
