@echo off
setlocal

:: --- Variables (must match your install script) ---
set "RCLONE_DIR=C:\rclone"
set "SERVICE_NAME=rclone-mount"
set "LOG_OUT=%RCLONE_DIR%\rclone-out.log"
set "LOG_ERR=%RCLONE_DIR%\rclone-err.log"
set "RCLONE_CONF=%RCLONE_DIR%\rclone.conf"

echo === Stopping service %SERVICE_NAME% ===
nssm stop %SERVICE_NAME%

echo === Removing service %SERVICE_NAME% ===
nssm remove %SERVICE_NAME% confirm

:: Optional cleanup
echo Deleting logs...
del "%LOG_OUT%" /f /q 2>nul
del "%LOG_ERR%" /f /q 2>nul

:: Uncomment if you also want to remove the local copy of rclone.conf
:: echo Deleting copied config...
:: del "%RCLONE_CONF%" /f /q 2>nul

echo === Uninstall complete ===
pause
