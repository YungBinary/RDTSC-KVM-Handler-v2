#!/bin/bash
# Patch rdtsc for Linux kernel 6.8.0-45-generic

read -p "Make sure to enable Ubuntu Software -> Source code in Software & Updates! Press enter to continue..."
echo "Removing any existing kernel related files that contain -rdtsc in the name..."
sudo shred -u /boot/*-rdtsc
echo "Removing any folders matching ./linux-hwe-6.8-6.8.0"
sudo rm -rf ./linux-hwe-6.8-6.8.0
echo "Downloading source: linux-image-unsigned-6.8.0-45-generic..."
sudo apt source linux-image-unsigned-6.8.0-45-generic
echo "Changing permissions on downloaded source directory..."
sudo chown -R $USER:$USER linux-hwe-6.8-6.8.0
sudo chmod -R 777 linux-hwe-6.8-6.8.0
cd ./linux-hwe-6.8-6.8.0
patch -p1 < ../kernel-patch-6.8.0-45.patch

# Get core count - 2 for faster make, e.g. if you have 8 cores, 6 will 
# be used by make
CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)
CORES=$(($CORES - 2))

# Fix for error: ISO C90 forbids mixed declarations and code
sed -i 's/KBUILD_CFLAGS += -Wdeclaration-after-statement/#KBUILD_CFLAGS += -Wdeclaration-after-statement/' Makefile

# Fix the kernel version
sed -i 's/SUBLEVEL = 12/SUBLEVEL = 0/' Makefile
sed -i 's/EXTRAVERSION =/EXTRAVERSION = -45/' Makefile

# Build and install the kernel
sudo apt install git libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm build-essential -y
cp ../.config .
make -j$CORES bzImage
make -j$CORES modules
echo "Installing kernel modules..."
sudo make modules_install -j$CORES
echo "Installing kernel..."
sudo make install
echo "Generating initrd.img..."
sudo update-initramfs -c -k 6.8.0-45-rdtsc
echo "Updating GRUB bootloader..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

read -p "Make the Grub bootloader menu visible? [y/n] " GRUBVISIBLE
if [ "$GRUBVISIBLE" = "y" ]; then
  sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/#GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=-1/' /etc/default/grub
  sudo update-grub
else
  echo 'Boot into Grub bootloader menu by holding Shift (BIOS) or Esc (UEFI).'
fi

echo 'All finished. In the Grub menu, go to [Advanced Options for Ubuntu] and select 6.8.0-45-rdtsc.'

