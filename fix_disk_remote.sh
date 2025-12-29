#!/bin/bash
# Script to fix 512GB disk not being recognized on remote server
# Run this on the database server: 102.37.137.29

echo "=== Step 1: Check Current Disk Status ==="
lsblk
echo ""
echo "=== Step 2: Check Partition Table ==="
sudo fdisk -l /dev/sda 2>/dev/null || sudo fdisk -l /dev/nvme0n1 2>/dev/null
echo ""
echo "=== Step 3: Check LVM Status ==="
sudo pvs
sudo vgs
sudo lvs
echo ""
echo "=== Step 4: Check Filesystem Usage ==="
df -h
echo ""
echo "=== If disk shows 512GB but partition is small, continue below ==="
echo ""
echo "Installing growpart if needed..."
sudo dnf install -y cloud-utils-growpart 2>/dev/null || sudo yum install -y cloud-utils-growpart 2>/dev/null
echo ""
echo "=== Identify the disk device ==="
echo "Run: lsblk to see which device (sda or nvme0n1)"
echo "Then run the appropriate commands below:"
echo ""
echo "For /dev/sda:"
echo "  sudo growpart /dev/sda 3"
echo "  sudo pvresize /dev/sda3"
echo "  sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot"
echo "  sudo xfs_growfs /"
echo ""
echo "For /dev/nvme0n1:"
echo "  sudo growpart /dev/nvme0n1 3"
echo "  sudo pvresize /dev/nvme0n1p3"
echo "  sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot"
echo "  sudo xfs_growfs /"
