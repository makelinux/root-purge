#!/bin/sh

# System cleanup script - removes old kernels, snaps, logs, and temporary files
# Supports: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Flatpak, Snap, Docker, Podman

r=$(uname -r)
age=10  # days to keep files (mtime, atime)

purge_debian() {
	command -v apt-get > /dev/null || return
	# Remove old kernel packages (keep current + 1 previous)
	dpkg --list 'linux-image-*' | awk '/^ii/ {print $2}' | grep -E '[0-9]+\.[0-9]+\.[0-9]+' |
		sort -V | head -n -2 | xargs --no-run-if-empty sudo apt-get --yes remove --purge

	# Clean orphaned kernel packages
	command -v aptitude > /dev/null && sudo aptitude --assume-yes purge "~nlinux-image~c"

	# Hold current kernel from removal
	echo "linux-image-$r hold" | sudo dpkg --set-selections

	# Ensure current kernel headers/image installed
	sudo apt-get install --yes "linux-headers-$r" "linux-image-$r" 2> /dev/null

	sudo apt-get clean
	sudo apt-get --yes autoremove

	echo Kept kernels:
	dpkg --list | grep --extended-regexp "linux-(image|headers|source)" | grep --extended-regexp "(^ii|^rc)"
}

purge_fedora() {
	command -v dnf > /dev/null || return
	# Clean all DNF cache
	sudo dnf clean all
	sudo rm -rf /var/cache/dnf/*

	# Remove old kernels (keep current + 1 previous)
	rpm -qa kernel-core | sort -V | head -n -2 | xargs -r sudo dnf remove -y

	echo Cleaning PackageKit cache
	command -v pkcon > /dev/null && sudo pkcon refresh force -c -1 2> /dev/null
	sudo rm -rf /var/cache/PackageKit/*

	# Clean ABRT crash data
	if [ -d /var/spool/abrt ]; then
		sudo find /var/spool/abrt -mindepth 1 -maxdepth 1 -type d -mtime +$age -exec rm -rf {} \; 2> /dev/null
	fi
}

prune_containers() {
	for cmd in podman docker; do
		command -v $cmd > /dev/null || continue

		echo "Pruning $cmd containers..."
		# Remove stopped containers
		$cmd container prune --force 2> /dev/null

		# Remove unused volumes
		$cmd volume prune --force 2> /dev/null

		# Remove unused networks
		$cmd network prune --force 2> /dev/null

		# Aggressive cleanup - commented by default
		# $cmd system prune --all --force --volumes 2> /dev/null
	done
}

purge_system() {
	# Package manager cleanup (distro-specific)

	purge_debian
	purge_fedora

	# Keep only 2 snap revisions
	sudo snap set system refresh.retain=2 2> /dev/null

	# Remove disabled snaps
	snap list --all 2> /dev/null | awk '/disabled/{print $1, $3}' |
		while read s v; do
			sudo snap remove "$s" --revision="$v"
		done

	sudo rm -rf /var/lib/snapd/cache/* 2> /dev/null

	command -v flatpak > /dev/null && flatpak uninstall --unused --assumeyes

	# Journal cleanup - keep 1 day
	sudo journalctl --vacuum-time=1d

	# Remove old temp/crash files
	sudo find /tmp /var/tmp /var/crash -type f -atime +$age -delete 2> /dev/null

	sudo find /root/.cache -type f -atime +$age -delete 2> /dev/null

	prune_containers
}

show_status() {
	journalctl --disk-usage 2> /dev/null

	# Show container status if tools exist
	for cmd in podman docker; do
		command -v $cmd > /dev/null || continue
		echo $cmd containers:
		$cmd ps --all
		echo $cmd images:
		if [ "$cmd" = "podman" ]; then
			$cmd images --all --sort size
		else
			$cmd images --all
		fi
		echo $cmd disk usage:
		$cmd system df 2> /dev/null
	done
	sudo du --time --one-file-system / | \
		sort -n | tail -n 20 | \
		while read s n; do
			echo "$(numfmt --padding=7 --to=iec-i $((1024*s))) $n";
		done
}

main() {
	purge_system
	show_status
}

# Run when executed directly
main "$@"
