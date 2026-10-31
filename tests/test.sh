#!/bin/bash
# shellcheck disable=SC2015  # "a && ok || bad" is intended, ok/bad never fail
#
# Tests for borgrestore with a real borg repository and a real FUSE mount.
# Never touches the real system: every test restores into a temporary
# destination directory with its own config file.
#
# Needs root, borg 1.x with pyfuse3/llfuse, fuse3, rsync, acl, attr, libcap2-bin
# (setcap/getcap), expect not needed. In Docker: --device /dev/fuse
# --cap-add SYS_ADMIN --security-opt apparmor:unconfined
#
#   sudo ./tests/test.sh [path/to/borgrestore]
#
set -u

BR="$(readlink -f "${1:-$(dirname "$0")/../borgrestore}")"
work="$(mktemp -d)" || { echo "cannot create temporary directory" >&2; exit 2; }
# Remove the workspace only if nothing is mounted in it anymore
final_cleanup() {
	local m busy=0
	for m in "$work/mnt" "$work/dest/mnt"; do
		if mountpoint -q "$m" && ! umount "$m"; then
			busy=1
		fi
	done
	if [ "$busy" -eq 1 ]; then
		echo "WARNING: a mount in $work is still busy, workspace kept" >&2
	else
		rm -rf "$work"
	fi
}
trap final_cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "ok   $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
for t in borg rsync setfacl getfacl setfattr getfattr setcap getcap mountpoint; do
	command -v "$t" > /dev/null || { echo "missing: $t"; exit 2; }
done

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_BASE_DIR="$work/borgbase"

## Source tree = "the system in the snapshot"
src="$work/src"
mkdir -p "$src"/{etc,usr/bin,home/user,var/empty,keep}
echo "galaxias" > "$src/etc/hostname"
printf 'line1\nline2\n' > "$src/etc/fstab"
cp /bin/true "$src/usr/bin/pingish"
setcap cap_net_raw+ep "$src/usr/bin/pingish"
echo "hard" > "$src/usr/bin/a"
ln "$src/usr/bin/a" "$src/usr/bin/b"
ln -s ../etc/hostname "$src/usr/hostname-link"
echo "secret" > "$src/home/user/acl-file"
setfacl -m u:1234:rw "$src/home/user/acl-file"
setfattr -n user.comment -v "borg keeps me" "$src/home/user/acl-file"
chown 1234:2345 "$src/home/user"
chmod 0750 "$src/home/user"
echo "in the backup, but excluded" > "$src/keep/file"

## Repositories: unencrypted with two archives, encrypted, one without etc/usr
(
	cd "$src" || exit 1
	borg --warning init -e none "$work/repo"
	borg create "$work/repo::snap1" .
	cp -a etc/hostname "$work/hostname.orig"
	echo "galaxias-v2" > etc/hostname
	borg create "$work/repo::snap2" .
	cp -a "$work/hostname.orig" etc/hostname
	BORG_PASSPHRASE="s3cret pass" borg --warning init -e repokey "$work/crepo"
	BORG_PASSPHRASE="s3cret pass" borg create "$work/crepo::csnap" .
	mkdir -p "$work/datasrc" && echo data > "$work/datasrc/just-data"
	cd "$work/datasrc" && borg create "$work/repo::dataonly" .
) || { echo "cannot create test repositories"; exit 2; }

conf="$work/borgrestore.conf"
writeconf() { # writeconf [repo] [mountpoint]
	cat > "$conf" <<EOF
BORGREPO="${1:-$work/repo}"
DESTINATION="$work/dest"
MOUNTPOINT="${2:-$work/mnt}"
RSYNCEXCLUDES=('/keep')
EXTRA_EXCLUDES=()
LIVESYSTEM="1"
EOF
}

# The destination = "the current system": changed against the snapshot
newdest() {
	if mountpoint -q "$work/dest/mnt" && ! umount "$work/dest/mnt"; then
		echo "cannot unmount $work/dest/mnt" >&2
		exit 2
	fi
	rm -rf "$work/dest"
	cp -a "$src" "$work/dest"
	rm "$work/dest/etc/fstab"                       # deleted -> must come back
	echo "new" > "$work/dest/etc/new-file"          # new -> must be deleted
	echo "changed" > "$work/dest/etc/hostname"      # changed -> restored
	setcap -r "$work/dest/usr/bin/pingish"          # capability lost -> restored
	setfattr -x user.comment "$work/dest/home/user/acl-file"
	chown 0:0 "$work/dest/home/user"                # owner changed -> restored
	rm "$work/dest/usr/bin/b" && cp "$work/dest/usr/bin/a" "$work/dest/usr/bin/b"  # hard link broken
	echo "local only, excluded" > "$work/dest/keep/local"
	rm -f "$work/dest/keep/file"
}

