#!/bin/sh

root_purge()
{
	#sudo apt-get -y autoremove
	# dpkg --list "linux-image"*
	if which apt-get 2> /dev/null; then
		R=$(uname -r)
		sudo apt-get remove linux-image-generic
		sudo apt-get -y remove --purge \
			$(dpkg -l 'linux-image-*' |
				sed '/^ii/!d;
				/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;
				s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;
				/[0-9]/!d')
		sudo aptitude -y purge "~nlinux-image~c"
		#sudo apt-get -y install linux-image-generic
		#sudo apt-get -y install linux-image-lowlatency
		# linux-lowlatency
		dpkg --list | grep -e linux-source -e linux-image -e linux-headers -e linux-image-generic
		echo linux-image-$R hold | sudo dpkg --set-selections
		dpkg --get-selections linux-image-$R
		sudo apt-get install -y linux-headers-$R linux-image-$R
		sudo apt-get clean
		sudo apt-get autoclean
		sudo apt-get autoremove
		sudo apt-get purge
	fi
	sudo snap set system refresh.retain=2
	snap list --all | awk '/disabled/{print $1, $3}' | \
	while read s r; do
		sudo snap remove "$s" --revision="$r"
	done
	sudo du --summarize --human-readable /var/lib/snapd/cache
	sudo journalctl --vacuum-time=1d # SystemMaxUse=100M /etc/systemd/journald.conf
	grep SystemMaxUse /etc/systemd/journald.conf
	journalctl --disk-usage
	sudo dnf clean dbcache
	find /tmp /var/crash/ -type f -atime +8 -delete 2> /dev/null || true
	podman ps -a
	podman container list -a
	docker ps -a
	docker container list -a
	flatpak uninstall --unused
}

root_purge
