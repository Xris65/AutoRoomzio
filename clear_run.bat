@echo off
:start
cls
echo Running AutoRoomzio Flutter App...
cd app
call flutter clean
call flutter run -d windows
cd ..
echo.
echo =======================================================
echo [r] Relancer le script
echo [q] Quitter
set /p RESTART="Choix (r/q) > "
if /i "%RESTART%"=="r" goto start
