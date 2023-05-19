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

# TODO: uncomment locale in locale.conf

# Enable user selected locale
task_wrapper sudo arch-chroot $workdir locale-gen

# Copy Systemd-boot configuration
task_wrapper sudo cp $osidir/bits/systemd-boot/arkane.conf /mnt/boot/loader/entries/
task_wrapper sudo cp $osidir/bits/systemd-boot/arkane-fallback.conf /mnt/boot/loader/entries/
task_wrapper sudo cp $osidir/bits/systemd-boot/loader.conf /mnt/boot/loader/

# Add dconf tweaks for GNOME desktop configuration
task_wrapper sudo cp -r /etc/os-installer/bits/dconf /mnt/etc/
task_wrapper sudo arch-chroot /mnt dconf update

# Configure useradd default on new root
#
# The custom useradd default is used for setting Zsh as the default
# shell for newly created users
task_wrapper sudo install -m600 -d  $osidir/bits/useradd $workdir/etc/default/

# Enable wheel in sudoers
task_wrapper sudo sed -i 's/#\ %wheel\ ALL=(ALL:ALL)\ ALL/%wheel\ ALL=(ALL:ALL)\ ALL/g' /mnt/etc/sudoers

# Set hostname
echo 'arkane' | task_wrapper sudo tee /mnt/etc/hostname

# Set kernel parameters in Systemd-boot based on if disk encryption is used or not
#
# This is the base string shared by all configurations
declare -r KERNEL_PARAM='lsm=landlock,lockdown,yama,integrity,apparmor,bpf quiet splash loglevel=3 vt.global_cursor_default=0 systemd.show_status=auto rd.udev.log_level=3 rw'

# The kernel parameters have to be configured differently based upon if the
# user opted for disk encryption or not
if [[ ${OSI_USE_ENCRYPTION} == 1 ]];
then
	declare -r LUKS_UUID=$(sudo blkid -o value -s UUID ${OSI_DEVICE_PATH}3)
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | task_wrapper sudo tee -a /mnt/boot/loader/entries/arkane.conf
	echo "options rd.luks.name=$LUKS_UUID=arkane_root root=/dev/mapper/arkane_root $KERNEL_PARAM" | task_wrapper sudo tee -a /mnt/boot/loader/entries/arkane-fallback.conf
	task_wrapper sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block sd-encrypt filesystems fsck)/g' /mnt/etc/mkinitcpio.conf
	task_wrapper sudo arch-chroot /mnt mkinitcpio -P
else
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | task_wrapper sudo tee -a /mnt/boot/loader/entries/arkane.conf
	echo "options root=\"LABEL=arkane_root\" $KERNEL_PARAM" | task_wrapper sudo tee -a /mnt/boot/loader/entries/arkane-fallback.conf
	task_wrapper sudo sed -i '/^#/!s/HOOKS=(.*)/HOOKS=(systemd sd-plymouth autodetect keyboard keymap consolefont modconf block filesystems fsck)/g' /mnt/etc/mkinitcpio.conf
	task_wrapper sudo arch-chroot /mnt mkinitcpio -P
fi

# Ensure synced and umount
#
# Linux sometimes likes to be smart about these things are write everything
# to the memory instead of the disk
task_wrapper sync
task_wrapper sudo umount -R /mnt

exit 0
