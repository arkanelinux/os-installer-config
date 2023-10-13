# os-installer-config
Configuration files for [os-installer](https://gitlab.gnome.org/p3732/os-installer) on Arch Linux and Arch-based systems.

> **Note** Installing to a partition is not functional on os-installer 0.3, the EFI detection bug should be fixed on master and in the future 0.4 release

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
- Bind mount `/var/localrepo` to new install if available
- Install GNOME system defined in `bits/package_lists/gnome.list`
- Install bootloader
- Create 2GB, 4GB or 6GB swapfile based on amount of system memory
- Enable swapfile
- Generate fstab

### configure.sh
- Copy `overlay` to new root
- Generate user selected locale and `en_US.UTF-8`, user locale is set as default
- Set kernel params based upon if LUKS is used or not
- Create user
- Set root pasword
- Set custom keymap
- Enable autologin if requested
- Disable localrepo
- Sync and umount
