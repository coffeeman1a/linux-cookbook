#!/bin/bash
set -euo pipefail

# default variables
cpu_model=""
do_vpn=false
do_bltz=false
do_wifi=false
is_laptop=false
locale=""
tz=""
hostname="arch"
crypto=false
fs_type=""
crypto_UUID=""
raw_UUID=""

print_help() {
  cat <<EOF
    Usage: $0 [OPTIONS]

    Options:
    --cpu-model <intel|amd>    Install Intel or AMD CPU microcode
    --vpn                      Include IPsec/L2TP VPN support
    --bltz                     Include Bluetooth support
    --wifi                     Include Wi-Fi support
    --laptop                   Optimize for laptops (TLP, thermald, etc.)
    --tz <Region/City>         Set timezone (default: UTC)
    --locale <xx_YY.UTF-8>     Enable additional locale (default: en_US.UTF-8)
    --hostname <name>          Set system hostname (default: arch)
    --crypto                   Encrypt root partition with LUKS
    -h, --help                 Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu-model)
            if [[ -n "${2-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                cpu_model="$2"
                shift 2
            else
                echo "error: --cpu-model not set" >&2
                exit 1
            fi
            ;;
        --vpn)
            do_vpn=true
            shift
            ;;
        --bltz)
            do_bltz=true
            shift
            ;;
        --wifi)
            do_wifi=true
            shift
            ;;
        --laptop)
            is_laptop=true
            shift
            ;;
        --locale)
            if [[ -n "${2-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                locale="$2"
                shift 2
            else
                echo "error: --local not set" >&2
                exit 1
            fi
            ;;
        --tz)
            if [[ -n "${2-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                tz="$2"
                shift 2
            else
                echo "error: --timezone not set" >&2
                exit 1
            fi
            ;;
        --hostname)
             if [[ -n "${2-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                hostname="$2"
                shift 2
            else
                echo "error: --hostname not set" >&2
                exit 1
            fi
            ;;
        --crypto)
            crypto=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "unexpected option: $1" >&2
            echo "try $0 --help" >&2
            exit 1
            ;;
    esac
done

cat <<'EOF'
===============================================================================================                                                                                     
  /$$$$$$             /$$$$$$   /$$$$$$    /$$   /$$       /$$                                \\
 /$$__  $$           /$$__  $$ /$$__  $$ /$$$$  | $$      |__/                                //
| $$  \__/  /$$$$$$ | $$  \__/| $$  \__/|_  $$  | $$       /$$ /$$$$$$$  /$$   /$$ /$$   /$$  \\
| $$       /$$__  $$| $$$$    | $$$$      | $$  | $$      | $$| $$__  $$| $$  | $$|  $$ /$$/  //
| $$      | $$  \ $$| $$_/    | $$_/      | $$  | $$      | $$| $$  \ $$| $$  | $$ \  $$$$/   \\
| $$    $$| $$  | $$| $$      | $$        | $$  | $$      | $$| $$  | $$| $$  | $$  >$$  $$   //
|  $$$$$$/|  $$$$$$/| $$      | $$       /$$$$$$| $$$$$$$$| $$| $$  | $$|  $$$$$$/ /$$/\  $$  \\
 \______/  \______/ |__/      |__/      |______/|________/|__/|__/  |__/ \______/ |__/  \__/  //
===============================================================================================
EOF

select_fs() { # select_fs() -> void
    echo "Available file systems:"
    echo "1) ext4 2) btrfs"
    read -p "Select fs (1-2): [1 by default]" fs_choice

    case $fs_choice in
        1)
            fs_type="ext4"
            ;;
        2)
            fs_type="btrfs"
            ;;
        *)
            echo "Using default option..."
            fs_type="ext4"
    esac
    echo "Selected fs: $fs_type"
}

clear_and_create_gpt() { # clear_and_create_gpt(target_disk [/dev/sda]) -> void
    local target_disk=$1

    echo "Cleaning disk $target_disk"
    wipefs -a $target_disk

    echo "Creating GPT partition table on $target_disk..."
    parted $target_disk -s mklabel gpt
}

