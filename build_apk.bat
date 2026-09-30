@echo off
:start
cls
echo Building AutoRoomzio APK...
cd app
call flutter clean
call flutter pub get
call flutter build apk --release
copy /y build\app\outputs\flutter-apk\app-release.apk ..\AutoRoomzio.apk
cd ..
echo Build complete. The APK is in the root folder as AutoRoomzio.apk.
echo.
echo =======================================================
echo [r] Relancer le script
echo [q] Quitter
set /p RESTART="Choix (r/q) > "
if /i "%RESTART%"=="r" goto start
