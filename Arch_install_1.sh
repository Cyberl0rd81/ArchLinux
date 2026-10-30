#!/bin/bash

### Installerscript mit folgendem Befehl herunterladen:
### curl -O https://raw.githubusercontent.com/yourusername/yourrepository/main/arch_install.sh
### curl -O https://raw.githubusercontent.com/yourusername/yourrepository/main/arch_install_1.sh
### oder
### git clone https://github.com/yourusername/yourrepository.git

set -Eeuo pipefail

if (( EUID != 0 )); then
	printf 'Dieses Skript muss als root ausgeführt werden.\n' >&2
	exit 1
fi

if [[ ! -d /sys/firmware/efi ]]; then
	printf 'Das Installationsmedium wurde nicht im UEFI-Modus gestartet.\n' >&2
	exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ ! -f $script_dir/arch_install.sh ]]; then
	printf 'arch_install.sh wurde neben diesem Skript nicht gefunden.\n' >&2
	exit 1
fi

### File in Linux Format convertieren: vim file.txt -c "set ff=unix" -c ":wq"

### Laufwerk definieren (z.B. /dev/sda)
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
read -r -p "Bitte gib hier die Festplatte an: " disk
disk=$(readlink -f -- "$disk")

if [[ ! -b $disk ]] || [[ $(lsblk -dnro TYPE -- "$disk") != disk ]]; then
	printf 'Ungültiges Laufwerk: %s\n' "$disk" >&2
	exit 1
fi

if lsblk -nrpo MOUNTPOINTS -- "$disk" | grep -q '[^[:space:]]'; then
	printf 'Das Laufwerk oder eine seiner Partitionen ist eingehängt.\n' >&2
	exit 1
fi

if mountpoint -q /mnt || mountpoint -q /mnt/boot; then
	printf '/mnt oder /mnt/boot ist bereits eingehängt.\n' >&2
	exit 1
fi

printf '\nACHTUNG: Alle Partitionen auf %s werden gelöscht.\n' "$disk"
read -r -p 'Zum Fortfahren exakt "ja" eingeben: ' confirmation
if [[ ${confirmation,,} != ja ]]; then
	printf 'Installation abgebrochen.\n'
	exit 1
fi

if [[ $disk =~ [0-9]$ ]]; then
	partition_prefix="${disk}p"
else
	partition_prefix=$disk
fi
boot_partition="${partition_prefix}1"
root_partition="${partition_prefix}2"

echo "Partitionen anlegen und formatieren"

### GPT-Partitionen erstellen
sgdisk -o "$disk"

### EFI-Systempartition (512M MB)
sgdisk -n 1:0:+512M -t 1:EF00 "$disk"

### Root-Partition (verbleibender Speicherplatz)
sgdisk -n 2:0:0 -t 2:8300 "$disk"

### Änderungen schreiben und Partitionstabelle neu laden
partprobe "$disk"
udevadm settle

### Partitionen formatieren
mkfs.fat -F32 -n BOOT "$boot_partition"
mkfs.ext4 -L ROOT "$root_partition"

### Partitionen einhängen
mount "$root_partition" /mnt
mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

echo "Partitionierung und Formatierung abgeschlossen."

### Pakete installieren
echo "Pakete intallieren."
pacstrap /mnt base base-devel linux linux-firmware dhcpcd nano iwd intel-ucode efibootmgr dosfstools gptfdisk
echo "Pakete installiert"

### Fstab anlegen
echo "Fstab anlegen"
genfstab -U /mnt > /mnt/etc/fstab
echo "Fstab angelegt"

### Chroot Umgebung starten
install -m 0755 "$script_dir/arch_install.sh" /mnt/arch_install.sh
echo "Chroot starten"
arch-chroot /mnt ./arch_install.sh