check_gpt() { # check_gpt() -> 0 | 1 
    local disk=$1
    parted $disk print | grep -q "Partition Table: gpt"
    return $?
}

create_partition() { # create_partition(target_disk [/dev/sda], size_G [32], fs [ext4], use_remaining [true | false]]) -> void
    local target_disk=$1
    local size_G=$2
    local fs=$3
    local use_remaining=$4

    last_partition=$(lsblk -n -o NAME $target_disk | grep -o '[0-9]*$' | sort -n | tail -n 1)
    if [[ -z "$last_partition" ]]; then
        last_partition=0
    fi

    new_partition=$((last_partition + 1))

    if [[ "$use_remaining" == "true" ]]; then
        start_point=$(parted $target_disk unit MiB print | awk '/^[[:space:]]*[0-9]+/ { end=$3 } END{ print end }')
        echo "Creating a partition on disk $target_disk with fs $fs, using the remaning space..."
        parted $target_disk mkpart primary $fs $start_point 100%
    else
        local size_MB=$((size_G * 1024))

        echo "Creating a partition on disk $target_disk with fs $fs"
            parted $target_disk mkpart primary $fs 1MiB ${size_MB}MiB
        echo "Partition $new_partition created successfully"
    fi
}

create_boot_partition() {
    local target_disk=$1
    parted $target_disk --script mkpart ESP fat32 1MiB 1024MiB
    parted $target_disk --script set 1 esp on
}

format_partition() {
    local target_partition=$1
    local fs=$2

    echo "Formating partition $target_partition..."
    if [[ "$fs" == "fat32" ]]; then
        mkfs.fat -F 32 $target_partition
    else
        mkfs.$fs -f $target_partition
    fi
    echo "Partition $target_partition formatted successfully"
}

create_luks_partition() { # create_luks_partition(target_disk [/dev/sda], use_remaining [true | false])
    local target_disk=$1
    local size_G=$2
    local use_remaining=$4

    last_partition=$(lsblk -n -o NAME $disk | grep -o '[0-9]*$' | sort -n | tail -n 1)
    if [[ -z "$last_partition" ]]; then
        last_partition=0
    fi

    new_partition=$((last_partition + 1))
    if [[ "$use_remaining" == "true" ]]; then
        start_point=$(parted $target_disk unit MiB print | awk '/^[[:space:]]*[0-9]+/ { end=$3 } END{ print end }')
        echo "Creating a luks container on disk $target_disk, using the remaning space..."
        parted "$target_disk" mkpart cryptroot $start_point 100%
    else
        local size_MB=$((size_G * 1024))
        echo "Creating a luks container on disk $target_disk"F
            parted "$target_disk" mkpart cryptroot $start_point ${size_MB}MiB
        echo "Partition $new_partition created successfully"
    fi
}

echo -e "Welcome to arch linux installation helper! Go grep some coffee\n"

echo "CPU model: ${cpu_model:-not specified}"
echo "VPN flag: $do_vpn"
echo "Bltz flag: $do_bltz"
echo "WiFi flag: $do_wifi"
echo "Laptop flag: $is_laptop"
if [[ "${locale:-}" ]]; then
    echo "Locale: $locale"
else
    echo "Locale: en_US.UTF-8"
fi
if [[ "${tz:-}" ]]; then
    echo "Timezone: $tz"
else
    echo "Timezone: UTC"
fi
echo "Hostname: $hostname"

lsblk
read -rp "Enter target disk (for example, /dev/sda): " target; echo
select_fs
read -rsp "Enter root password: " root_pw; echo
read -rsp "Repeat root password: " root_pw_test; echo
if [[ "$root_pw" != "$root_pw_test" ]]; then 
    echo "Password mismatch"
    exit 0
fi

read -rp "Enter your username: " username
read -rsp "Enter user password: " user_pw; echo
read -rsp "Repeat user password: " user_pw_test; echo
if [[ "$user_pw" != "$user_pw_test" ]]; then 
    echo "Password mismatch"
    exit 0
fi

