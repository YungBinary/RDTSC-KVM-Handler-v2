#!/bin/bash
# Patch rdtsc for Linux kernel 7.0.0-30-generic

base64 -d <<< "X19fX18uX19fLiAgICAgICAgICAgICAgICAgICBfX19fX19fX19fLl9fICAgICAgICAgICAgICAgICAgICAgICAgICAgIApcX18gIHwgICB8X18gX18gIF9fX18gICAgX19fX1xfX19fX18gICBcX198IF9fX18gX19fX18gX19fX19fXyBfX18uX18uCiAvICAgfCAgIHwgIHwgIFwvICAgIFwgIC8gX19fXHwgICAgfCAgXy8gIHwvICAgIFxcX18gIFxcXyAgX18gPCAgIHwgIHwKIFxfX19fICAgfCAgfCAgLyAgIHwgIFwvIC9fLyAgPiAgICB8ICAgXCAgfCAgIHwgIFwvIF9fIFx8ICB8IFwvXF9fXyAgfAogLyBfX19fX198X19fXy98X19ffCAgL1xfX18gIC98X19fX19fICAvX198X19ffCAgKF9fX18gIC9fX3wgICAvIF9fX198CiBcLyAgICAgICAgICAgICAgICAgXC8vX19fX18vICAgICAgICBcLyAgICAgICAgXC8gICAgIFwvICAgICAgIFwvICAgICAK"
echo " RDTSC KVM Handler - Kernel Builder"
echo " Target: 7.0.0-30-rdtsc"
echo "====================================================================="
echo ""

echo "Make sure to enable Ubuntu Software -> Source code in Software & Updates first!"
read -p "Press any key to continue..."
echo ""

read -p "Delete pre-existing kernels with -rdtsc in the name? [y/n] " DELETEOLDKERNELS
read -p "Would you like to apply the ACS override patch for PCI devices? [y/n] " APPLYACS
read -p "Make the Grub bootloader menu visible? [y/n] " GRUBVISIBLE

# Detect Secure Boot
if command -v mokutil &>/dev/null; then
  if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
    echo "WARNING: Secure Boot is ENABLED."
    echo "Custom kernels will fail to boot with 'bad shim signature' unless"
    echo "disable Secure Boot in BIOS settings."
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
echo " Build cores:               $(nproc)"
echo "====================================================================="
echo ""
read -p "Proceed with build? [y/n] " PROCEED
if [ "$PROCEED" != "y" ]; then
  echo "Aborted."
  exit 0
fi

sudo apt update
sudo apt install dpkg-dev -y

if [ "$DELETEOLDKERNELS" = "y" ]; then
  echo "Removing existing kernels that contain -rdtsc in the name..."
  sudo shred -u /boot/*-rdtsc
fi

echo "Removing any folders matching ./linux-hwe-7.0-7.0.0"
sudo rm -rf ./linux-hwe-7.0-7.0.0
echo "Downloading source: linux-image-unsigned-7.0.0-30-generic..."
sudo apt source linux-image-unsigned-7.0.0-30-generic
echo "Changing permissions on downloaded source directory..."
sudo chown -R $USER:$USER linux-hwe-7.0-7.0.0
sudo chmod -R 777 linux-hwe-7.0-7.0.0
cd ./linux-hwe-7.0-7.0.0
patch -p1 < ../kernel-patch-7.0.0-30.patch

if [ "$APPLYACS" = "y" ]; then
  patch -p1 < ../acso-7.0.0-30.patch
fi

# Use all available cores for make
CORES=$(nproc)

# Fix for error: ISO C90 forbids mixed declarations and code
sed -i 's/KBUILD_CFLAGS += -Wdeclaration-after-statement/#KBUILD_CFLAGS += -Wdeclaration-after-statement/' Makefile

# Fix the kernel version
sed -i 's/SUBLEVEL = 12/SUBLEVEL = 0/' Makefile
sed -i 's/EXTRAVERSION =/EXTRAVERSION = -30/' Makefile

# Build and install the kernel
sudo apt install git libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libdw-dev libdebuginfod-dev autoconf llvm build-essential -y
cp ../.config .
make olddefconfig
make -j$CORES
echo "Installing kernel modules..."
sudo make modules_install -j$CORES
echo "Installing kernel headers..."
sudo make headers_install -j$CORES
echo "Installing kernel..."
sudo make install
# Sign the kernel if the user opted for MOK signing
if [ "$SIGNKERNEL" = "y" ]; then
  echo "Signing kernel with MOK key..."
  sudo sbsign --key "$MOK_DIR/MOK.priv" --cert "$MOK_DIR/MOK.der" \
    /boot/vmlinuz-7.0.0-30-rdtsc --output /boot/vmlinuz-7.0.0-30-rdtsc
  echo "Kernel signed successfully."
fi

echo "Generating initrd.img..."
sudo update-initramfs -c -k 7.0.0-30-rdtsc
echo "Updating GRUB bootloader..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Install kernel headers so DKMS and out-of-tree module builds work
HDRSDIR="/usr/src/linux-headers-7.0.0-30-rdtsc"
echo "Installing kernel headers to $HDRSDIR..."
sudo mkdir -p "$HDRSDIR"
sudo cp .config Module.symvers Makefile "$HDRSDIR/"
sudo cp -a include scripts arch/x86/include "$HDRSDIR/"
sudo mkdir -p "$HDRSDIR/arch/x86"
sudo cp -a arch/x86/Makefile "$HDRSDIR/arch/x86/"
sudo cp -a tools/objtool/objtool "$HDRSDIR/tools/objtool/objtool" 2>/dev/null || true
# Fix the build symlink in /lib/modules so module builds find headers
sudo rm -f /lib/modules/7.0.0-30-rdtsc/build
sudo ln -s "$HDRSDIR" /lib/modules/7.0.0-30-rdtsc/build

echo "Cleaning up..."
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

echo 'All finished. In the Grub menu, go to [Advanced Options for Ubuntu] and select 7.0.0-30-rdtsc.'
