@echo off
setlocal

:: --- Variables you can change ---
set "RCLONE_DIR=C:\rclone"
set "RCLONE_EXE=C:\rclone\rclone.exe"
set "RCLONE_CONF=%RCLONE_DIR%\rclone.conf"
set "RCLONE_USER=jonas"
set "RCLONE_PASS=kallekokain"
set "REMOTE_NAME=storage-dav"
set "REMOTE_URL=http://storage.local.hejsan.xyz:3923"
set "MOUNT_DRIVE=W:"
set "SERVICE_NAME=rclone-mount"
set "LOG_OUT=%RCLONE_DIR%\rclone-out.log"
set "LOG_ERR=%RCLONE_DIR%\rclone-err.log"

echo === Creating/Updating rclone config ===
"%RCLONE_EXE%" config show %REMOTE_NAME% >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Creating config for %REMOTE_NAME%...
    "%RCLONE_EXE%" config create %REMOTE_NAME% webdav url=%REMOTE_URL% vendor=owncloud pacer_min_sleep=0.01ms user=%RCLONE_USER% pass=%RCLONE_PASS%
) else (
    echo Config "%REMOTE_NAME%" already exists.
)

echo Copying config to %RCLONE_CONF%
if exist "%APPDATA%\rclone\rclone.conf" (
    copy "%APPDATA%\rclone\rclone.conf" "%RCLONE_CONF%" /Y
) else (
    echo WARNING: No config found in %%APPDATA%%\rclone\rclone.conf
)

echo === Installing NSSM service ===
.\nssm stop %SERVICE_NAME% >nul 2>&1
.\nssm remove %SERVICE_NAME% confirm >nul 2>&1

.\nssm install %SERVICE_NAME% "%RCLONE_EXE%" cmount --config "%RCLONE_CONF%" --vfs-cache-mode writes  --file-perms 0777 %REMOTE_NAME%: %MOUNT_DRIVE%


:: Set working dir
.\nssm set %SERVICE_NAME% AppDirectory "%RCLONE_DIR%"

:: Logging
.\nssm set %SERVICE_NAME% AppStdout "%LOG_OUT%"
.\nssm set %SERVICE_NAME% AppStderr "%LOG_ERR%"
.\nssm set %SERVICE_NAME% AppRotateFiles 1

echo Starting service %SERVICE_NAME%...
.\nssm start %SERVICE_NAME%

echo === Done! Rclone should now be mounted on %MOUNT_DRIVE% via NSSM service ===
pause
