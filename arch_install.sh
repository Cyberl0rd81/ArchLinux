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
echo "3 = Samba-Server"
echo "4 = Docker incl. Dockge"
echo "5 = Qemu incl. Cockpit"
echo "7 = VmWare Tools"
echo "8 = Bootmanager UEFI"
echo "###################################"
read -r -p "Bitte gib eine Mehrfachauswahl mit , getrennt an z.B. 1, 4, 5: " selected_packages
if [[ -z $selected_packages ]]; then
	printf 'Mindestens Option 8 (UEFI-Bootmanager) muss ausgewählt werden.\n' >&2
	exit 1
fi
IFS=',' read -r -a pakete_array <<< "$selected_packages"
declare -A selected_options=()
for index in "${!pakete_array[@]}"; do
	element=${pakete_array[index]//[[:space:]]/}
	if [[ ! $element =~ ^(1|2|3|4|5|7|8)$ ]]; then
		printf 'Ungültige Paketauswahl: %s\n' "${pakete_array[index]}" >&2
		exit 1
	fi
	if [[ ${selected_options[$element]+selected} ]]; then
		printf 'Option %s wurde mehrfach ausgewählt.\n' "$element" >&2
		exit 1
	fi
	selected_options[$element]=selected
	pakete_array[index]=$element
done
if [[ ! ${selected_options[8]+selected} ]]; then
	printf 'Option 8 (UEFI-Bootmanager) ist erforderlich.\n' >&2
	exit 1
fi

### Hostname definiere
printf '%s\n' "$host_name" > /etc/hostname


### Deutsches Layout verwenden te
printf 'LANG=de_DE.UTF-8\nLC_COLLATE=C\n' > /etc/locale.conf
echo KEYMAP=de-latin1 > /etc/vconsole.conf
echo FONT=lat9w-16 >> /etc/vconsole.conf

### Zeitzone definieren
		ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime


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
		echo "Samba wird installiert"
		pacman -S --noconfirm samba
		install -d -o "$username" -g users -m 2770 /srv/samba/shared
		cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server role = standalone server
   security = user

[shared]
   path = /srv/samba/shared
   browseable = yes
   read only = no
   valid users = $username
   create mask = 0660
   directory mask = 0770
EOF
		testparm -s
		echo "Bitte ein Samba-Passwort für $username festlegen"
		smbpasswd -a "$username"
		systemctl enable smb.service
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
		pacman -S --noconfirm qemu-full cockpit cockpit-machines cockpit-podman cockpit-storaged cockpit-packagekit networkmanager udisks2 pcp
		systemctl enable cockpit.socket
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
options root=LABEL=ROOT rw
EOF
		cat > /boot/loader/entries/arch-uefi-fallback.conf <<'EOF'
title   Arch Linux Fallback
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=LABEL=ROOT rw
EOF
		cat > /boot/loader/loader.conf <<'EOF'
default arch-uefi
timeout 4
EOF
		bootctl update
	fi
done

exit




