#!/usr/bin/env bash

### Pre-run checks to ensure everything is ready ###
#
# load collection of checks and functions
source /etc/os-installer/lib.sh

if [[ ! $? -eq 0 ]]; then
	printf 'Failed to load /etc/os-installer/lib.sh\n'
	exit 1
fi

# Loop until pacman-init.service finishes
printf 'Waiting for pacman-init.service to finish running before starting the installation... '

while true; do
	systemctl status pacman-init.service | grep -q 'Finished Initializes Pacman keyring.'

	if [[ $? -eq 0 ]]; then
		printf 'Done'
		break
	fi

	sleep 2
done

# Synchornize with repos
task_wrapper sudo pacman -Syy

exit 0
