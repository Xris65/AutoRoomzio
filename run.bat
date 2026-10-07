@echo off
:start
cls
echo Running AutoRoomzio Flutter App...
cd app
call flutter run -d windows
cd ..
echo.
echo =======================================================
echo [r] Relancer le script (Compilation rapide)
echo [c] Nettoyer completement (flutter clean) et relancer
echo [q] Quitter
set /p RESTART="Choix (r/c/q) > "
if /i "%RESTART%"=="r" goto start
if /i "%RESTART%"=="c" (
    cd app
    call flutter clean
    call flutter pub get
    cd ..
    goto start
)
