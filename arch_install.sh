#!/bin/bash


### Grundvariablen abfragen
read -p "Bitte gib den hier den Hostnamen ein: " hostname
read -p "Bitte gib deinen Benutzernamen ein: " User
echo "Wähl aus welche Pakete du installiert haben möchtest"
echo "1 = Xfce incl. Loginmanager und Tools"
echo "2 = SSH"
echo "3 = SMB/NFS"
echo "4 = Docker incl. Portainer"
echo "5 = Qemu incl. Cockpit"
echo "6 = Pentesting Tools"
echo "###################################"
read -p "Bitte gib eine Mehrfachauswahl mit , getrennt an z.B. 1, 4, 5: " Pakete
IFS=',' read -r -a pakete_array <<< "$Pakete"

### Hostname definiere
echo $hostname > /etc/hostname

### Deutsches Layout verwenden
echo LANG=de_DE.UTF-8 > /etc/locale.conf
echo LC_COLLATE= C >> /etc/locale.conf
echo KEYMAP=de-latin1 > /etc/vconsole.conf
echo FONT=lat9w-16 >> /etc/vconsole.conf

### Zeitzone definieren
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime


echo de_DE.UTF-8 UTF-8 >> /etc/locale.gen
echo de_DE ISO-8859-1 >> /etc/locale.gen
echo de_DE@euro ISO-8859-15 >> /etc/locale.gen
echo en_US.UTF-8 UTF-8 >> /etc/locale.gen
locale-gen

### Initramfs erzeugen
mkinitcpio -p linux

### Root Passwort setzen
echo "Root Passwort definieren"
passwd

### User anlegen
useradd -m -g users -s /bin/bash $User
echo "Bitte gib dein Userpasswort ein"
passwd $User

### User zu Gruppen hinzufügen
gpasswd -a $User wheel audio video

### Basispakete installieren
pacman -S --noconfirm acpid ntp dbus avahi sudo connman cronie

### Basispakte Dienste aktivieren
systemctl enable cronie acpid ntpd avahi-daemon connman.service

### Hardwareuhr aktualisieren
ntpd -gq
hwclock -w

for element in "${pakete_array[@]}"
do
	if [ "$element" -eq 1 ]; then
		echo "Xfce wird installiert"
		pacman -S --noconfirm xorg-server xorg-apps xorg-xdm xfce4 xfc4-goodies terminator
		systemctl enable xdm-archlinux.service
	elif [ "$element" -eq 2 ]; then
		echo "SSH wird installiert"
		pacman -S --noconfirm openssh
	elif [ "$element" -eq 3 ]; then
		echo "SMB/NFS wird installiert"
	elif [ "$element" -eq 4 ]; then
		echo "Docker incl. Portainer wird installiert"
	elif [ "$element" -eq 5 ]; then
		echo "Qemu incl. Cockpit wird installiert"
	elif [ "$element" -eq 6 ]; then
		echo "Pentesting Tools werden installiert"
	fi
done