if [[ "$crypto" == true ]]; then
    read -rsp "Enter luks password: " luks_pw; echo
    read -rsp "Repeat luks password: " luks_pw_test; echo
    if [[ "$luks_pw" != "$luks_pw_test" ]]; then
        echo "Password mismatch"
        exit 0
    fi
fi

read -rp "Continue with installation [y/N]: " ok; echo
if [[ "$ok" != "y" && "$ok" != "Y" ]]; then
    echo "Installation aborted by user"
    exit 0
fi

echo "Marking partitions on $target..."
clear_and_create_gpt "$target"

if [[ "$crypto" == true ]]; then
    create_boot_partition "$target"
    create_luks_partition "$target" 100 true
else
    create_boot_partition "$target"
    create_partition "$target" 100 $fs_type true
fi

# partprobe "$target"

case "$target" in
  /dev/nvme*|/dev/mmcblk*)
    esp_part="${target}p1"
    second_part="${target}p2"
    ;;
  *)
    esp_part="${target}1"
    second_part="${target}2"
    ;;
esac

# echo "Marking partitions on $target..."
# if [[ "$crypto" == true ]]; then
#     parted "$target" --script \
#         mklabel gpt \
#         mkpart ESP fat32 1MiB 1024MiB \
#         set 1 esp on \
#         mkpart cryptroot 1024MiB 100%
# else
#     parted "$target" --script \
#         mklabel gpt \
#         mkpart ESP fat32 1MiB 1024MiB \
#         set 1 esp on \
#         mkpart primary ext4 1024MiB 100%
# fi

echo "Formatting EFI System Partition ($esp_part)..."
format_partition $esp_part fat32

if [[ "$crypto" == true ]]; then
    echo "Setting up LUKS on $second_part..."
    printf "%s" "$luks_pw" | \
        cryptsetup luksFormat "$second_part" --batch-mode --key-file=-
    printf "%s" "$luks_pw" | \
        cryptsetup open "$second_part" cryptroot --key-file=-
    echo "Formatting decrypted root (/dev/mapper/cryptroot)..."
    root_dev=/dev/mapper/cryptroot
    raw_UUID=$(blkid -s UUID -o value "$second_part")
    crypto_UUID=$(blkid -s UUID -o value "$root_dev")
else
    root_dev="$second_part"
fi

echo "Formatting root partition ($root_dev)..."
if [[ "$fs_type" == "btrfs" ]]; then
    mkfs.btrfs -f "$root_dev"
else
    mkfs.${fs_type} "$root_dev"
fi

echo "Mounting root partition on /mnt..."
mount "$root_dev" /mnt

if [[ "$fs_type" == "btrfs" ]]; then
    echo "Setting up subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@swap
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@games
    btrfs subvolume create /mnt/@snapshots

    umount /mnt

    mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$root_dev" /mnt
    mkdir -p /mnt/home
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$root_dev" /mnt/home
    mkdir -p /mnt/.snapshots
    mount -o noatime,subvol=@snapshots "$root_dev" /mnt/.snapshots
    mkdir -p /mnt/games
    mount -o noatime,space_cache=v2,subvol=@games "$root_dev" /mnt/games
    mkdir -p /mnt/swap
    mount -o noatime,space_cache=v2,subvol=@swap "$root_dev" /mnt/swap
    mkdir -p /mnt/var
    mount -o noatime,subvol=@var "$root_dev" /mnt/var
fi

echo "Mounting boot partition on /mnt/boot/..."
if [[ "$crypto" == "true" ]]; then
    mount --mkdir "$esp_part" /mnt/boot/
else
    mount --mkdir "$esp_part" /mnt/boot/efi
fi

echo "Installing main packages..."
pacstrap -K /mnt \
    base base-devel linux linux-firmware \
    networkmanager \
    dialog \
    mtools dosfstools \
    ntfs-3g exfat-utils \
    sudo \
    bash-completion \
    reflector pacman-contrib \
    grub efibootmgr os-prober \
    acpi acpid \
    smartmontools lm_sensors \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    gvfs gvfs-smb \
    cups cups-pdf \
    p7zip zip unzip \
    openssh \
    vim nano \
    xdg-utils xdg-user-dirs \
    ldns \
    git \
    htop \
    rsync \
    trash-cli \
    tree \
    jq \
    fzf

