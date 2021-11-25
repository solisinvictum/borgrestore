# borgrestore

First of all, I apologize that English may not be perfect (especially in the comments of the files). I speak only German, and have for this text in the README.md deepl.com/translate to help.

# What does borgrestore do?

borgrestore does exactly the same as timeshift(btrfs) or timeshift(rsync). 

That means it restores a snapshot 1:1 like it was recorded. 

For this borg is taken to help. Unfortunately, borg restores just as "badly" as BackInTime or other backup programs. 

But why is explained very well in this thread:

https://forum.endeavouros.com/t/searching-for-a-real-backup-solution-no-btrfs-or-timeshift/20249

Unfortunately Timeshift and BTRFS don't allow to backup the snapshots to an external storage (like NFS). Otherwise Timeshift/BTRFS would be perfect. 

The script is quite rudimentary. And certainly not perfect. Some things could have been done in a more elegant and comfortable way. But it does exactly what it should do.

In this repo is a PKGBUILD for Arch based operating systems. 

For any other (Linux-) system, just move the script "borgrestore" to /usr/bin for example and "borgrestore.conf" to "/etc/borgrestore/".

# What else is coming in this repo?

Besides the hourly backup, I would like to create a Pacman hook that makes a backup before installing a new program with Pacman, or before each system upgrade performed by Pacman. But that has time for now...

# How i use it

I have reduced the size of my hard disk by a few gigs and installed Debian on it. Grub of EndeavourOS adjusted so that in the grub menu now appears a "Recovery" entry. When I select it, debian is started, my / from EndeavourOS and the Borg repo are mounted and the script is started which asks me which snapshot I want to recover.

You can also use this script live while the operating system is running. But be careful! I have tested this a few times and it seems to work, but I can't guarantee anything. 

I decided to use the safe option.

# Thanks to

- The nice Guys from https://forum.endeavouros.com
- The nice Guys from #Gentoo IRC Channel
- The nice Guys from #rsync IRC Channel
- Archwiki
- and many other... (they get mentioned in the commits)

# Other

Feel free to improve the script or start PR & MR. Would be very happy to do so.
