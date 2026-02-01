# Waiveo Releases

Official release downloads for [Waiveo](https://waiveo.io) - Home Automation made simple.

## Quick Install

### One-Line Installer (Recommended)

For Ubuntu 20.04+, Debian 11+ on x86_64 or arm64:

```bash
curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash
```

### Raspberry Pi Image

For Raspberry Pi 4/5 with 4GB+ RAM:

1. Download the latest `.img.xz` from [Releases](https://github.com/maaxton/waiveo-host-releases/releases)
2. Flash to SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
3. Insert SD card and boot your Pi
4. Access setup at `http://waiveo.local`

## System Requirements

### CLI Install (x86_64 / arm64)

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 20.04, Debian 11 | Ubuntu 22.04+ |
| RAM | 2 GB | 4 GB+ |
| Storage | 5 GB | 10 GB+ |
| Architecture | x86_64, arm64 | x86_64, arm64 |

### Raspberry Pi Image

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Model | Raspberry Pi 4 | Raspberry Pi 5 |
| RAM | 4 GB | 8 GB |
| Storage | 16 GB SD card | 32 GB+ SD card |

## Default Credentials

After installation, access the web interface:

- **URL:** `http://<ip-address>` or `http://waiveo.local`
- **Username:** `waiveo`
- **Password:** `TemporaryBootstrapPassword123!`

You will be prompted to change the password on first login.

## CLI Commands

After installation, the following commands are available:

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

## Verify Downloads

All releases include SHA256 checksums. To verify:

```bash
# Download the checksum file
curl -fsSLO https://github.com/maaxton/waiveo-host-releases/releases/latest/download/SHA256SUMS

# Verify your download
sha256sum -c SHA256SUMS --ignore-missing
```

## Troubleshooting

### Cannot access waiveo.local

- Ensure your device supports mDNS (most do)
- Try accessing via IP address instead: `http://<ip-address>`
- On the device, run `waiveo network` to see the IP

### Docker installation failed

```bash
# Manually install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable docker
sudo systemctl start docker

# Re-run Waiveo installer
curl -fsSL https://get.waiveo.io | sudo bash
```

### Service not starting

```bash
# Check service status
sudo systemctl status waiveo-management

# View logs
sudo journalctl -u waiveo-management -f
```

## Uninstall

To completely remove Waiveo:

```bash
# Stop services
sudo systemctl stop waiveo waiveo-management

# Disable services
sudo systemctl disable waiveo waiveo-management

# Remove files
sudo rm -rf /opt/waiveo
sudo rm -f /usr/local/bin/waiveo*
sudo rm -f /etc/systemd/system/waiveo*.service

# Remove Docker volume (WARNING: deletes all data)
sudo docker volume rm waiveo_waiveo-data

# Reload systemd
sudo systemctl daemon-reload
```

## Support

- [GitHub Issues](https://github.com/maaxton/waiveo-host-releases/issues)
- [Documentation](https://waiveo.com/docs)

## License

Waiveo is open source software. See the main repository for license details.