# base, linux, linux-firmware
#   - base: essential Arch Linux base system
#   - linux: the Linux kernel
#   - linux-firmware: firmware files for various hardware components (Wi-Fi, GPU, etc.)

# networkmanager
#   - network management daemon for Ethernet and Wi-Fi connections

# dialog
#   - utility for creating interactive text-based dialogs in scripts

# mtools, dosfstools
#   - tools for managing FAT filesystems (e.g., for EFI partitions)

# ntfs-3g, exfat-utils
#   - drivers and tools for NTFS and exFAT filesystem support

# sudo
#   - allows designated users to execute commands as root

# bash-completion
#   - programmable completion for Bash commands and options

# reflector, pacman-contrib
#   - reflector: automated mirror ranking
#   - pacman-contrib: extra utilities for pacman

# grub, efibootmgr, os-prober
#   - grub: GRUB bootloader (UEFI support)
#   - efibootmgr: EFI boot manager
#   - os-prober: OS autodetection for multi-boot setups

# acpi, acpid
#   - acpi: ACPI utilities
#   - acpid: daemon for handling power/battery events

# smartmontools, lm_sensors
#   - smartmontools: SMART monitoring for disks
#   - lm_sensors: sensor monitoring for temperature/voltage

# pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, wireplumber
#   - modern multimedia framework (PipeWire) with ALSA/PulseAudio/JACK compatibility and session manager

# gvfs, gvfs-smb
#   - userspace virtual filesystem and SMB (Samba) support for file browsing

# cups, cups-pdf
#   - CUPS printing system and virtual PDF printer backend

# p7zip, zip, unzip
#   - command-line tools for creating and extracting ZIP and 7z archives

# openssh
#   - OpenSSH server and client for secure remote access

# vim, nano
#   - popular terminal-based text editors

# xdg-utils, xdg-user-dirs
#   - utilities for handling XDG desktop integration and user directory creation

# ldns
#   - DNS library and utilities for DNS lookup and manipulation

# git
#   - distributed version control system for source code management

# htop
#   - interactive process viewer for real-time system monitoring

# rsync
#   - fast and versatile file-copying tool for backups and synchronization

# yay
#   - AUR helper for building and installing packages from the Arch User Repository

# trash-cli
#   - command-line trash/recycle bin utilities for safe file deletion

# tree
#   - display directory structure in a depth-indented listing

# jq
#   - lightweight and flexible command-line JSON processor

# fzf
#   - general-purpose command-line fuzzy finder for file and history search

if [[ "$crypto" == true ]]; then
    echo "Installing additional encryption packages..."
    pacstrap -K /mnt lvm2 cryptsetup
fi

if [[ -n "$cpu_model" ]]; then
    case "$cpu_model" in
        intel)  echo "Installing intel-ucode..."; pacstrap -K /mnt intel-ucode ;;
        amd)    echo "Installing amd-ucode..."; pacstrap -K /mnt amd-ucode ;;
        # microcode fixes
    esac
fi

if [[ "$do_vpn" == true ]]; then
    echo "Installing additional VPN packages..."
    pacstrap -K /mnt \
        strongswan \
        xl2tpd \
        ppp \
        networkmanager-l2tp
fi

# strongswan             — IPsec daemon: handles key exchange and encrypted VPN tunnels
# xl2tpd                 — L2TP daemon: implements Layer 2 Tunneling Protocol for tunneling sessions
# ppp                    — PPP support: required for L2TP over PPP connections
# networkmanager-l2tp    — NetworkManager plugin: provides easy GUI/CLI integration for IPsec+L2TP

if [[ "$do_bltz" == true ]]; then
    echo "Installing additional Bluetooth packages..."
    pacstrap -K /mnt \
        bluez \
        bluez-utils
fi

# bluez                  — Core Bluetooth stack: provides daemons and libraries for Bluetooth devices
# bluez-utils            — Command-line utilities (bluetoothctl, etc.) for scanning, pairing, and managing devices

