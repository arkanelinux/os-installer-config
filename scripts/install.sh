#!/usr/bin/env bash

set -o pipefail

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
mountpoint -q $workdir && quit_on_err "$workdir is already a mountpoint, unmount this directory and try again"

# Write partition table to the disk
sudo sfdisk $OSI_DEVICE_PATH < $osidir/bits/part.sfdisk || quit_on_err 'Failed to write partition table to disk'

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
		sudo mkfs.fat -F32 ${partition_path}1 || quit_on_err "Failed to create FAT filesystem on ${partition_path}1"
		echo $OSI_ENCRYPTION_PIN | sudo cryptsetup -q luksFormat ${partition_path}2 || quit_on_err "Failed to create LUKS partition on ${partition_path}2"
		echo $OSI_ENCRYPTION_PIN | sudo cryptsetup open ${partition_path}2 $rootlabel - || quit_on_err 'Failed to unlock LUKS partition'
		sudo mkfs.btrfs -f -L $rootlabel /dev/mapper/$rootlabel || quit_on_err 'Failed to create Btrfs partition on LUKS'

		sudo mount -o compress=zstd /dev/mapper/$rootlabel $workdir || quit_on_err "Failed to mount LUKS/Btrfs root partition to $workdir"
		sudo mount --mkdir ${partition_path}1 $workdir/boot || quit_on_err 'Failed to mount boot'
		sudo btrfs subvolume create $workdir/home || quit_on_err 'Failed to create home subvolume'

	else
		# If target is a partition
		printf 'PARTITION TARGET NOT YET IMPLEMENTED BECAUSE OF EFI DETECTION BUG\n'
		exit 1
	fi

else

	# If no disk encryption requested
	if [[ $OSI_DEVICE_IS_PARTITION -eq 0 ]]; then

		# If target is a drive
		sudo mkfs.fat -F32 ${partition_path}1 || quit_on_err "Failed to create FAT filesystem on ${partition_path}1"
		sudo mkfs.btrfs -f -L $rootlabel ${partition_path}2 || quit_on_err "Failed to create root on ${partition_path}2"

		sudo mount -o compress=zstd ${partition_path}2 $workdir || quit_on_err "Failed to mount root to $workdir"
		sudo mount --mkdir ${partition_path}1 $workdir/boot || quit_on_err 'Failed to mount boot'
		sudo btrfs subvolume create $workdir/home || quit_on_err 'Failed to create home subvoume'

	else
		# If target is a partition
		printf 'PARTITION TARGET NOT YET IMPLEMENTED BECAUSE OF EFI DETECTION BUG\n'
		exit 1
	fi

fi

# Ensure partitions are mounted, quit and error if not
for mountpoint in $workdir $workdir/boot; do
	mountpoint -q $mountpoint || quit_on_err "No volume mounted to $mountpoint"
done

# Install the base system packages to root
readarray base_packages < $osidir/bits/package_lists/base.list || quit_on_err 'Failed to read base.list'
sudo pacstrap $workdir ${base_packages[*]} || quit_on_err 'Failed to install base packages'

# Copy the ISO's pacman.conf file to the new installation
sudo cp -v /etc/pacman.conf $workdir/etc/pacman.conf || quit_on_err 'Failed to copy local pacman.conf to new root'

# For some reason Arch does not populate the keyring upon installing
# arkane-keyring, thus we have to populate it manually
sudo arch-chroot $workdir pacman-key --populate arkane || quit_on_err 'Failed to populate pacman keyring with Arkane keys'

# If localrepo exists, mount it
if [[ -d /var/localrepo ]]; then
	sudo mount -v -m --bind /var/localrepo $workdir/var/localrepo || quit_on_err 'Failed to mount localrepo' 
fi

# Install the remaining system packages
sudo arch-chroot $workdir pacman -S --noconfirm - < $osidir/bits/package_lists/gnome.list || quit_on_err 'Failed to arch-chroot and install gnome packages'

# If localrepo exists, unmount it and remove dir
if [[ -d $workdir/var/localrepo ]]; then
	sudo umount -v $workdir/var/localrepo || quit_on_err 'Failed to unmount localrepo'
	rm -rf $workdir/var/localrepo || quit_on_err 'Failed to remove localrepo mount point'
fi

# Install the systemd-boot bootloader
sudo arch-chroot $workdir bootctl install || quit_on_err 'Failed to install systemd-boot'

# Collect information about the system memory, this is used to determine an apropriate swapfile size
declare -ri memtotal=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Determine suitable swapfile size
if [[ $memtotal -lt 4500000 ]]; then

	# If RAM is less than 4.5GB create a 2GB swapfile
	sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 2G /var/swapfile || quit_on_err 'Failed to create swapfile'
	
elif [[ $memtotal -lt 8500000 ]]; then

	# If RAM is less than 8.5GB, create a 4GB swapfile
	sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 4G /var/swapfile || quit_on_err 'Failed to create swapfile'

else

	# Else create a 6GB swapfile
	sudo arch-chroot $workdir btrfs filesystem mkswapfile --size 6G /var/swapfile || quit_on_err 'Failed to create swapfile'

fi

# Enable the swapfile
sudo swapon $workdir/var/swapfile || quit_on_err 'Failed to activate swap'

# Generate the fstab file
sudo genfstab -U $workdir || quit_on_err 'Failed to genfstab' | sudo tee $workdir/etc/fstab || quit_on_err 'Failed to write fstab'

exit 0