# Fingerprint of a tree: names, types, modes, owners, sizes, contents, xattrs
fingerprint() {
	(cd "$1" && find . -printf '%p %y %m %U:%G %s %i\n' | sort | awk '{ $NF=""; print }'
	 find . -type f -exec sha256sum {} + | sort
	 getfattr -R -d -m - --absolute-names . 2> /dev/null | grep -v '^$' | sort)
}

# Same as the snapshot (except the excluded /keep)?
same_as_src() { # same_as_src [extra rsync exclude]
	local raw diff
	# no -A: ACLs are not part of the restore (borg mount does not expose
	# them); the mtime of the top directory is not restored either
	raw="$(rsync -n -aHXc --numeric-ids --delete --itemize-changes --exclude=/keep ${1:+"--exclude=$1"} "$src/" "$work/dest/")" || {
		echo "comparison rsync failed"
		return 1
	}
	diff="$(grep -v '^\.d\.\.t\.\.\.\.\.\. \./$' <<< "$raw")"
	[ -z "$diff" ] || { echo "$diff" | head -20; return 1; }
}

run() { # run <stdin> <args...>
	local input="$1"
	shift
	printf '%b' "$input" | "$BR" -c "$conf" "$@" > "$work/out" 2>&1
}

# 1: full restore (with select menu: snapshot 1)
writeconf; newdest
run '1\ny\n' -r; rc=$?
if [ $rc -eq 0 ] && same_as_src; then ok "restore: destination equals the snapshot"
else bad "restore (rc=$rc): $(tail -5 "$work/out")"; fi
[ "$(getcap "$work/dest/usr/bin/pingish" | awk '{print $2}')" = "cap_net_raw=ep" ] && ok "file capability restored" || bad "capability: $(getcap "$work/dest/usr/bin/pingish")"
getfacl -cp "$work/dest/home/user/acl-file" 2> /dev/null | grep -q '^user:1234:rw-' && ok "ACL in the destination kept (not stripped)" || bad "ACL stripped"
[ "$(getfattr --only-values -n user.comment "$work/dest/home/user/acl-file" 2> /dev/null)" = "borg keeps me" ] && ok "user xattr restored" || bad "xattr"
[ "$(stat -c '%u:%g %a' "$work/dest/home/user")" = "1234:2345 750" ] && ok "numeric owner + mode restored" || bad "owner $(stat -c '%u:%g %a' "$work/dest/home/user")"
[ "$(stat -c %i "$work/dest/usr/bin/a")" = "$(stat -c %i "$work/dest/usr/bin/b")" ] && ok "hard link restored" || bad "hard link"
[ ! -e "$work/dest/etc/new-file" ] && [ -f "$work/dest/etc/fstab" ] && ok "new file deleted, deleted file back" || bad "delete/restore"
[ -f "$work/dest/keep/local" ] && [ ! -e "$work/dest/keep/file" ] && ok "excluded folder untouched" || bad "exclude"
! mountpoint -q "$work/mnt" && ok "archive unmounted afterwards" || bad "still mounted"

# 2: -r ARCHIVE picks that archive, no menu
writeconf; newdest
run 'y\n' -r snap2; rc=$?
[ $rc -eq 0 ] && [ "$(cat "$work/dest/etc/hostname")" = "galaxias-v2" ] && ok "-r snap2" || bad "-r snap2 (rc=$rc): $(tail -3 "$work/out")"

# 3: dry run changes nothing and shows the changes
writeconf; newdest
before="$(fingerprint "$work/dest")"
run '' -n -r snap1; rc=$?
after="$(fingerprint "$work/dest")"
[ $rc -eq 0 ] && [ "$before" = "$after" ] && grep -q 'etc/fstab' "$work/out" && grep -Eq 'deleting +etc/new-file' "$work/out" && ok "dry run: nothing changed, changes listed" || bad "dry run (rc=$rc): $(tail -5 "$work/out")"
! mountpoint -q "$work/mnt" && ok "dry run unmounts" || bad "dry run still mounted"

