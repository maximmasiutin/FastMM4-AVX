@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  WSL2 PAServer Port Forwarding Setup
echo  Run this script as Administrator
echo ============================================
echo.

:: Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This script requires Administrator privileges.
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

:: Get WSL IP address
echo Getting WSL IP address...
for /f "tokens=1" %%i in ('wsl hostname -I') do set WSL_IP=%%i

if "%WSL_IP%"=="" (
    echo ERROR: Could not get WSL IP address.
    echo Make sure WSL is running.
    pause
    exit /b 1
)

echo WSL IP: %WSL_IP%
echo.

:: Remove existing port proxy rule (if any)
echo Removing existing port forwarding rule (if any)...
netsh interface portproxy delete v4tov4 listenport=64211 listenaddress=0.0.0.0 >nul 2>&1

:: Add new port proxy rule
echo Adding port forwarding: 0.0.0.0:64211 -> %WSL_IP%:64211
netsh interface portproxy add v4tov4 listenport=64211 listenaddress=0.0.0.0 connectport=64211 connectaddress=%WSL_IP%

if %errorlevel% neq 0 (
    echo ERROR: Failed to add port forwarding rule.
    pause
    exit /b 1
)

:: Add firewall rule (if not exists)
echo.
echo Checking firewall rule...
netsh advfirewall firewall show rule name="Delphi PAServer" >nul 2>&1
if %errorlevel% neq 0 (
    echo Adding firewall rule for PAServer...
    netsh advfirewall firewall add rule name="Delphi PAServer" dir=in action=allow protocol=tcp localport=64211
) else (
    echo Firewall rule already exists.
)

:: Show current configuration
echo.
echo ============================================
echo  Current Port Forwarding Rules:
echo ============================================
netsh interface portproxy show v4tov4

echo.
echo ============================================
echo  Setup Complete
echo ============================================
echo.
echo In WSL, run PAServer:
echo   cd ~/paserver
echo   ./paserver
echo.
echo In Delphi, connect to: localhost:64211
echo   (or use WSL IP: %WSL_IP%:64211)
echo.
pause
