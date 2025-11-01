#!/bin/sh

# System cleanup script - removes old kernels, snaps, logs, and temporary files
# Supports: Debian/Ubuntu (apt), Fedora/RHEL (dnf), Flatpak, Snap, Docker, Podman

age=10  # days to keep files (mtime, atime)
keep=2  # number of releases to keep
dry_run=  # dry run mode (empty for normal, non-empty for dry-run)
interactive=
mode=--assumeyes  # default mode for package managers
extra=

purge_debian() {
	command -v apt-get > /dev/null || return
	aptmode=""
	[ "$dry_run" ] && aptmode="--simulate"
	[ ! "$interactive" ] && aptmode="--assume-yes"

	# Remove old kernel packages (keep current + 1 previous)
	r=$(uname -r)
	dpkg --list 'linux-image-*' |
		awk '/^ii/ {print $2}' |
		grep --fixed-strings --invert-match "$r" |
		grep -E '[0-9]+\.[0-9]+\.[0-9]+' |
		sort --version-sort |
		head -n -$keep |
		xargs --no-run-if-empty sudo apt-get $aptmode remove --purge

	# Clean orphaned kernel packages
	command -v aptitude > /dev/null && sudo aptitude $aptmode purge "~nlinux-image~c"

	# Hold current kernel from removal
	[ ! "$dry_run" ] && echo "linux-image-$r hold" | sudo dpkg --set-selections

	# Ensure current kernel headers/image installed
	[ ! "$dry_run" ] && sudo apt-get install $aptmode "linux-headers-$r" "linux-image-$r" 2> /dev/null

	[ ! "$dry_run" ] && sudo apt-get clean
	sudo apt-get $aptmode autoremove

	echo Kept kernels:
	dpkg --list | grep --extended-regexp "linux-(image|headers|source)" |
		grep --extended-regexp "(^ii|^rc)"
}

purge_fedora() {
	command -v dnf > /dev/null || return

	# Clean all DNF cache
	if [ "$dry_run" ]; then
		echo "Would clean DNF cache:"
		du -sh /var/cache/dnf/* 2> /dev/null || echo "  (empty or inaccessible)"
	else
		sudo dnf clean all
	fi

	# Remove old kernel releases
	rpm -qa kernel-core | sort -V | head -n -$keep | xargs -r sudo dnf $mode remove

	# Clean PackageKit cache
	if [ "$extra" ]; then
		if [ "$dry_run" ]; then
			echo "Would clean PackageKit cache:"
			du -sh /var/cache/PackageKit/* 2> /dev/null || echo "  (empty or inaccessible)"
		else
			sudo rm -rf /var/cache/PackageKit/*
		fi
	fi

	# Clean ABRT crash data
	if [ -d /var/spool/abrt ]; then
		if [ "$dry_run" ]; then
			echo "Would remove ABRT crash data older than $age days:"
			find /var/spool/abrt -mindepth 1 -maxdepth 1 -type d -mtime +$age 2> /dev/null |
				xargs -r ls -ld | sed 's/^/  /'
		else
			sudo find /var/spool/abrt -mindepth 1 -maxdepth 1 -type d -mtime +$age \
				-exec rm -rf {} \; 2> /dev/null
		fi
	fi
}

prune_containers() {
	for cmd in podman docker; do
		command -v $cmd > /dev/null || continue
		echo Pruning $cmd
		[ "$interactive" ] && force="" || force="--force"
		if [ "$dry_run" ]; then
			echo "Would prune $cmd containers, volumes, and networks"
		else
			# user context
			$cmd container prune $force 2> /dev/null
			$cmd volume prune $force 2> /dev/null
			$cmd network prune $force 2> /dev/null
		fi

		# Aggressive cleanup, including unused images
		[ "$extra" ] && $cmd system prune --all $force --volumes 2> /dev/null
	done
}

purge_system() {
	# Package manager cleanup (distro-specific)

	purge_debian
	purge_fedora

	# Limit snap revisions
	[ "$extra" ] && sudo snap set system refresh.retain=$keep 2> /dev/null

	# Remove disabled snaps in user context
	if [ "$dry_run" ]; then
		echo "Would remove disabled snaps:"
		snap list --all 2> /dev/null | awk '/disabled/{print "  - " $1 " (rev " $3 ")"}'
	else
		snap list --all 2> /dev/null | awk '/disabled/{print $1, $3}' |
			while read s v; do
				sudo snap remove --purge "$s" --revision="$v"
			done
	fi

	# Clean snap cache
	if [ "$dry_run" ]; then
		echo "Would clean snap cache:"
		du -sh /var/lib/snapd/cache 2> /dev/null || echo "  (empty or inaccessible)"
	else
		sudo rm -rf /var/lib/snapd/cache/* 2> /dev/null
	fi

	# Clean flatpak
	if command -v flatpak > /dev/null; then
		if [ "$dry_run" ]; then
			echo "Would remove unused flatpaks"
		else
			# user context
			flatpak uninstall --unused $mode
		fi
	fi

	# Journal cleanup - keep 1 day
	if [ "$dry_run" ]; then
		echo "Would vacuum journal (current size):"
		journalctl --disk-usage 2> /dev/null | sed 's/^/  /'
	else
		sudo journalctl --vacuum-time=1d
	fi

	# Remove old temp/crash files
	if [ "$dry_run" ]; then
		echo "Would remove temp/crash files older than $age days:"
		find /tmp /var/tmp /var/crash -type f -atime +$age 2> /dev/null | wc -l | xargs echo "  Files:"
	else
		sudo find /tmp /var/tmp /var/crash -type f -atime +$age -delete 2> /dev/null
	fi

	# Clean old root cache
	if [ "$dry_run" ]; then
		echo "Would remove root cache files older than $age days:"
		find /root/.cache -type f -atime +$age 2> /dev/null | wc -l | xargs echo "  Files:"
	else
		sudo find /root/.cache -type f -atime +$age -delete 2> /dev/null
	fi

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
	sudo du --one-file-system -xh / 2> /dev/null | sort -h | tail -n 20
}

show_help() {
	echo "Usage: $0 [--dry-run|-n] [--interactive|-i] [--extra|-e] [--keep|-k N] [--help|-h]"
	echo "  --dry-run, -n     Show what would be done without making changes"
	echo "  --interactive, -i Let tools prompt for confirmation (no auto-yes)"
	echo "  --extra, -e       Enable aggressive cleanup operations and configurations"
	echo "  --keep, -k N      Number of releases to keep (default: 2)"
	echo "  --help, -h        Show this help message"
}

main() {
	# Handle command line options
	while [ $# -gt 0 ]; do
		case "$1" in
			--dry-run|-n)
				dry_run=1
				mode=--assumeno
				echo "Dry run mode - no changes will be made"
				;;
			--interactive|-i)
				interactive=1
				mode=""
				echo "Interactive mode - tools will prompt for confirmation"
				;;
			--extra|-e)
				extra=1
				echo "Extra mode"
				;;
			--help|-h)
				show_help
				exit 0
				;;
			*)
				echo "Unknown option: $arg"
				echo "Use --help for usage information"
				exit 1
				;;
		esac
		shift
	done

	purge_system
	show_status
}

# Run when executed directly
main "$@"
