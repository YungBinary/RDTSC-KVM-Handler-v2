#!/bin/bash
# Patch rdtsc for Linux kernel 7.0.0-34-generic
SRCVERSION="7.0.0-34.34~24.04.1"

base64 -d <<< "X19fX18uX19fLiAgICAgICAgICAgICAgICAgICBfX19fX19fX19fLl9fICAgICAgICAgICAgICAgICAgICAgICAgICAgIApcX18gIHwgICB8X18gX18gIF9fX18gICAgX19fX1xfX19fX18gICBcX198IF9fX18gX19fX18gX19fX19fXyBfX18uX18uCiAvICAgfCAgIHwgIHwgIFwvICAgIFwgIC8gX19fXHwgICAgfCAgXy8gIHwvICAgIFxcX18gIFxcXyAgX18gPCAgIHwgIHwKIFxfX19fICAgfCAgfCAgLyAgIHwgIFwvIC9fLyAgPiAgICB8ICAgXCAgfCAgIHwgIFwvIF9fIFx8ICB8IFwvXF9fXyAgfAogLyBfX19fX198X19fXy98X19ffCAgL1xfX18gIC98X19fX19fICAvX198X19ffCAgKF9fX18gIC9fX3wgICAvIF9fX198CiBcLyAgICAgICAgICAgICAgICAgXC8vX19fX18vICAgICAgICBcLyAgICAgICAgXC8gICAgIFwvICAgICAgIFwvICAgICAK"
echo " RDTSC KVM Handler - Kernel Builder"
echo " Target: 7.0.0-34-rdtsc"
echo "====================================================================="
echo ""

read -p "Delete pre-existing kernels with -rdtsc in the name? [y/n] " DELETEOLDKERNELS
read -p "Would you like to apply the ACS override patch for PCI devices? [y/n] " APPLYACS
read -p "Make the Grub bootloader menu visible? [y/n] " GRUBVISIBLE

# Detect Secure Boot and offer to sign the kernel with the MOK key DKMS already uses for modules
MOK_DIR="/var/lib/shim-signed/mok"
SIGNKERNEL="n"
if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
  echo "Secure Boot is ENABLED."
  read -p "Sign the kernel with your MOK key ($MOK_DIR) so it can boot with Secure Boot? [y/n] " SIGNKERNEL
  if [ "$SIGNKERNEL" = "y" ]; then
    if ! sudo test -f "$MOK_DIR/MOK.priv" || ! sudo test -f "$MOK_DIR/MOK.der"; then
      echo "ERROR: No MOK key found in $MOK_DIR. Create and enroll one first, then reboot and complete the enrollment:"
      echo "  sudo update-secureboot-policy --new-key"
      echo "  sudo update-secureboot-policy --enroll-key"
      exit 1
    fi
    if ! mokutil --test-key "$MOK_DIR/MOK.der" 2>/dev/null | grep -q "already enrolled"; then
      echo "ERROR: $MOK_DIR/MOK.der is not enrolled. Enroll it, then reboot and complete the enrollment:"
      echo "  sudo mokutil --import $MOK_DIR/MOK.der"
      exit 1
    fi
  else
    echo "WARNING: The kernel will be unsigned. It will fail to boot with 'bad shim signature'"
    echo "until you disable Secure Boot in your BIOS/UEFI settings."
    read -p "Press any key to continue..."
  fi
fi

echo ""
echo "====================================================================="
echo " Configuration Summary"
echo "====================================================================="
echo " Delete old -rdtsc kernels: $DELETEOLDKERNELS"
echo " ACS override patch:        $APPLYACS"
echo " Grub menu visible:         $GRUBVISIBLE"
echo " Sign kernel (Secure Boot): $SIGNKERNEL"
echo " Build cores:               $(nproc)"
echo "====================================================================="
echo ""
read -p "Proceed with build? [y/n] " PROCEED
if [ "$PROCEED" != "y" ]; then
  echo "Aborted."
  exit 0
fi

sudo apt update
sudo apt install dpkg-dev wget -y
if [ "$SIGNKERNEL" = "y" ]; then
  sudo apt install sbsigntool -y
fi

# nvidia-dkms and other DKMS packages only rebuild for the running and newest packaged kernel on upgrade,
# so a driver update while booted into another kernel would leave -rdtsc with a stale module
if ! grep -q '^autoinstall_all_kernels=' /etc/dkms/framework.conf; then
  echo "Configuring DKMS to rebuild modules for all installed kernels..."
  echo 'autoinstall_all_kernels="yes"' | sudo tee -a /etc/dkms/framework.conf > /dev/null
fi

