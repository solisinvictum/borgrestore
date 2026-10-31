# borgrestore

First of all, I apologize that English may not be perfect. I speak only German, and used deepl.com/translate to help with this README.

## What does borgrestore do?

borgrestore does exactly the same as timeshift (btrfs) or timeshift (rsync): it restores a snapshot 1:1 like it was recorded. Files that were added after the snapshot are deleted, deleted files come back, changed files are reset, including permissions, owners, extended attributes (e.g. file capabilities) and hard links.

For this, [Borg](https://www.borgbackup.org/) is taken to help. Unfortunately, `borg extract` restores just as "badly" as BackInTime or other backup programs: it only puts files back, but does not remove what is new. Why that is a problem is explained very well in this thread:

https://forum.endeavouros.com/t/searching-for-a-real-backup-solution-no-btrfs-or-timeshift/20249

Timeshift and btrfs don't allow to store the snapshots on external storage (like NFS), otherwise they would be perfect. borgrestore mounts the chosen Borg archive and syncs it to the destination with `rsync --delete`.

## Usage

```
borgrestore -r [ARCHIVE]   restore a snapshot (asks which one if ARCHIVE is not given)
borgrestore -n -r ARCHIVE  dry run: only show what would be changed
borgrestore -l             list the snapshots
borgrestore -c FILE ...    use another config file
borgrestore -f -r ARCHIVE  restore even if the archive does not look like a system (no etc/ and usr/)
```

borgrestore must run as root. If the repository is encrypted, it asks for the passphrase once (or takes it from `BORG_PASSPHRASE` / `BORG_PASSCOMMAND`).

Before anything is changed, borgrestore checks that the archive is really mounted, not empty and looks like a system backup. If the mount fails or something is wrong, it stops and nothing is changed. The archive is always unmounted at the end, also after errors or Ctrl+C. Use the dry run first if you are unsure.

## Configuration

Edit `/etc/borgrestore/borgrestore.conf` first:

- `BORGREPO`: path of the Borg repository (local, NFS or `ssh://`).
- `DESTINATION`: where to restore, normally `/`.
- `MOUNTPOINT`: an empty directory where the archive is mounted.
- `RSYNCEXCLUDES`: **important**: everything you excluded in Vorta/Borg must be excluded here too. Everything in the destination that is not in the backup gets deleted, so folders you did not back up must be listed here. Note that these are **rsync** patterns, not Borg patterns: a leading `/` anchors the pattern at the destination (`/mnt` = only `<DESTINATION>/mnt`), Borg prefixes like `pp:` or `sh:` do not work. Check the result with a dry run (`borgrestore -n -r ARCHIVE`): every `*deleting` line is a file that would be removed.
- `EXTRA_EXCLUDES`: more excludes.
- `LIVESYSTEM`: `1` when restoring the running system, `0` when restoring offline. With `0` and `DESTINATION="/"`, `/tmp` and `/run` are emptied after a successful restore.
- `BORG_PASSCOMMAND` (optional): command that prints the passphrase.

borgrestore itself (`/usr/bin/borgrestore`, `/etc/borgrestore/`), the mount point and a local repository inside the destination are never touched.

## Limitations

- **POSIX ACLs are not restored.** `borg mount` does not expose them, so borgrestore does not touch ACLs (no `rsync -A`, that would remove them). Existing ACL entries in the destination usually stay, but restoring the permission bits can change the ACL mask and thus the effective permissions, and recreated files get no ACLs. systemd re-creates its own ACLs (e.g. on `/var/log/journal`) at boot. If you need ACLs exactly as in the backup, use `borg extract` for those files.
- borg 1.x only, borg 2 has a different command line and is not supported yet.

## Installation

Arch Linux: install [borgrestore from the AUR](https://aur.archlinux.org/packages/borgrestore). Your config file is kept on updates.

Other systems: needs `borg` 1.x with FUSE support (pyfuse3 or llfuse), `rsync` and `util-linux`.

```
install -Dm755 borgrestore /usr/bin/borgrestore
install -Dm644 borgrestore.conf /etc/borgrestore/borgrestore.conf
```

## How I use it

I have reduced the size of my hard disk by a few gigs and installed Debian on it. The GRUB of EndeavourOS is adjusted so that a "Recovery" entry appears in the GRUB menu. When I select it, Debian is started, my / from EndeavourOS and the Borg repo are mounted and the script is started, which asks me which snapshot I want to recover (`DESTINATION` points to the mounted EndeavourOS, `LIVESYSTEM="0"`).

You can also use this script live while the operating system is running. I have tested this a few times and it seems to work, but I can't guarantee anything. After a live restore a reboot is mandatory, borgrestore offers to do it (a forced reboot, because the running system no longer matches the disk).

I decided to use the safe option.

## Tests

`tests/test.sh` tests borgrestore with a real Borg repository and a real FUSE mount, restoring into a temporary directory (never the real system). It needs root, borg, fuse3, rsync, acl, attr and libcap tools.

## Thanks to

- The nice Guys from https://forum.endeavouros.com
- The nice Guys from #Gentoo IRC Channel
- The nice Guys from #rsync IRC Channel
- Archwiki
- and many other... (they get mentioned in the commits)

## Other

Feel free to improve the script or open issues and pull requests. Would be very happy about it.
