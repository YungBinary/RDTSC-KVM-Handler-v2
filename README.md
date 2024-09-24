# Installation

This script is for Intel only! Not for use with AMD CPUs. All credits go to WCharacter, I simply created a bash script and updated the patch to work for Linux 6.8+.

Don't forget to disable rdtscp in your qemu xml config:

Add rdtscp=off to your qemu:arg, so it will look similar to this:

<qemu:arg value="-cpu"/>

<qemu:arg value="host,rdtscp=off,hv_time,kvm=off,hv_vendor_id=null,-hypervisor"/>

# Changing Timer

You can play with ticks if you want to:

* Open kernel-patch-6.8.0-45.patch in text editor
* Find handle_rdtsc function
* Change **u64 fake_diff =  diff / 16;**
* 16 is a divider of actual difference in timestamp, you can increase and decrease it

# Getting Started

Run the bash script and everything will be done for you:

* sudo bash kernel-patch-6.8.0-45.sh
