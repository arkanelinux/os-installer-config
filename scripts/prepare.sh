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

	# Ensure the terminal has time to print before exiting
	sleep 2

	exit 1
}

## Pre-run checks to ensure everything is ready
#
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
sudo pacman -Syy || quit_on_err 'Failed to synchornize with repositories'

exit 0
