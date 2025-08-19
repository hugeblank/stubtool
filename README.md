# stubtool
Bootstrap script for `efibootmgr`. Makes setting up efistubs on arch easier.
For use in `arch-chroot`, or directly on the system.

## Requirements
- packages `efibootmgr` `awk` and `sed` be installed
- to be run as root
- devices that fit the format: `/dev/sdX` or `/dev/nvmeXnY` (sata drives or nvme drives, essentially)
- boot partition to be mounted at `/boot`
- root partition to be mounted at `/`
- at least 1 mkinitcpio preset be present (found in `/etc/mkinitcpio.d`. should be present if at least one linux kernel package is installed)

### Optional
- at least 1 swap partition be mounted (for setting up hibernation)

## Notes
- If setting up a btrfs system, make sure to provide the root subvol details when the "Additional flags" are requested (ex. `rootflags=subvol=@`.) See [the wiki](https://wiki.archlinux.org/title/EFI_boot_stub#efibootmgr) for more details.
- If multiple swap partitions are found, a dialog will appear to allow for choosing one of them for use in the hibernate option. This can be skipped by pressing enter without inputting anything (in the same way as the other optional prompts.)