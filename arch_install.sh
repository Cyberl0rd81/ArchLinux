#!/bin/bash

set -euo pipefail

if (( EUID != 0 )); then
	printf 'Dieses Skript muss als root ausgeführt werden.\n' >&2
	exit 1
fi

### Grundvariablen abfragen
read -r -p "Bitte gib den Hostnamen ein: " host_name
read -r -p "Bitte gib deinen Benutzernamen ein: " username
echo "Wähle aus welche Pakete du installiert haben möchtest"
echo "1 = Xfce incl. Loginmanager und Tools"
echo "2 = SSH"
echo "3 = SMB/NFS"
echo "4 = Docker incl. Dockge"
echo "5 = Qemu incl. Cockpit"
echo "6 = Pentesting Tools"
echo "7 = VmWare Tools"
echo "8 = Bootmanager UEFI"
echo "9 = Bootmanager Syslinux"
echo "###################################"
read -r -p "Bitte gib eine Mehrfachauswahl mit , getrennt an z.B. 1, 4, 5: " selected_packages
IFS=',' read -r -a pakete_array <<< "$selected_packages"
for index in "${!pakete_array[@]}"; do
	element=${pakete_array[index]//[[:space:]]/}
	if [[ ! $element =~ ^[1-9]$ ]]; then
		printf 'Ungültige Paketauswahl: %s\n' "${pakete_array[index]}" >&2
		exit 1
	fi
	pakete_array[index]=$element
done

### Hostname definiere
printf '%s\n' "$host_name" > /etc/hostname


### Deutsches Layout verwenden te
printf 'LANG=de_DE.UTF-8\nLC_COLLATE=C\n' > /etc/locale.conf
echo KEYMAP=de-latin1 > /etc/vconsole.conf
echo FONT=lat9w-16 >> /etc/vconsole.conf

### Zeitzone definieren
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime


{
	printf '%s\n' \
		'de_DE.UTF-8 UTF-8' \
		'de_DE ISO-8859-1' \
		'de_DE@euro ISO-8859-15' \
		'en_US.UTF-8 UTF-8'
} >> /etc/locale.gen
locale-gen

### Initramfs erzeugen
mkinitcpio -p linux

### Root Passwort setzen
echo "Root Passwort definieren"
passwd

### User anlegen
useradd -m -g users -s /bin/bash "$username"
echo "Bitte gib dein Userpasswort ein"
passwd "$username"

### User zu Gruppen hinzufügen
usermod -aG wheel,audio,video "$username"
install -d -m 0750 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
visudo -c

### Basispakete installieren
pacman -S --noconfirm acpid ntp dbus avahi sudo connman cronie wget

### Basispakte Dienste aktivieren
systemctl enable cronie acpid ntpd avahi-daemon connman.service

### Hardwareuhr aktualisieren
ntpd -gq
hwclock -w

for element in "${pakete_array[@]}"
do
	if [ "$element" -eq 1 ]; then
		echo "Xfce wird installiert"
		pacman -S --noconfirm xorg-server xorg-xinit xorg-drivers xorg-apps xorg-xdm xfce4 xfce4-goodies terminator
		systemctl enable xdm-archlinux.service
		localectl set-x11-keymap de pc105 deadgraveacute
	elif [ "$element" -eq 2 ]; then
		echo "SSH wird installiert"
		pacman -S --noconfirm openssh
		systemctl enable sshd.service
	elif [ "$element" -eq 3 ]; then
		echo "SMB/NFS wird installiert"
		pacman -S --noconfirm samba nfs-utils
		systemctl enable smb.service
		wget -O /etc/samba/smb.conf 'https://git.samba.org/samba.git/?p=samba.git;a=blob_plain;f=examples/smb.conf.default;hb=HEAD'
	elif [ "$element" -eq 4 ]; then
		echo "Docker incl. Dockge wird installiert"
		pacman -S --noconfirm docker docker-compose podman
		systemctl enable docker.service
		mkdir -p /opt/dockge /opt/stacks
		cat > /opt/dockge/docker-compose.yml <<'EOF'
services:
  dockge:
    image: louislam/dockge:1
    restart: unless-stopped
    ports:
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
EOF
		cat > /etc/systemd/system/dockge.service <<'EOF'
[Unit]
Description=Dockge Docker Compose UI
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/dockge
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF
		systemctl enable dockge.service
	elif [ "$element" -eq 5 ]; then
		echo "Qemu incl. Cockpit wird installiert"
		pacman -S qemu-full cockpit cockpit-machines cockpit-podman cockpit-storaged cockpit-packagekit networkmanager udisks2 pcp
		systemctl enable cockpit.socket
	elif [ "$element" -eq 6 ]; then
		echo "Pentesting Tools werden installiert"
	elif [ "$element" -eq 7 ]; then
		echo "VmWare Tools werden installiert"
		pacman -S --noconfirm open-vm-tools gtkmm3 xf86-input-vmmouse xf86-video-vmware mesa
		systemctl enable vmtoolsd.service vmware-vmblock-fuse.service
	elif [ "$element" -eq 8 ]; then
		echo "UEFI wird installiert/konfiguriert"
		bootctl install
			mkdir -p /boot/loader/entries
			cat > /boot/loader/entries/arch-uefi.conf <<'EOF'
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=LABEL=ROOT rw lang=de init=/usr/lib/systemd/systemd locale=de_DE.UTF-8
EOF
			cat > /boot/loader/entries/arch-uefi-fallback.conf <<'EOF'
title   Arch Linux Fallback
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=LABEL=ROOT rw lang=de init=/usr/lib/systemd/systemd locale=de_DE.UTF-8
EOF
			cat > /boot/loader/loader.conf <<'EOF'
default arch-uefi
timeout 4
EOF
		bootctl update
	elif [ "$element" -eq 9 ]; then
		echo "Syslinux wird installiert/konfiguriert"
		pacman -S --noconfirm syslinux
		sed -i 's\APPEND root=/dev/sda3 rw\APPEND root=LABEL=ROOT rw' /boot/syslinux/syslinux.cfg
		syslinux-install_update -i -a -m
	fi
done

exit




