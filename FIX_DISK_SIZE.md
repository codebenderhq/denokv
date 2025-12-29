# Fix: 512GB Disk Not Recognized - Azure VM

## Problem
- Azure shows 512GB disk
- System shows only 8.8GB (100% full)
- The partition/LVM hasn't been extended to use the full disk

## Step 1: Check Current Disk Status

Run these commands to see what's happening:

```bash
# Check actual disk size (should show 512GB)
lsblk

# Check partition table
sudo fdisk -l /dev/sda  # or /dev/nvme0n1 depending on your setup

# Check LVM status
sudo pvs
sudo vgs
sudo lvs

# Check current filesystem
df -h
```

## Step 2: Identify the Disk Device

For Azure VMs, it's usually:
- **Standard VMs**: `/dev/sda` or `/dev/sdb`
- **NVMe VMs**: `/dev/nvme0n1` or `/dev/nvme1n1`

Check with:
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

## Step 3: Extend the Partition (If Needed)

### For Standard Disk (/dev/sda):

```bash
# Check current partition
sudo fdisk -l /dev/sda

# Use growpart to extend partition (usually partition 3 for LVM)
sudo growpart /dev/sda 3

# If growpart not available, install it:
sudo dnf install cloud-utils-growpart
```

### For NVMe Disk (/dev/nvme0n1):

```bash
# Check current partition
sudo fdisk -l /dev/nvme0n1

# Extend partition (usually partition 3)
sudo growpart /dev/nvme0n1 3
```

## Step 4: Resize Physical Volume

After extending the partition, resize the LVM physical volume:

```bash
# For standard disk
sudo pvresize /dev/sda3

# OR for NVMe
sudo pvresize /dev/nvme0n1p3
```

## Step 5: Extend Logical Volume

```bash
# Extend to use all available space
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
```

## Step 6: Resize Filesystem

```bash
# For xfs (most common on Rocky Linux)
sudo xfs_growfs /

# OR for ext4
sudo resize2fs /dev/mapper/rocky-lvroot
```

## Step 7: Verify

```bash
# Should now show ~512GB available
df -h

# Verify LVM
sudo vgs
sudo lvs
```

## Complete Command Sequence

```bash
# 1. Check disk
lsblk
sudo fdisk -l /dev/sda  # or /dev/nvme0n1

# 2. Install growpart if needed
sudo dnf install -y cloud-utils-growpart

# 3. Extend partition (adjust device and partition number)
sudo growpart /dev/sda 3  # or /dev/nvme0n1 3

# 4. Resize physical volume
sudo pvresize /dev/sda3  # or /dev/nvme0n1p3

# 5. Extend logical volume
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot

# 6. Resize filesystem
sudo xfs_growfs /  # or resize2fs for ext4

# 7. Verify
df -h
```

## Troubleshooting

### If growpart fails:
```bash
# Check partition number
sudo fdisk -l /dev/sda | grep -E "^/dev"

# Manually extend using fdisk (advanced - be careful!)
# This requires deleting and recreating the partition
# Only do this if you know what you're doing
```

### If pvresize fails:
```bash
# Check if physical volume exists
sudo pvs

# Check partition type
sudo blkid /dev/sda3
```

### If you see "device is busy":
```bash
# Unmount if possible (usually can't for root)
# Or reboot after extending partition, then continue with pvresize
```

## After Fixing: Free Up Space

Even after expanding, you should still clean up:

```bash
# Clean logs
sudo journalctl --vacuum-time=7d

# Clean package cache
sudo dnf clean all

# Restart PostgreSQL
sudo systemctl restart postgresql
```