# 4: answer n -> nothing changed
writeconf; newdest
before="$(fingerprint "$work/dest")"
run 'n\n' -r snap1; rc=$?
[ $rc -eq 0 ] && [ "$before" = "$(fingerprint "$work/dest")" ] && ! mountpoint -q "$work/mnt" && ok "answer n: nothing changed, unmounted" || bad "answer n (rc=$rc)"

# 5: archive without etc/ and usr/ -> refused, with -f restored
writeconf; newdest
before="$(fingerprint "$work/dest")"
run 'y\n' -r dataonly; rc=$?
[ $rc -eq 1 ] && [ "$before" = "$(fingerprint "$work/dest")" ] && grep -q 'does not look like a system' "$work/out" && ! mountpoint -q "$work/mnt" && ok "non-system archive refused, unmounted" || bad "non-system (rc=$rc): $(tail -3 "$work/out")"
run 'y\n' -f -r dataonly; rc=$?
[ $rc -eq 0 ] && [ -f "$work/dest/just-data" ] && [ ! -e "$work/dest/etc" ] && ok "-f restores it anyway" || bad "-f (rc=$rc)"

# 6: borg mount fails -> abort, nothing changed (borg wrapper that fails on mount)
writeconf; newdest
mkdir -p "$work/fakebin"
cat > "$work/fakebin/borg" <<EOF
#!/bin/bash
[ "\$1" = mount ] && { echo "fuse: simulated failure" >&2; exit 2; }
exec $(command -v borg) "\$@"
EOF
chmod +x "$work/fakebin/borg"
before="$(fingerprint "$work/dest")"
PATH="$work/fakebin:$PATH" run 'y\n' -r snap1; rc=$?
[ $rc -eq 1 ] && [ "$before" = "$(fingerprint "$work/dest")" ] && grep -q 'borg mount failed' "$work/out" && ok "borg mount failure: abort, nothing changed" || bad "mount failure (rc=$rc): $(tail -3 "$work/out")"

# 7: borg mount "succeeds" but nothing is mounted -> abort
cat > "$work/fakebin/borg" <<EOF
#!/bin/bash
[ "\$1" = mount ] && exit 0
exec $(command -v borg) "\$@"
EOF
PATH="$work/fakebin:$PATH" run 'y\n' -r snap1; rc=$?
[ $rc -eq 1 ] && [ "$before" = "$(fingerprint "$work/dest")" ] && grep -q 'not mounted' "$work/out" && ok "no mount after borg mount: abort" || bad "fake mount (rc=$rc): $(tail -3 "$work/out")"

# 8: borg 2 is refused
cat > "$work/fakebin/borg" <<'EOF'
#!/bin/bash
[ "$1" = --version ] && { echo "borg 2.0.0b14"; exit 0; }
exit 1
EOF
PATH="$work/fakebin:$PATH" run '' -l; rc=$?
[ $rc -eq 1 ] && grep -q 'borg 2.0.0b14 is not supported' "$work/out" && ok "borg 2 refused" || bad "borg 2 (rc=$rc): $(cat "$work/out")"
rm -rf "$work/fakebin"

# 9: unknown archive, broken repository, non-empty mount point
writeconf
run '' -r nope; rc=$?
[ $rc -eq 1 ] && grep -q "archive 'nope' not found" "$work/out" && ok "unknown archive refused" || bad "unknown archive (rc=$rc)"
writeconf "$work/no-such-repo"
run '\n' -l; rc=$?
[ $rc -eq 1 ] && grep -q 'cannot list the archives' "$work/out" && ok "broken repository: error" || bad "broken repo (rc=$rc): $(cat "$work/out")"
writeconf; mkdir -p "$work/mnt" && touch "$work/mnt/x"
run 'y\n' -r snap1; rc=$?
rm -f "$work/mnt/x"
[ $rc -eq 1 ] && grep -q 'is not empty' "$work/out" && ok "non-empty mount point refused" || bad "non-empty mountpoint (rc=$rc)"

# 10: encrypted repository: passphrase asked once, works
writeconf "$work/crepo"; newdest
run 's3cret pass\ny\n' -r csnap; rc=$?
n=$(grep -c 'Borg passphrase for' "$work/out")
[ $rc -eq 0 ] && [ "$n" = 1 ] && same_as_src && ok "encrypted repo: passphrase asked once, restored" || bad "encrypted (rc=$rc, asked=$n): $(tail -3 "$work/out")"
BORG_PASSPHRASE="s3cret pass" run '' -l; rc=$?
[ $rc -eq 0 ] && grep -qx csnap "$work/out" && ! grep -q 'Borg passphrase' "$work/out" && ok "BORG_PASSPHRASE from the environment" || bad "env passphrase (rc=$rc)"
echo 'BORG_PASSCOMMAND="echo s3cret pass"' >> "$conf"
run '' -l; rc=$?
[ $rc -eq 0 ] && grep -qx csnap "$work/out" && ok "BORG_PASSCOMMAND from the config" || bad "passcommand (rc=$rc): $(cat "$work/out")"

