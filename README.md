# Waiveo Host

**Waiveo Host** is a management layer that installs, configures, and manages [Waiveo](https://waiveo.com) on dedicated hardware. It provides a web-based management interface, automatic updates, backup/restore, and system monitoring.

> **Note:** Waiveo is currently in private beta. Open source release coming soon!

## Hosting Options

There are three ways to run Waiveo:

| Method | Best For | Uses Waiveo Host? |
|--------|----------|-------------------|
| **Docker** | Existing servers, NAS, homelabs | No - use Waiveo directly |
| **Raspberry Pi** | Dedicated appliance | Yes - pre-built image |
| **x86 Linux** | Dedicated server/mini PC | Yes - CLI installer |

### Option 1: Docker (Advanced Users)

If you already have a server running Docker, you don't need Waiveo Host. Just run Waiveo directly:

```bash
docker run -d \
  --name waiveo \
  --restart unless-stopped \
  --network host \
  --privileged \
  -v waiveo-data:/app/data \
  maaxton/waiveo:latest
```

Access at `http://<your-server-ip>:5173`

### Option 2: Raspberry Pi Image

For a dedicated Waiveo appliance on Raspberry Pi 4/5 (4GB+ RAM):

1. Download the latest image from [Releases](https://github.com/maaxton/waiveo-host-releases/releases)
2. Flash to SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
3. Insert SD card and boot your Pi
4. Access setup at `http://waiveo.local`

**Includes:**
- Pre-configured Raspberry Pi OS (64-bit)
- Docker with Waiveo
- Web-based management interface (port 80)
- Automatic resource optimization for Pi hardware
- SD card-friendly caching (reduces wear)

### Option 3: x86 Linux Installer

For a dedicated x86_64 or arm64 server running Ubuntu/Debian:

```bash
curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash
```

**Requirements:**
- Ubuntu 20.04+ or Debian 11+
- 4GB+ RAM (2GB minimum)
- 10GB+ free disk space

**Includes:**
- Docker installation (if not present)
- Waiveo container with auto-restart
- Web-based management interface (port 80)
- CLI tools for management

## What is Waiveo Host?

Waiveo Host provides:

- **Web Management UI** - Start/stop, view logs, update Waiveo from your browser
- **First-Boot Setup** - Guided setup wizard for credentials and initial configuration
- **Automatic Updates** - Check for and install Waiveo updates
- **Backup & Restore** - Create and restore backups of your Waiveo data
- **System Monitoring** - CPU, memory, disk, temperature (Pi), throttle detection (Pi)
- **CLI Tools** - `waiveo status`, `waiveo logs`, `waiveo update`, etc.

## Credentials & Access

After installation, access the web interface at `http://<ip-address>`

### Raspberry Pi Image

- **URL:** `http://waiveo.local` or `http://<ip-address>`
- **Username:** `waiveo`
- **Password:** `TemporaryBootstrapPassword123!`
- You will be prompted to change the password on first login.

### x86 Linux Install

- **URL:** `http://<ip-address>`
- **Login:** Use your existing Linux username and password
- The management UI authenticates against your system credentials via PAM.

## CLI Commands

```bash
waiveo status      # Check service status
waiveo logs        # View application logs
waiveo restart     # Restart Waiveo
waiveo update      # Update to latest version
waiveo backup      # Create a backup
waiveo restore     # Restore from backup
waiveo info        # Show system information
waiveo --help      # Show all available commands
```

## Uninstall

To completely remove Waiveo Host:

```bash
# Stop services
sudo systemctl stop waiveo waiveo-management

# Disable services
sudo systemctl disable waiveo waiveo-management

# Remove files
sudo rm -rf /opt/waiveo
sudo rm -f /usr/local/bin/waiveo*
sudo rm -f /etc/systemd/system/waiveo*.service

# Remove Docker volume (WARNING: deletes all Waiveo data)
sudo docker volume rm waiveo_waiveo-data

# Reload systemd
sudo systemctl daemon-reload
```

## Support

- [GitHub Issues](https://github.com/maaxton/waiveo-host-releases/issues)
- [Waiveo Website](https://waiveo.com)

## License

Waiveo Host is open source. See the [main repository](https://github.com/maaxton/waiveo-host) for license details.
