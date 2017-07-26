#!/bin/sh
#  piconsole - The Raspberry Pi retro videogame console project
#  Copyright (C) 2017  Michael Andrew Nixon
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  Contact: zipplet@zipplet.co.uk
#
#  Install custom piconsole kernel on Raspberry Pi
#

# Kernel files
KERNEL_OLD='../kernels/piconsole-kernel-4.11.11.tar.gz'
KERNELNAME_OLD='piconsole-4.11.11.img'
KERNELFILENAME_OLD='kernel.img'
KERNEL_NEW='../kernels/piconsole-kernel-4.11.11-v7.tar.gz'
KERNELNAME_NEW='piconsole-4.11.11-v7.img'
KERNELFILENAME_NEW='kernel7.img'

# Colours
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'

# Reset to black
NC='\033[0m'

# Fail if the Pi model is unknown
fail_unknownmodel() {
  echo "${RED}Sorry, your Raspberry Pi model is currently unsupported / unknown.${NC}"
  echo "${RED}Please submit the output of ${CYAN}cat /proc/cpuinfo${RED} along with more information about your Rasperry Pi${NC}"
  echo "${RED}to the author, by opening a GitHub issue. Please include high resolution images of the top and bottom of the board.${NC}"
  exit 1
}

# Report Pi model
pireport() {
  if [ "$PIBOARD" = "" ]; then
    fail_unknownmodel
  fi
  echo "Your Pi: ${CYAN}${PIBOARD}${NC}"
  echo " - Model: ${CYAN}${PIMODEL}${NC}"
  echo " - Sub model: ${CYAN}${PISUBMODEL}${NC}"
  echo " - RAM: ${CYAN}${PIRAM}MB${NC}"
}

# We must run as root
if [ "$(id -u)" != "0" ]; then
   echo "${RED}Please run this program as root (or use sudo)${NC}" 1>&2
   exit 1
fi

clear
echo "${BLUE}------------------------------------------------------------${NC}"
echo "${CYAN}piconsole - The Raspberry Pi retro videogame console project${NC}"
echo "${CYAN}Copyright (C) 2017 Michael Andrew Nixon${NC}"
echo "${BLUE}------------------------------------------------------------${NC}"

echo "${GREEN}Determining Pi model...${NC}"
PIBOARDREVISION=$(grep "Revision" /proc/cpuinfo | cut -f2 | cut -c3-)

