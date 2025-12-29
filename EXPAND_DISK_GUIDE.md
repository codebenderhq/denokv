# Guide: Expand Disk and Free Space

## Important: Expanding Disk Won't Free Space Automatically

**Expanding the disk adds more space, but doesn't clean up existing files.** You need to:
1. **First**: Free up space immediately (so PostgreSQL can work)
2. **Then**: Expand the disk (for long-term capacity)

## Step 1: Free Up Space IMMEDIATELY (Do This First!)

### Quick Cleanup Commands

```bash
# 1. Clean system journal logs (usually the biggest culprit)
sudo journalctl --vacuum-time=3d  # Keep only 3 days of logs

# 2. Clean package cache
sudo dnf clean all

# 3. Remove old kernels (keep only current + 1)
sudo dnf remove --oldinstallonly --setopt installonly_limit=2

# 4. Check PostgreSQL logs size
sudo du -sh /var/lib/pgsql/data/log/* 2>/dev/null
# If large, clean old PostgreSQL logs:
sudo find /var/lib/pgsql/data/log -name "*.log" -mtime +7 -delete

# 5. Check what's using space
sudo du -h --max-depth=1 / | sort -hr | head -15
```

### After Cleanup, Restart PostgreSQL

```bash
sudo systemctl restart postgresql
sudo systemctl status postgresql
```

## Step 2: Check Current Disk Setup

```bash
# Check current disk usage
df -h

# Check LVM setup (you're using LVM based on rocky-lvroot)
sudo pvs    # Physical volumes
sudo vgs    # Volume groups  
sudo lvs    # Logical volumes

# Check if there's unallocated space in the volume group
sudo vgdisplay rocky
```

## Step 3: Expand the Disk

### Option A: If You Have Unallocated Space in Volume Group

If `vgdisplay` shows free space:

```bash
# Extend the logical volume to use all free space
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot

# Resize the filesystem (check which one you have first)
# For ext4:
sudo resize2fs /dev/mapper/rocky-lvroot

# OR for xfs (more common on Rocky Linux):
sudo xfs_growfs /

# Verify
df -h
```

### Option B: If You Need to Add a New Disk/Partition

1. **Add new disk to the server** (via cloud provider console or physical disk)

2. **Create physical volume:**
   ```bash
   # Find the new disk
   lsblk
   # Example: /dev/sdb or /dev/nvme1n1
   
   # Create physical volume
   sudo pvcreate /dev/sdb  # Replace with your disk
   ```

3. **Extend volume group:**
   ```bash
   sudo vgextend rocky /dev/sdb
   ```

4. **Extend logical volume:**
   ```bash
   sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
   ```

5. **Resize filesystem:**
   ```bash
   # For xfs:
   sudo xfs_growfs /
   
   # OR for ext4:
   sudo resize2fs /dev/mapper/rocky-lvroot
   ```

### Option C: Expand Existing Disk (Cloud Provider)

If you're on AWS/Azure/GCP, you can expand the disk in the cloud console:

1. **Stop the instance** (or take snapshot first)
2. **Increase disk size** in cloud provider console
3. **Start the instance**
4. **Extend the partition:**
   ```bash
   # Check current partition
   sudo fdisk -l /dev/nvme0n1
   
   # Use growpart (if available)
   sudo growpart /dev/nvme0n1 3  # Adjust partition number
   
   # Then extend LVM
   sudo pvresize /dev/nvme0n1p3
   sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
   sudo xfs_growfs /  # or resize2fs
   ```

## Step 4: Verify and Monitor

```bash
# Check disk space
df -h

# Check PostgreSQL is working
sudo -u postgres psql -c "SELECT version();"

# Check DenoKV service
sudo systemctl status denokv
```

## Prevention: Set Up Automatic Cleanup

```bash
# Create log rotation for PostgreSQL
sudo vi /etc/logrotate.d/postgresql-custom
```

Add:
```
/var/lib/pgsql/data/log/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 postgres postgres
    sharedscripts
}
```

## Quick Reference Commands

```bash
# Check everything
df -h && echo "---" && sudo vgs && echo "---" && sudo lvs

# Free space immediately
sudo journalctl --vacuum-time=3d && sudo dnf clean all

# Expand if you have free space in VG
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot && sudo xfs_growfs /
```
