@echo off
echo Running AutoRoomzio Flutter App...
cd app
call flutter clean
call flutter pub get
call flutter run -d windows
cd ..
pause