# This table comes from http://elinux.org/RPi_HardwareHistory#Board_Revision_History
case "$PIBOARDREVISION" in
  "0002")
    PIBOARD="2012 Q1 - PCB v1.0 - Pi 1 Model B [256MB] (original)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="256"
    ;;
  "0003")
    PIBOARD="2012 Q3 - PCB v1.0 - Pi 1 Model B (ECN0001) [256MB] (Fuses mod and D14 removed)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="256"
    ;;
  "0004")
    PIBOARD="2012 Q3 - PCB v2.0 - Pi 1 Model B [256MB] (Manufactured by Sony)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="256"
    ;;
  "0005")
    PIBOARD="2012 Q4 - PCB v2.0 - Pi 1 Model B [256MB] (Manufactured by Qisda)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="256"
    ;;
  "0006")
    PIBOARD="2012 Q4 - PCB v2.0 - Pi 1 Model B [256MB] (Manufactured by Egoman)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="256"
    ;;
  "0007")
    PIBOARD="2013 Q1 - PCB v2.0 - Pi 1 Model A [256MB] (Manufactured by Egoman)"
    PIMODEL="1"
    PISUBMODEL="A"
    PIRAM="256"
    ;;
  "0008")
    PIBOARD="2013 Q1 - PCB v2.0 - Pi 1 Model A [256MB] (Manufactured by Sony)"
    PIMODEL="1"
    PISUBMODEL="A"
    PIRAM="256"
    ;;
  "0009")
    PIBOARD="2013 Q1 - PCB v2.0 - Pi 1 Model A [256MB] (Manufactured by Qisda)"
    PIMODEL="1"
    PISUBMODEL="A"
    PIRAM="256"
    ;;
  "000d")
    PIBOARD="2012 Q4 - PCB v2.0 - Pi 1 Model A [512MB] (Manufactured by Egoman)"
    PIMODEL="1"
    PISUBMODEL="A"
    PIRAM="512"
    ;;
  "000e")
    PIBOARD="2012 Q4 - PCB v2.0 - Pi 1 Model B [512MB] (Manufactured by Sony)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="512"
    ;;
  "000f")
    PIBOARD="2012 Q4 - PCB v2.0 - Pi 1 Model B [512MB] (Manufactured by Qisda)"
    PIMODEL="1"
    PISUBMODEL="B"
    PIRAM="512"
    ;;
  "0010")
    PIBOARD="2014 Q3 - PCB v1.0 - Pi 1 Model B+ [512MB] (Manufactured by Sony)"
    PIMODEL="1"
    PISUBMODEL="B+"
    PIRAM="512"
    ;;
  "0011")
    PIBOARD="2014 Q2 - PCB v1.0 - Compute Module [512MB] (Manufactured by Sony)"
    PIMODEL="Compute"
    # For now pretend compute modules are equivalent to a B+
    PISUBMODEL="B+"
    PIRAM="512"
    ;;
  "0012")
    PIBOARD="2014 Q4 - PCB v1.1 - Pi 1 Model A+ [256MB] (Manufactured by Sony)"
    PIMODEL="1"
    PISUBMODEL="A+"
    PIRAM="256"
    ;;
  "0013")
    PIBOARD="2015 Q1 - PCB v1.2 - Pi 1 Model B+ [512MB] (Unknown manufacturer)"
    PIMODEL="1"
    PISUBMODEL="B+"
    PIRAM="512"
    ;;
  "0014")
    PIBOARD="2014 Q2 - PCB v1.0 - Compute Module [512MB] (Manufactured by Embest)"
    PIMODEL="1"
    # For now pretend compute modules are equivalent to a B+
    PISUBMODEL="B+"
    PIRAM="512"
    ;;
  "0015")
    PIBOARD="Unknown manufacturing date - PCB v1.1 - Pi 1 Model A+ [256/512MB] (Unknown RAM and unknown manufacturer)"
    PIMODEL="1"
    PISUBMODEL="A+"
    # Err on the side of caution, although we could add a check here
    PIRAM="256"
    ;;
  "a01040")
    PIBOARD="Unknown manufacturing date - PCB v1.0 - Pi 2 Model B [1GB] (Unknown manufacturer)"
    PIMODEL="2"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  "a01041")
    PIBOARD="2015 Q1 - PCB v1.1 - Pi 2 Model B [1GB] (Manufactured by Sony)"
    PIMODEL="2"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  "a21041")
    PIBOARD="2015 Q1 - PCB v1.1 - Pi 2 Model B [1GB] (Manufactured by Embest)"
    PIMODEL="2"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  "a22042")
    PIBOARD="2016 Q3 - PCB v1.2 - Pi 2 Model B (BCM2837) [1GB] (Manufactured by Embest)"
    PIMODEL="2"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  "900092")
    PIBOARD="2015 Q4 - PCB v1.2 - Pi Zero [512MB] (Manufactured by Sony)"
    PIMODEL="0"
    PISUBMODEL="0"
    PIRAM="512"
    ;;
  "900093")
    PIBOARD="2016 Q2 - PCB v1.3 - Pi Zero [512MB] (Manufactured by Sony)"
    PIMODEL="0"
    PISUBMODEL="0"
    PIRAM="512"
    ;;
  "920093")
    PIBOARD="2016 Q4?- PCB v1.3 - Pi Zero [512MB] (Manufactured by Embest)"
    PIMODEL="0"
    PISUBMODEL="0"
    PIRAM="512"
    ;;
  "a02082")
    PIBOARD="2016 Q1 - PCB v1.2 - Pi 3 Model B [1GB] (Manufactured by Sony)"
    PIMODEL="3"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  "a22082")
    PIBOARD="2016 Q1 - PCB v1.2 - Pi 3 Model B [1GB] (Manufactured by Embest)"
    PIMODEL="3"
    PISUBMODEL="B"
    PIRAM="1024"
    ;;
  *)
    PIBOARD=""
    PIMODEL=""
    PISUBMODEL=""
    PIRAM=""
    ;;