if [ "$DELETEOLDKERNELS" = "y" ]; then
  echo "Removing existing kernels that contain -rdtsc in the name..."
  sudo shred -u /boot/*-rdtsc || true
fi

echo "Removing any folders matching ./linux-hwe-7.0-7.0.0"
sudo rm -rf ./linux-hwe-7.0-7.0.0
echo "Downloading source: linux-hwe-7.0 $SRCVERSION..."
LPURL="https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/linux-hwe-7.0/$SRCVERSION"
for f in linux-hwe-7.0_7.0.0.orig.tar.gz "linux-hwe-7.0_$SRCVERSION.diff.gz" "linux-hwe-7.0_$SRCVERSION.dsc"; do
  wget -nv -O "$f" "$LPURL/$f"
done
dpkg-source -x "linux-hwe-7.0_$SRCVERSION.dsc"
echo "Changing permissions on downloaded source directory..."
sudo chown -R $USER:$USER linux-hwe-7.0-7.0.0
sudo chmod -R 777 linux-hwe-7.0-7.0.0
cd ./linux-hwe-7.0-7.0.0
if ! head -1 debian.hwe-7.0/changelog | grep -qF "($SRCVERSION)"; then
  echo "ERROR: Downloaded source is not $SRCVERSION:"
  head -1 debian.hwe-7.0/changelog
  exit 1
fi
patch -p1 < ../kernel-patch-7.0.0-34.patch

if [ "$APPLYACS" = "y" ]; then
  patch -p1 < ../acso-7.0.0-34.patch
fi

# Use all available cores for make
CORES=$(nproc)

# Fix for error: ISO C90 forbids mixed declarations and code
sed -i 's/KBUILD_CFLAGS += -Wdeclaration-after-statement/#KBUILD_CFLAGS += -Wdeclaration-after-statement/' Makefile

# Fix the kernel version
sed -i 's/^SUBLEVEL = .*/SUBLEVEL = 0/' Makefile
sed -i 's/^EXTRAVERSION =.*/EXTRAVERSION = -34/' Makefile

# Build and install the kernel
sudo apt install git libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libdw-dev libdebuginfod-dev autoconf llvm build-essential -y
cp ../.config .
make olddefconfig
KRELEASE=$(make -s kernelrelease)
if [ "$KRELEASE" != "7.0.0-34-rdtsc" ]; then
  echo "ERROR: Kernel release is '$KRELEASE', expected '7.0.0-34-rdtsc'"
  exit 1
fi
make -j$CORES
echo "Installing kernel modules..."
sudo make modules_install -j$CORES

# Install kernel headers before the kernel so DKMS (run by installkernel) builds against them,
# and they keep working after the source tree is cleaned up
HDRSDIR="/usr/src/linux-headers-7.0.0-34-rdtsc"
echo "Installing kernel headers to $HDRSDIR..."
sudo rm -rf "$HDRSDIR"
sudo make run-command KBUILD_RUN_COMMAND="$PWD/scripts/package/install-extmod-build $HDRSDIR"
sudo cp .config "$HDRSDIR/"
sudo rm -f /lib/modules/7.0.0-34-rdtsc/build
sudo ln -s "$HDRSDIR" /lib/modules/7.0.0-34-rdtsc/build

KIMAGE=arch/x86/boot/bzImage
if [ "$SIGNKERNEL" = "y" ]; then
  echo "Signing kernel with MOK key..."
  sudo openssl x509 -inform der -in "$MOK_DIR/MOK.der" -out MOK.pem
  sudo sbsign --key "$MOK_DIR/MOK.priv" --cert MOK.pem --output arch/x86/boot/bzImage.signed "$KIMAGE"
  sudo rm -f MOK.pem
  KIMAGE=arch/x86/boot/bzImage.signed
fi

echo "Installing kernel..."
sudo installkernel 7.0.0-34-rdtsc "$KIMAGE" System.map /boot

echo "Cleaning up..."
cd ..
sudo rm -rf ./linux-hwe-*

if [ "$GRUBVISIBLE" = "y" ]; then
  sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/#GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=-1/' /etc/default/grub
  sudo update-grub
else
  echo 'Boot into Grub bootloader menu by holding Shift (BIOS) or Esc (UEFI).'
fi

if [ "$APPLYACS" = "y" ]; then
  if grep -R "pcie_acs_override" "/etc/default/grub"
    then
      echo "Boot parameter pcie_acs_override already in /etc/default/grub... skipping"
    else
      echo "Adding intel_iommu=on pcie_acs_override=downstream to GRUB boot options..."
      sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_iommu=on pcie_acs_override=downstream"/' /etc/default/grub
      sudo update-grub
  fi
fi

echo 'All finished. In the Grub menu, go to [Advanced Options for Ubuntu] and select 7.0.0-34-rdtsc.'
