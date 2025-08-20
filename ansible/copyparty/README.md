# Rclone WebDAV Mount (Windows + NSSM)

This setup mounts the WebDAV storage from **copyparty** at  
`http://storage.local.hejsan.xyz:3923`  
to drive `W:` on Windows. The mount runs automatically as a **Windows Service** using [NSSM](https://nssm.cc/).

## Requirements

1. **rclone**

   - Download from: https://rclone.org/downloads/
   - Extract to `C:\rclone\` (where `rclone.exe` will live).

2. **NSSM (Non-Sucking Service Manager)**

   - Download from: https://nssm.cc/download
   - Place `nssm.exe` somewhere in your `PATH` or in `C:\rclone\`.

3. **Copyparty WebDAV credentials**
   - Go to [http://storage.local.hejsan.xyz:3923/?hc](http://storage.local.hejsan.xyz:3923/?hc)
   - Copy the `rclone config create` command shown there.
   - Update `setup-rclone-service.bat` with the correct username and password.

## Setup

1. Edit `setup-rclone-service.bat`

   - Change `RCLONE_USER` and `RCLONE_PASS` at the top.
   - Adjust `MOUNT_DRIVE` if you want a different drive letter.

2. Run `setup-rclone-service.bat` as **Administrator**

   - This will:
     - Ensure the rclone config exists.
     - Copy the config to `C:\rclone\rclone.conf`.
     - Install the `rclone-mount` service with NSSM.
     - Enable logging to `C:\rclone\rclone-out.log` and `C:\rclone\rclone-err.log`.
     - Start the service.

3. Verify the mount
   - Open File Explorer → you should see drive `W:`.
   - Check logs in `C:\rclone\rclone-out.log` / `C:\rclone\rclone-err.log` if something fails.

## Management

- **Restart service** (after config changes):
  ```powershell
  nssm restart rclone-mount
  ```

* **Stop service**:

  ```powershell
  nssm stop rclone-mount
  ```

* **Uninstall service**:
  Run `uninstall-rclone-service.bat` as Administrator.
  (This stops/removes the service and deletes logs.)

## Notes

- The `rclone.conf` used by the service is stored in `C:\rclone\rclone.conf`.
- If you ever change credentials, re-run `setup-rclone-service.bat`.
- The service runs under `Local System` by default, but because we specify `--config "C:\rclone\rclone.conf"` it will always find the correct configuration.
