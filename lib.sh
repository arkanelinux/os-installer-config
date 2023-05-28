# Make pipes return last non-zero exit code, else return zero
set -o pipefail

declare -r workdir='/mnt'
declare -r osidir='/etc/os-installer'
declare -r rootlabel='arkane_root'

# Ensure user is able to run sudo
for group in $(groups); do

	if [[ $group == 'wheel' || $group == 'sudo' ]]; then
		declare -ri sudo_ok=1
	fi

done

if [[ ! -n $sudo_ok ]]; then
	printf 'The current user is not a member of either the sudo or wheel group, this os-installer configuration requires sudo permissions\n'
	exit 1
fi

# Executes program or build-in and quits osi on non-zero exit code
task_wrapper () {
	if [[ -n $OSI_CONFIG_DEBUG ]]; then
		$* >> $HOME/installation.log
	else
		$*
	fi

	if [[ ! $? -eq 0  ]]; then
		printf "Task \"$*\" exited with non-zero exit code, quitting...\n"
		exit 1
	fi
}
