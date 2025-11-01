# ♻️ root-purge

Root file system garbage collection utility
that removes old kernels, snaps, logs, containers and temporary files.

## Supported systems

Ubuntu/Debian - apt-based systems\
RHEL/Fedora - dnf-based systems\
Container tools - Docker, Podman\
Package formats - Flatpak, Snap

## Usage

```bash
./root-purge.sh [OPTIONS]
```

## Options

`--dry-run, -n` - show what would be done without making changes\
`--interactive, -i` - let tools prompt for confirmation (no auto-yes)\
`--extra, -e` - enable aggressive cleanup operations\
`--keep, -k N` - number of releases to keep (default: 2)\
`--help, -h` - show help message

## What it cleans

### Default operations

Old kernel packages (keeps current + N previous, default N=2)\
Disabled snap packages\
Snap cache\
Unused flatpak runtimes\
System journal\
Old temporary and cache files\
Stopped containers, unused volumes and networks (Docker/Podman)

### Extra operations (--extra flag)

Limit snap revisions to keep value\
PackageKit cache\
All unused container images (with --all --volumes)

## Notes

Requires sudo/root access for most operations\
Current running kernel is always protected\
Operations are skipped if tools are not installed
