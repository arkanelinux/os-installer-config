#!/usr/bin/env bash

### Pre-run checks and setup ###
#
# load collection of checks and functions
source /etc/os-installer/lib.sh

if [[ ! $? -eq 0 ]]; then
	printf 'Failed to load /etc/os-installer/lib.sh\n'
	exit 1
fi

# sanity check that all variables were set
if [ -z ${OSI_LOCALE+x} ] || \
   [ -z ${OSI_DEVICE_PATH+x} ] || \
   [ -z ${OSI_DEVICE_IS_PARTITION+x} ] || \
   [ -z ${OSI_DEVICE_EFI_PARTITION+x} ] || \
   [ -z ${OSI_USE_ENCRYPTION+x} ] || \
   [ -z ${OSI_ENCRYPTION_PIN+x} ] || \
   [ -z ${OSI_USER_NAME+x} ] || \
   [ -z ${OSI_USER_AUTOLOGIN+x} ] || \
   [ -z ${OSI_USER_PASSWORD+x} ] || \
   [ -z ${OSI_FORMATS+x} ] || \
   [ -z ${OSI_TIMEZONE+x} ] || \
   [ -z ${OSI_ADDITIONAL_SOFTWARE+x} ]
then
    printf 'configure.sh called without all environment variables set!\n'
    exit 1
fi

# Enable systemd services
task_wrapper readarray services < "$osidir/bits/systemd.services"

for service in ${services[@]}; do
	task_wrapper sudo arch-chroot $workdir systemctl enable $service
done

# Set default stop timer to 15 seconds to avoid long shutdowns
task_wrapper sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=15s/g' $workdir/etc/systemd/system.conf

# FIXME: Uncomment instead of append
# Set chosen locale and en_US.UTF-8 for it is required by some programs
echo "$OSI_LOCALE UTF-8" | task_wrapper sudo tee -a $workdir/etc/locale.gen

if [[ $OSI_LOCALE != 'en_US.UTF-8' ]]; then
	echo "en_US.UTF-8 UTF-8" | task_wrapper sudo tee -a $workdir/etc/locale.gen
fi

echo "LANG=\"$OSI_LOCALE\"" | task_wrapper sudo tee $workdir/etc/locale.conf

# Generate locales
task_wrapper sudo arch-chroot $workdir locale-gen

# Copy Systemd-boot configuration
task_wrapper sudo cp -rv $osidir/bits/systemd-boot/* $workdir/boot/loader/

# Add dconf tweaks for GNOME desktop configuration
task_wrapper sudo cp -rv $osidir/bits/dconf $workdir/etc/
task_wrapper sudo arch-chroot $workdir dconf update

# Add custom useradd config
task_wrapper sudo install -m600 $osidir/bits/useradd $workdir/etc/default/useradd

# Enable wheel in sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' | task_wrapper sudo tee $workdir/etc/sudoers.d/wheel

# Set hostname
echo 'arkane' | task_wrapper sudo tee /mnt/etc/hostname

# Set kernel parameters in Systemd-boot based on if disk encryption is used or not
#
# This is the base string shared by all configurations
declare -r KERNEL_PARAM='lsm=landlock,lockdown,yama,integrity,apparmor,bpf quiet splash loglevel=3 vt.global_cursor_default=0 systemd.show_status=auto rd.udev.log_level=3 rw'

# The kernel parameters have to be configured differently based upon if the
# user opted for disk encryption or not
if [[ $OSI_USE_ENCRYPTION == 1 ]];
then
	declare -r LUKS_UUID=$(sudo blkid -o value -s UUID ${OSI_DEVICE_PATH}3)
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | task_wrapper sudo tee -a $workdir/boot/loader/entries/arkane.conf
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | task_wrapper sudo tee -a $workdir/boot/loader/entries/arkane-fallback.conf
	task_wrapper sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block sd-encrypt filesystems fsck)/g' $workdir/etc/mkinitcpio.conf
	task_wrapper sudo arch-chroot $workdir mkinitcpio -P
else
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | task_wrapper sudo tee -a $workdir/boot/loader/entries/arkane.conf
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | task_wrapper sudo tee -a $workdir/boot/loader/entries/arkane-fallback.conf
	task_wrapper sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block filesystems fsck)/g' $workdir/etc/mkinitcpio.conf
	task_wrapper sudo arch-chroot $workdir mkinitcpio -P
fi

# Add user and set password
task_wrapper sudo arch-chroot $workdir useradd -m $OSI_USER_NAME
echo $OSI_USER_NAME:$OSI_USER_PASSWORD | task_wrapper sudo arch-chroot $workdir chpasswd

# Ensure synced and umount
task_wrapper sync
task_wrapper sudo umount -R /mnt

exit 0
