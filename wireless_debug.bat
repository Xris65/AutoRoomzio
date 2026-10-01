@echo off
color 0B
:start
cls
echo =======================================================
echo          AutoRoomzio - Wireless Debugging Setup
echo =======================================================
echo.
echo [1] Connect to my phone (already paired)
echo [2] Pair my phone for the first time
echo.
set /p CHOICE="Choose an option (1 or 2): "

if "%CHOICE%"=="2" goto pairing
goto connecting

:pairing
echo.
echo --- PAIRING MODE ---
echo Open 'Wireless debugging' on your phone and tap 'Pair device with pairing code'.
echo Enter the IP address and Port shown in the popup (e.g., 192.168.1.50:41234)
set /p PAIR_IP="Pairing IP:PORT > "
if "%PAIR_IP%"=="" goto pairing
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" pair %PAIR_IP%
echo.
echo Pairing complete! Now let's connect.

:connecting
echo.
echo --- CONNECTION MODE ---
echo Look at the MAIN 'Wireless debugging' screen on your phone.
echo Enter the IP address and Port shown there (e.g., 192.168.1.50:33333)
set /p CONN_IP="Connection IP:PORT > "
if "%CONN_IP%"=="" goto connecting
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" connect %CONN_IP%

echo.
echo =======================================================
echo Starting Flutter...
echo =======================================================
cd app
call flutter run
cd ..
echo.
echo =======================================================
echo [r] Relancer le script
echo [q] Quitter
set /p RESTART="Choix (r/q) > "
if /i "%RESTART%"=="r" goto start
