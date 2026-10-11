@echo off
SETLOCAL
set "ROOT=%~dp0"
set "IVERILOG_BIN=C:\Users\mohdy\scoop\apps\iverilog\current\bin"
set "PATH=%IVERILOG_BIN%;%PATH%"
cd /d "%ROOT%"

iverilog -o tb.out testbench.v module.v
if errorlevel 1 (
    echo. 
    echo Verilog compile failed.
    exit /b %errorlevel%
)

vvp tb.out
if errorlevel 1 (
    echo. 
    echo Simulation failed.
    exit /b %errorlevel%
)

echo.
echo Simulation complete. Output waveform file: dump.vcd
exit /b 0
