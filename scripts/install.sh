#!/usr/bin/env bash

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
   [ -z ${OSI_ENCRYPTION_PIN+x} ]
then
    printf 'install.sh called without all environment variables set!\n'
    exit 1
fi

# Check if something is already mounted to $workdir
mountpoint -q $workdir

if [[ $? -eq 0 ]]; then
	printf "$workdir is already a mountpoint, unmount this directory and try again\n"
	exit 1
fi

# Write partition table to the disk
task_wrapper sudo sfdisk $OSI_DEVICE_PATH < $osidir/bits/part.sfdisk

# NVMe drives follow a slightly different naming scheme to other block devices
# this will change `/dev/nvme0n1` to `/dev/nvme0n1p` for easier parsing later
if [[ $OSI_DEVICE_PATH == *"nvme"*"n"* ]]; then
	declare -r partition_path="${OSI_DEVICE_PATH}p"
else
	declare -r partition_path="${OSI_DEVICE_PATH}"
fi

# Check if encryption is requested, write filesystems accordingly
if [[ $OSI_USE_ENCRYPTION -eq 1 ]]; then

	# If user requested disk encryption
	if [[ $OSI_DEVICE_IS_PARTITION -eq 0 ]]; then

		# If target is a drive
		task_wrapper sudo mkfs.fat -F32 ${partition_path}1
		task_wrapper sudo cryptsetup -q luksFormat ${partition_path}2
		task_wrapper sudo cryptsetup open ${partition_path}2 $rootlabel -
		task_wrapper sudo mkfs.btrfs -f -L $rootlabel /dev/mapper/$rootlabel

		task_wrapper sudo mount -o compress=zstd /dev/mapper/$rootlabel $workdir
		task_wrapper sudo mount --mkdir ${partition_path}1 $workdir/boot
		task_wrapper sudo btrfs subvolume create $workdir/home

	else

		# If target is a partition
		printf 'PARTITION TARGET NOT YET IMPLEMENTED BECAUSE OF EFI DETECTION BUG\n'
		exit 1
	fi

else

	# If no disk encryption requested
	if [[ $OSI_DEVICE_IS_PARTITION -eq 0 ]]; then

		# If target is a drive
		task_wrapper sudo mkfs.fat -F32 ${partition_path}1
		task_wrapper sudo mkfs.btrfs -f -L $rootlabel ${partition_path}2

		task_wrapper sudo mount -o compress=zstd ${partition_path}2 $workdir
		task_wrapper sudo mount --mkdir ${partition_path}1 $workdir/boot
		task_wrapper sudo btrfs subvolume create $workdir/home

	else

		# If target is a partition=
		printf 'PARTITION TARGET NOT YET IMPLEMENTED BECAUSE OF EFI DETECTION BUG\n'
		exit 1
	fi

fi

# Ensure partitions are mounted, quit and error if not
for mountpoint in $workdir $workdir/boot; do
	task_wrapper mountpoint -q $mountpoint
done

# Collect information about the system memory, this is used to determine an apropriate swapfile size
declare -ri memtotal=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Determine suitable swapfile size
if [[ $memtotal -lt 4500000 ]]; then

	# If RAM is less than 4.5GB create a 2GB swapfile
	task_wrapper sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 2G /var/swapfile

elif [[ $memtotal -lt 8500000 ]]; then

	# If RAM is less than 8.5GB, create a 4GB swapfile
	task_wrapper sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 4G /var/swapfile

else

	# Else create a 6GB swapfile
	task_wrapper sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 6G /var/swapfile

fi

# Enable the swapfile
task_wrapper sudo swapon $workdir/var/swapfile

# Install the base system packages to root
task_wrapper readarray base_packages < "$osidir/bits/package_lists/base.list"
task_wrapper sudo pacstrap $workdir $base_packages

# Generate the fstab file
task_wrapper sudo genfstab -U $workdir | task_wrapper sudo tee $workdir/etc/fstab

# Copy the ISO's pacman.conf file to the new installation
task_wrapper sudo cp -v /etc/pacman.conf $workdir/etc/pacman.conf

# For some reason Arch does not populate the keyring upon installing
# arkane-keyring, thus we have to populate it manually
task_wrapper sudo arch-chroot $workdir pacman-key --populate arkane

# Install the remaining system packages
task_wrapper sudo arch-chroot $workdir pacman -S --noconfirm - < $osidir/bits/package_lists/gnome.list

# Install the systemd-boot bootloader
task_wrapper sudo arch-chroot $workdir bootctl install

exit 0