esac
echo "${GREEN}Board revision is ${CYAN}${PIBOARDREVISION}${NC}"
pireport
echo

case "$PIMODEL" in
  "0")
    KERNELFILE=$KERNEL_OLD
    KERNELNAME=$KERNELNAME_OLD
    KERNELFILENAME=$KERNELFILENAME_OLD
    echo "${GREEN}Debug: Using old kernel.${NC}"
    ;;
  "1")
    KERNELFILE=$KERNEL_OLD
    KERNELNAME=$KERNELNAME_OLD
    KERNELFILENAME=$KERNELFILENAME_OLD
    echo "${GREEN}Debug: Using old kernel.${NC}"
    ;;
  "2")
    KERNELFILE=$KERNEL_NEW
    KERNELNAME=$KERNELNAME_NEW
    KERNELFILENAME=$KERNELFILENAME_NEW
    echo "${GREEN}Debug: Using new kernel.${NC}"
    ;;
  "3")
    KERNELFILE=$KERNEL_NEW
    KERNELNAME=$KERNELNAME_NEW
    KERNELFILENAME=$KERNELFILENAME_NEW
    echo "${GREEN}Debug: Using new kernel.${NC}"
    ;;
  *)
    fail_unknownmodel
    ;;
esac

echo "${GREEN}Before proceeding, please confirm the following:${NC}"
echo "${YELLOW}1) You have not already installed a custom kernel.${NC}"
echo "${YELLOW}2) You have taken a backup of your SD card.${NC}"
echo "${YELLOW}3) You accept all responsibility if this does not work.${NC}"
echo "${YELLOW}4) You are not trying to upgrade a custom kernel that this tool has already installed (not yet supported).${NC}"
echo "${YELLOW}5) You do not have a directory called ${RED}temp${YELLOW} in the current working directory.${NC}"
echo
echo
echo "Debug: ${CYAN}Kernel to install: ${RED}${KERNELFILE} ${CYAN}imagename ${YELLOW}(${KERNELNAME})${NC}"
echo "Debug: ${CYAN}Kernel original filename is: ${RED}${KERNELFILENAME}${NC}"
echo
echo
read -p "Have you read, confirmed and do you understand all of the above? (y/n) :" -r ANSWER
echo
if [ ! "$ANSWER" = "y" ]; then
  echo "Aborting."
  exit 1
fi

if [ ! -f "${KERNELFILE}" ]; then
  echo "${RED}Cannot find the kernel file ${KERNELFILE} - Run this script from its own directory!${NC}"
  exit 1
fi

echo "${GREEN}Unpacking kernel files to a temporary location...${NC}"
mkdir temp
cd temp
tar -zxf $KERNELFILE
cd ..
if [ ! -d "temp/boot" ]; then
  echo "${RED}Could not find the unpacked boot files for the new kernel; unpack failed?${NC}"
  echo "Cleaning up..."
  rm -rf temp
  exit 1
fi
if [ ! -d "temp/lib" ]; then
  echo "${RED}Could not find the unpacked lib files for the new kernel; unpack failed?${NC}"
  echo "Cleaning up..."
  rm -rf temp
  exit 1
fi
if [ ! -f "temp/boot/$KERNELFILENAME" ]; then
  echo "${RED}Could not find the unpacked kernel; unpack failed?${NC}"
  echo "Cleaning up..."
  rm -rf temp
  exit 1
fi

echo "${GREEN}Copying the new kernel modules into place...${NC}"
cp -R temp/lib/* /lib/

echo "${GREEN}Copying the new boot files into place...${NC}"
cp temp/boot/*.dtb /boot/
cp temp/boot/overlays/* /boot/overlays/

echo "${GREEN}Copying the new kernel into /boot...${NC}"
cp temp/boot/$KERNELFILENAME /boot/$KERNALNAME

echo "${GREEN}Patching /boot/config.txt to boot the new kernel...${NC}"
echo "kernel=${KERNALNAME}" >> /boot/config.txt

echo "${GREEN}All done. Please reboot to use the new kernel.${NC}"

exit 0
