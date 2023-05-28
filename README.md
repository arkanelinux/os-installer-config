# os-installer-config
Configuration files for [os-installer](https://gitlab.gnome.org/p3732/os-installer) on Arch Linux and Arch-based systems.

## Overview
An overview of the non-default os-installer components.
| File/Directory | Utility |
| --- | --- |
| `lib.sh` | Contains shared functions and checks, is sourced by all script files in `scripts/` |
| `bits` | Contains files utilized by the installation scripts, these files are either copied or read by the installation scripts |

## Scripts configuration overview
### prepare.sh
- Ensure `pacman-init.service` finishes running before starting install
- Sync with repos

### install.sh
- Partition drive
- Write filesystems to drive, either LUKS+Btrfs or Btrfs
- Mount disk
- Create `/home` Btrfs subvolume
- Install core system defined in `bits/package_lists/base.list`
- Setup pacman keyring
- Install GNOME system defined in `bits/package_lists/gnome.list`
- Install bootloader
- Bind mount `/var/localrepo` to new install if available
- Create 2GB, 4GB or 6GB swapfile based on amount of system memory
- Enable swapfile
- Generate fstab

### configure.sh
- Start systemd services defined in `bits/systemd.services`
- Decrease systemd DefaultTimeoutStopSec to 15s
- Generate user selected locale and `en_US.UTF-8`, user locale is default
- Copy systemd-boot configs from `bits/systemd-boot/`
- Add dconf tweaks from `bits/dconf`
- Create custom useradd to make Zsh default on new users
- Configure sudoers
- Set hostname
- Set kernel params based upon if LUKS is used or not
- Create user
- Set root pasword
- Set custom keymap
- Enable autologin if requested
- Disable localrepo
- Sync and umount
