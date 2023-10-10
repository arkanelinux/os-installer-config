#!/usr/bin/env bash

set -o pipefail

declare -r workdir='/mnt'
declare -r osidir='/etc/os-installer'

## Generic checks
#
# Ensure user is in sudo group
for group in $(groups); do

	if [[ $group == 'wheel' || $group == 'sudo' ]]; then
		declare -ri sudo_ok=1
	fi

done

# If user is not in sudo group notify and exit with error
if [[ ! -n $sudo_ok ]]; then
	printf 'The current user is not a member of either the sudo or wheel group, this os-installer configuration requires sudo permissions\n'
	exit 1
fi

# Function used to quit and notify user or error
quit_on_err () {
	if [[ -v $1 ]]; then
		printf '$1\n'
	fi

	exit 1
}

# TODO: Drop this and instead use overlay?
# Enable systemd services
readarray services < $osidir/bits/systemd.services quit_on_err 'Failed to read systemd.services file'

for service in ${services[@]}; do
	sudo arch-chroot $workdir systemctl enable $service || quit_on_err 'Failed to enable system services'
done

# FIXME: Uncomment instead of append
# Set chosen locale and en_US.UTF-8 for it is required by some programs
echo "$OSI_LOCALE UTF-8" | sudo tee -a $workdir/etc/locale.gen || quit_on_err 'Failed to configure locale.gen'

if [[ $OSI_LOCALE != 'en_US.UTF-8' ]]; then
	echo "en_US.UTF-8 UTF-8" | sudo tee -a $workdir/etc/locale.gen || quit_on_err 'Failed to configure locale.gen with en_US.UTF-8'
fi

echo "LANG=\"$OSI_LOCALE\"" | sudo tee $workdir/etc/locale.conf || quit_on_err 'Failed to set default locale'

# Generate locales
sudo arch-chroot $workdir locale-gen || quit_on_err 'Failed to locale-gen'

# TODO: Also drop this in favor of overlay?
# Copy Systemd-boot configuration
sudo cp -rv $osidir/bits/systemd-boot/* $workdir/boot/loader/ || quit_on_err 'Failed to copy systemd-boot configuration'

# TODO: Also drop this in favor of overlay?
# Set custom sysctl tunables
sudo install -m600 $osidir/bits/99-sysctl.conf $workdir/etc/sysctl.d/ || quit_on_err 'Failed to set sysctl turnables'

# Add dconf tweaks for GNOME desktop configuration
sudo cp -rv $osidir/bits/dconf $workdir/etc/ || quit_on_err 'Failed to add dconf tweaks'
sudo arch-chroot $workdir dconf update || quit_on_err 'Failed to update dconf'

# TODO: Also drop this in favor of overlay?
# Add custom useradd config
sudo install -m600 $osidir/bits/useradd $workdir/etc/default/useradd || quit_on_err 'Failed to add useradd config'

# TODO: Also drop this in favor of overlay?
# Enable wheel in sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' | sudo tee $workdir/etc/sudoers.d/wheel || quit_on_err 'Failed to add wheel to sudoers'

# Set hostname
echo 'arkane' | sudo tee /mnt/etc/hostname || quit_on_err 'Failed to configure hostname'

# Set kernel parameters in Systemd-boot based on if disk encryption is used or not
#
# This is the base string shared by all configurations
declare -r KERNEL_PARAM='lsm=landlock,lockdown,yama,integrity,apparmor,bpf quiet splash loglevel=3 vt.global_cursor_default=0 systemd.show_status=auto rd.udev.log_level=3 rw'

# The kernel parameters have to be configured differently based upon if the
# user opted for disk encryption or not
if [[ $OSI_USE_ENCRYPTION == 1 ]]; then
	declare -r LUKS_UUID=$(sudo blkid -o value -s UUID ${OSI_DEVICE_PATH}2)
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | sudo tee -a $workdir/boot/loader/entries/arkane.conf || quit_on_err 'Failed to configure bootloader config'
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | sudo tee -a $workdir/boot/loader/entries/arkane-fallback.conf || quit_on_err 'Failed to configure bootloader fallback config'

	sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block sd-encrypt filesystems fsck)/g' $workdir/etc/mkinitcpio.conf || quit_on_err 'Failed to set hooks'
	sudo arch-chroot $workdir mkinitcpio -P || quit_on_err 'Failed to mkinitcpio'
else
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | sudo tee -a $workdir/boot/loader/entries/arkane.conf
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | sudo tee -a $workdir/boot/loader/entries/arkane-fallback.conf

	sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block filesystems fsck)/g' $workdir/etc/mkinitcpio.conf || quit_on_err 'Failed to set hooks'
	sudo arch-chroot $workdir mkinitcpio -P || quit_on_err 'Failed to generate initramfs'
fi

# Get first name
declare firstname=($OSI_USER_NAME)
firstname=${firstname[0]}

# Add user, setup groups and set password
sudo arch-chroot $workdir useradd -m  -c "$OSI_USER_NAME" "${firstname,,}" || quit_on_err 'Failed to add user'
echo "${firstname,,}:$OSI_USER_PASSWORD" | sudo arch-chroot $workdir chpasswd || quit_on_err 'Failed to set user password'
sudo arch-chroot $workdir usermod -a -G wheel "${firstname,,}" || quit_on_err 'Failed to make user sudoer'

# Set root password
echo "root:$OSI_USER_PASSWORD" | sudo arch-chroot $workdir chpasswd || quit_on_err 'Failed to set root password'

# Set timezome
sudo arch-chroot $workdir ln -sf /usr/share/zoneinfo/$OSI_TIMEZONE /etc/localtime || quit_on_err 'Failed to set timezone'

# Set custom keymap, very hacky but it gets the job done
# TODO: Also set in TTY
declare -r current_keymap=$(gsettings get org.gnome.desktop.input-sources sources)
printf "[org.gnome.desktop.input-sources]\nsources = $current_keymap\n" | sudo tee $workdir/etc/dconf/db/local.d/keymap || quit_on_err 'Failed to set dconf keymap'

# Set auto login if requested
if [[ $OSI_USER_AUTOLOGIN -eq 1 ]]; then
	printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=${firstname,,}\n" | sudo tee $workdir/etc/gdm/custom.conf || quit_on_err 'Failed to setup automatic login for user'
fi

# Disable localrepo on new install
grep -v 'localrepo' $workdir/etc/pacman.conf || quit_on_err 'Failed to grep new root pacman.conf' | sudo tee $workdir/etc/pacman.conf.new || quit_on_err 'Failed to writee '
sudo mv $workdir/etc/pacman.conf.new $workdir/etc/pacman.conf || quit_on_err 'Failed to write new pacman.conf'

# Ensure synced and umount
sync
sudo umount -R /mnt

exit 0
