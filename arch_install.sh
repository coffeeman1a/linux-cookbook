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
target=""

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
        -h|--help)
            echo "try using: $0 [--cpu-model <intel|amd>] [--vpn] [--bltz] [--wifi] [--laptop] [--tz <Europe/Moscow>] [--locale <ru_RU.UTF-8>] [--hostname <arch>]"
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

read -rsp "Enter root password: " root_pw; echo

read -rp "Enter your username: " username
read -rsp "Enter user password: " user_pw; echo

read -rp "Continue with installation [y/N]: " ok; echo
if [[ "$ok" != "y" && "$ok" != "Y" ]]; then
    echo "Installation aborted by user"
    exit 0
fi

echo "Installing main packages..."
pacstrap -K /mnt \
    base linux linux-firmware \
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
systemctl enable fwupd.service

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
fi

echo "Rebuilding initramfs..."
mkinitcpio -P

echo "Installing and configuring GRUB for UEFI..."
mkdir -p /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Configuration complete! You can now unmount /mnt and reboot into your new Arch system. Hope you enjoyed your coffee."
