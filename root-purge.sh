#!/bin/sh

# System cleanup script - removes old kernels, snaps, logs, and temporary files
# Supports: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Flatpak, Snap, Docker, Podman

r=$(uname -r)
k=${r%%-*}  # kernel version without suffix

purge_debian() {
	command -v apt-get > /dev/null || return
	# Remove old kernel packages except the current
	dpkg --list 'linux-*' | awk '/^ii/ && /'"$k"'/ && !/'"$r"'/ {print $2}' |
		xargs --no-run-if-empty sudo apt-get --yes remove --purge

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
	if command -v dnf > /dev/null; then
		# Fedora/RHEL
		sudo dnf clean dbcache
	fi

	# Keep only 2 snap revisions
	sudo snap set system refresh.retain=2 2> /dev/null

	# Remove disabled snaps
	snap list --all 2> /dev/null | awk '/disabled/{print $1, $3}' |
		while read s v; do
			sudo snap remove "$s" --revision="$v"
		done

	command -v flatpak > /dev/null && flatpak uninstall --unused --assumeyes

	# Journal cleanup - keep 1 day
	sudo journalctl --vacuum-time=1d

	# Remove old temp/crash files (8+ days)
	find /tmp /var/crash -type f -atime +8 -delete 2> /dev/null

	prune_containers
}

show_status() {
	echo "Status:"

	# Show snap cache size
	command -v snap > /dev/null && sudo du --summarize --human-readable /var/lib/snapd/cache 2> /dev/null

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
}

main() {
	purge_system
	show_status
}

# Run when executed directly
main "$@"