if [[ "$do_wifi" == true ]]; then
    echo "Installing additional Wi-Fi packages..."
    pacstrap -K /mnt \
        wpa_supplicant     # WPA/WPA2/WPA3 client: secures wireless network connections
fi

if [[ "$is_laptop" == true ]]; then
    echo "Installing additional laptop packages..."
    pacstrap -K /mnt \
        tlp \
        tlp-rdw \
        brightnessctl \
        powertop \
        thermald \
        upower \
        fwupd
fi

# tlp          — Advanced power management: tunes CPU governors, disk spindown, USB autosuspend, etc.
# tlp-rdw      — Radio-Device-Wizard: integrates with TLP to manage Wi-Fi/Bluetooth radios
# brightnessctl — CLI tool to adjust screen and keyboard-backlight brightness
# powertop     — Interactive power consumption analyzer with automatic tuning recommendations
# thermald     — Thermal daemon: dynamically controls throttling to prevent overheating
# upower       — D-Bus power monitoring service: exposes battery/adapter status for DEs and applets
# fwupd        — Firmware update daemon: installs signed BIOS/firmware updates via LVFS


echo "All required packages installed!"

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Entering chroot to configure the system..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

echo "Creating 4 GiB swap-file..."

if [[ "$fs_type" == "btrfs" ]]; then
    mkdir -p /swap
    chattr +C /swap

    dd if=/dev/zero of=/swap/swapfile bs=1M count=4096 status=progress

    chmod 600 /swap/swapfile
    mkswap  /swap/swapfile
    swapon  /swap/swapfile

    cat >> /etc/fstab <<FSTAB
/swap/swapfile none swap defaults 0 0
FSTAB
else
    fallocate -l 4G /swapfile

    chmod 600       /swapfile
    mkswap          /swapfile
    swapon /swapfile

    cat >> /etc/fstab <<FSTAB
/swapfile none swap defaults 0 0
FSTAB
fi  

if [[ $crypto == "true" ]]; then
    echo "cryptroot UUID="$raw_UUID" none luks" >> /etc/crypttab
fi

echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/\${tz:-UTC} /etc/localtime
hwclock --systohc

echo "Generating locale..."
if [[ -n "\${locale:-}" ]]; then
  sed -i "s/^#\${locale}\.UTF-8/\${locale}.UTF-8/" /etc/locale.gen
fi
sed -i "s/^#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
locale-gen

echo "Setting hostname..."
echo "$hostname" > /etc/hostname

echo "Setting root password..."
echo "root:${root_pw}" | chpasswd

echo "Creating a regular user..."
useradd -m -G wheel -s /bin/bash "$username"

echo "${username}:${user_pw}" | chpasswd

echo "Adding wheel group to sudoers..."
sed -i 's/^# %wheel/%wheel/' /etc/sudoers

echo "Enabling system services..."
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable acpid
systemctl enable cups.service
systemctl enable smartd.service

if [[ "${do_vpn}" == true ]]; then
  systemctl enable strongswan xl2tpd
fi

if [[ "${do_bltz}" == true ]]; then
  systemctl enable bluetooth
fi

if [[ "${do_wifi}" == true ]]; then
  systemctl enable wpa_supplicant
fi

if [[ "${is_laptop}" == true ]]; then
  systemctl enable tlp thermald upower
  systemctl enable fwupd.service
fi

echo "Rebuilding initramfs..."
if [[ $crypto == "true" ]]; then
    sed -i 's/\(HOOKS=.*block\)/\1 encrypt lvm2/' /etc/mkinitcpio.conf
fi
mkinitcpio -P
echo "Installing and configuring GRUB for UEFI..."
if [[ $crypto == "true" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB "$target"
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet cryptdevice=UUID=$raw_UUID:cryptroot root=UUID=$crypto_UUID"/' /etc/default/grub
else
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB "$target"
fi
grub-mkconfig -o /boot/grub/grub.cfg
echo "Configuration complete! You can now unmount /mnt and reboot into your new Arch system. Hope you enjoyed your coffee."
EOF
