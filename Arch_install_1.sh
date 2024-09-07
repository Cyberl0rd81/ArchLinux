#!/bin/bash

### File in Linux Format convertieren: vim file.txt -c "set ff=unix" -c ":wq"

### Laufwerk definieren (z.B. /dev/sda)
lsblk
read -p "Bitte gib hier die Festplatte an: " disk

echo "Partitionen anlegen und formatieren"

### Partitionen mit gdisk erstellen
sgdisk -o $disk

### EFI-Systempartition (512M MB)
sgdisk -n 1:0:+512M -t 1:EF00 $disk

### Root-Partition (20 GB)
sgdisk -n 2:0:0 -t 2:8300 $disk

### Änderungen schreiben und Partitionstabelle neu laden
partprobe $disk

### Partitionen formatieren
mkfs.fat -F32 -n BOOT ${disk}1
mkfs.ext4 -L ROOT ${disk}2

### Partitionen einhängen
mount -L ROOT /mnt
mkdir -p /mnt/boot
mount -L BOOT /mnt/boot

echo "Partitionierung und Formatierung abgeschlossen."

### Pakete installieren
echo "Pakete intallieren."
pacstrap /mnt base base-devel linux linux-firmware dhcpcd nano iwd intel-ucode
echo "Pakete installiert"

### Fstab anlegen
echo "Fstab anlegen"
genfstab -U /mnt > /mnt/etc/fstab
echo "Fstab angelegt"

### Chroot Umgebung starten
cp arch_install.sh /mnt
echo "Chroot starten"
arch-chroot /mnt ./arch_install.sh