@echo off
cd /d "%~dp0"
echo.
echo === Swarm receivers: type a message and a noise level. The channel's frequency, phase and timing are random and hidden. ===
:loop
echo.
set "MSG="
set /p "MSG=Enter message (q to quit): "
if /i "%MSG%"=="q" goto :eof
if "%MSG%"=="" goto loop
set "NOISE="
set /p "NOISE=Enter noise level as signal strength in dB, lower = noisier (Enter = 8): "
if "%NOISE%"=="" set "NOISE=8"
set "MSG=%MSG:'=''%"
matlab -batch "swarm_receivers('%MSG%', %NOISE%);"
goto loop