# 11: mount point inside the destination is protected
writeconf "$work/repo" "$work/dest/mnt"; newdest
run 'y\n' -r snap1; rc=$?
same_as_src /mnt > /dev/null 2>&1; same=$?
[ $rc -eq 0 ] && [ $same -eq 0 ] && [ -d "$work/dest/mnt" ] && ! mountpoint -q "$work/dest/mnt" && grep -q 'Recovery completed' "$work/out" && ok "mount point inside destination: protected, restore ok" || bad "mountpoint in dest (rc=$rc, same=$same): $(tail -5 "$work/out")"

# 11b: local repository inside the destination, with [ ] in its name, via file://
newdest
cp -a "$work/repo" "$work/dest/repo[old]"
writeconf "file://$work/dest/repo[old]"
run 'y\n' -r snap1; rc=$?
same_as_src '/repo\[old\]' > /dev/null 2>&1; same=$?
[ $rc -eq 0 ] && [ $same -eq 0 ] && [ -f "$work/dest/repo[old]/config" ] && ok "repo inside destination (file://, [ ] in name) protected" || bad "repo in dest (rc=$rc, same=$same): $(tail -5 "$work/out")"

# 11c: destination inside the mount point or equal to the repository is refused
writeconf "$work/repo" "$work"
run 'y\n' -r snap1; rc=$?
[ $rc -eq 1 ] && grep -q 'is the same as or inside' "$work/out" && ok "destination inside the mount point refused" || bad "dest in mountpoint (rc=$rc): $(tail -3 "$work/out")"
! mountpoint -q "$work" && ok "...and unmounted again" || { umount "$work"; bad "still mounted on $work"; }

# 11d: archive unmounted while the confirmation is pending -> abort, nothing changed
writeconf; newdest
before="$(fingerprint "$work/dest")"
rm -f "$work/fifo"; mkfifo "$work/fifo"
"$BR" -c "$conf" -r snap1 < "$work/fifo" > "$work/out" 2>&1 &
pid=$!
exec 7> "$work/fifo"
for _ in $(seq 1 100); do mountpoint -q "$work/mnt" && break; sleep 0.1; done
sleep 1
umount "$work/mnt"
echo y >&7
exec 7>&-
wait "$pid"; rc=$?
[ $rc -eq 1 ] && [ "$before" = "$(fingerprint "$work/dest")" ] && grep -q 'not mounted (anymore)' "$work/out" && ok "unmounted during confirmation: abort, nothing changed" || bad "unmount race (rc=$rc): $(tail -3 "$work/out")"

# 12: config checks, -l, help, non-root
printf 'BORGREPO="%s"\nCONFIGURED="0"\n' "$work/repo" > "$conf"
run '' -l; rc=$?
[ $rc -eq 1 ] && grep -q 'configure the config file' "$work/out" && ok "CONFIGURED=0 (old config) refused" || bad "CONFIGURED=0 (rc=$rc)"
printf 'BORGREPO=""\n' > "$conf"
run '' -l; rc=$?
[ $rc -eq 1 ] && grep -q 'BORGREPO is not set' "$work/out" && ok "empty BORGREPO refused" || bad "empty BORGREPO (rc=$rc)"
writeconf
run '' -l; rc=$?
[ $rc -eq 0 ] && [ "$(grep -c '^snap\|^dataonly' "$work/out")" = 3 ] && ok "-l lists 3 archives" || bad "-l (rc=$rc): $(cat "$work/out")"
"$BR" -h > /dev/null && "$BR" > /dev/null && ok "-h and no arguments show help" || bad "help"
if command -v setpriv > /dev/null; then
	out="$(setpriv --reuid=65534 --regid=65534 --clear-groups "$BR" -c "$conf" -l 2>&1)"; rc=$?
	[ $rc -eq 1 ] && [[ $out == *"need to be root"* ]] && ok "non-root refused" || bad "non-root (rc=$rc, $out)"
fi

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
