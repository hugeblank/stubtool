#!/bin/sh

## Stubtool - a bootstrap script for efibootmgr. Makes setting up efistubs on arch easier.
# For use in arch-chroot, or directly on the system.
# Expects:
# - packages `efibootmgr` `awk` and `sed` be installed
# - to be run as root
# - devices that fit the format: `/dev/sdX` or `/dev/nvmeXnY` (sata drives or nvme drives, essentially)
# - boot partition to be mounted at `/boot`
# - root partition to be mounted at `/`
# - at least 1 mkinitcpio preset be present. (found in `/etc/mkinitcpio.d`. should be present if at least one linux kernel package is installed)
# Prefers:
# - at least 1 swap partition be mounted (for setting up hibernation)
# Notes:
# If setting up a btrfs system, make sure to provide the root subvol details when the "Additional flags" are requested. (ex. `rootflags=subvol=@`)
# If multiple swap partitions are found, a dialog will appear to allow for choosing one for the hibernate option.

# Check for dependencies
pacman -Q efibootmgr awk sed >/dev/null
if [ $? -ne 0 ]; then
    echo Missing dependencies >>/dev/stderr
    exit 1 
fi



# Read in disks by uuid
declare -a drives
i=0
while IFS= read -r line; do
    drives[i]=$line
    i=$(($i+1))
done <<< $(ls -l /dev/disk/by-uuid | tail -n "+2" | awk '{print $9" "$11}')

boot=""
root=""
swap=""

# Get the amount of swap partitions
swapcount=$(cat /proc/swaps | tail -n "+2" | wc -l)

get_uuid() {
    echo $(echo $1 | awk '{print $1}')
}

# For each drive with a uuid
for key in ${!drives[@]}; do
    # Isolate the UUID and real path in /dev
    id=$(get_uuid ${drives[$key]})
    dev=$(echo ${drives[$key]} | awk '{print $2}' | sed -e 's/\.\.\/\.\./\/dev/g')
    # Also determine where it's mounted
    mount=$(df | grep $dev | awk '{print $6}')
    if [ -n "$mount" ]; then
        # Auto-detect boot and root partitions
        if [ "$mount" == "/" ]; then
            echo root partition detected
            root="$id $dev $mount"
        elif [ "$mount" == "/boot" ]; then
            echo boot partition detected
            boot="$id $dev $mount"
        fi
        # Rewrite the drive value to include the real path and mountpoint
        drives[$key]="$id $dev $mount"
    else
        # Auto-detect swap volume
        cat /proc/swaps | grep $dev >/dev/null
        if [ $? -eq 0 ]; then
            if [ $swapcount -eq 1 ]; then
                echo swap partition detected
                swap="$id $dev"
            fi
            drives[$key]="$id $dev swap"
        else
            # Rewrite the drive value to include the real path
            drives[$key]="$id $dev"
        fi
    fi
done

list_drives() {
    for key in ${!drives[@]}; do
        echo $key: $(echo ${drives[$key]} | awk '{print $1" "$2" (mounted as "$3")"}')
    done
}

if [ -z "$boot" ]; then
    echo "No boot volume detected." >>/dev/stderr
    exit 1
elif [ -z "$root" ]; then
    echo "No root volume detected." >>/dev/stderr
    exit 1
elif [ -z "$swap" ]; then
    echo "No swap volume detected."
    resume=1
    while [ $resume -ne 0 ]; do
        list_drives
        echo -n "Select device [optional, number]: "
        read -r input
        input=$(echo $input | sed -E 's/[^0-9]+//')
        if [ -n "$input" ]; then
            if [ "$(echo ${drives[$input]} | awk '{print $3}')" == "swap" ]; then
                swap=${drives[$input]}
                resume=0
            else
                echo "Invalid device, choose a swap partition."
            fi
        else
            resume=0
            echo "No swap partition selected, skipping."
        fi
    done
fi

# Get boot device and partition number isolated
dev=$(echo $boot | awk '{print $2}')
disk=$(echo $dev | sed -E 's/p?[0-9]+$//')
# for hard drives: https://superuser.com/questions/406272/maximum-amount-of-hard-drives-in-64-bit-linux
# no idea if the expression is also valid for the nvme devices.
# also no idea if any other drive types should be implemented. sr0 anyone? probably not.
part=$(echo $dev | sed -E 's/^\/dev\/(sd[a-z]+|nvme([0-9]+n[0-9]+)p)//')

presets=($(ls /etc/mkinitcpio.d))

for key in ${!presets[@]}; do
    echo "Using preset $(echo ${presets[$key]} | sed -E 's/^\/etc\/mkinitcpio\.d\///' | sed -E 's/\.preset$//')"
    source /etc/mkinitcpio.d/${presets[$key]}
    vmlinuz=$(echo $ALL_kver | sed -E "s/^\/boot//")
    for ikey in ${!PRESETS[@]}; do
        echo -n "Make EFI stub for ${PRESETS[$ikey]}? [y/n]: "
        read -r input
        input=$(echo $input | sed -E 's/[^yn]+//')
        if [ "$input" == "y" ]; then
            imgpathname=${PRESETS[$ikey]}_image
            initramfs=$(echo ${!imgpathname} | sed -E "s/^\/boot\///")

            # Stub Label
            label="ARCH"
            echo -n "Label [default=ARCH]: "
            read -r input
            if [ -n "$input" ]; then
                label=$input
            fi

            # Swap resume flag
            swapflags=""
            if [ -n "$swap" ]; then
                swapflags="resume=UUID=$(get_uuid $swap)"
            fi

            # User specified flags (eg. btrfs subvolume)
            echo -n "Additional flags [optional]: "
            read -r optflags

            echo "Will execute: efibootmgr --create --disk $disk --part $part --label $label --loader $vmlinuz --unicode \"root=UUID=$(get_uuid $root) $swapflags rw $optflags initrd=\\$initramfs\""
            echo -n "Ok? [y/n]: "
            read -r input
            input=$(echo $input | sed -E 's/[^yn]+//')
            if [ "$input" == "y" ]; then
                efibootmgr --create --disk $disk --part $part --label $label --loader $vmlinuz --unicode "root=UUID=$(get_uuid $root) $swapflags rw $optflags initrd=\\$initramfs"
            fi
        fi
    done
done
