#!/bin/bash
# Script to expand 512GB disk on Azure VM
# Run this on the database server: 102.37.137.29

set -e  # Exit on error

echo "=== Expanding 512GB Disk ==="
echo ""

# Step 1: Fix GPT table
echo "Step 1: Fixing GPT partition table..."
echo "Automatically answering prompts: Y, Y, w, Y"
echo ""

# Use echo to pipe answers to gdisk prompts
# Order: Y (fix secondary header), Y (proceed), w (write), Y (confirm)
echo -e "Y\nY\nw\nY" | sudo gdisk /dev/nvme0n1

echo ""
echo "Step 1 complete: GPT table fixed"
echo ""

# Step 2: Install growpart if needed
echo "Step 2: Installing growpart if needed..."
if ! command -v growpart &> /dev/null; then
    sudo dnf install -y cloud-utils-growpart || sudo yum install -y cloud-utils-growpart
    echo "growpart installed"
else
    echo "growpart already installed"
fi
echo ""

# Step 3: Extend partition 4
echo "Step 3: Extending partition 4 to use full disk..."
sudo growpart /dev/nvme0n1 4
echo "Partition extended"
echo ""

# Step 4: Resize physical volume
echo "Step 4: Resizing LVM physical volume..."
sudo pvresize /dev/nvme0n1p4
echo "Physical volume resized"
echo ""

# Step 5: Extend logical volume
echo "Step 5: Extending logical volume to use all available space..."
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
echo "Logical volume extended"
echo ""

# Step 6: Resize filesystem
echo "Step 6: Resizing filesystem..."
sudo xfs_growfs /
echo "Filesystem resized"
echo ""

# Step 7: Verify
echo "Step 7: Verifying disk space..."
echo ""
df -h
echo ""
echo "=== Disk expansion complete! ==="
echo ""
echo "Current disk status:"
sudo pvs
sudo vgs
sudo lvs


what does this mean [Pasted text #1 +45 lines]                                                                                                                          │
 └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  You're in the gdisk interactive prompt. The output means:
  • GPT partition table is present and valid
  • It's waiting for a command

  When you typed y, it showed the help menu because y isn't a command here.
  To fix the GPT table and write it, type w (write), then confirm with Y when prompted.

  Run this command instead (non-interactive):


  echo -e "w\ny" | sudo gdisk /dev/nvme0n1

  This sends:
  • w = write table to disk
  • y = confirm

  Or if gdisk asks about fixing the secondary header first, use:

  echo -e "y\ny\nw\ny" | sudo gdisk /dev/nvme0n1

  This sends:
  • y = fix secondary header placement
  • y = confirm fix
  • w = write table
  • y = confirm write

  After that, continue with the rest:

     1 │# Install growpart
     2 │sudo dnf install -y cloud-utils-growpart
     3 │
     4 │# Extend partition
     5 │sudo growpart /dev/nvme0n1 4
     6 │
     7 │# Resize physical volume
     8 │sudo pvresize /dev/nvme0n1p4
     9 │
    10 │# Extend logical volume
    11 │sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
    12 │
    13 │# Resize filesystem
    14 │sudo xfs_growfs /
    15 │
    16 │# Verify
    17 │df -h

  Try the echo -e command above; it should work non-interactively.

   Next Steps:

  1. Free up some space first (you were at 100%):


     1 │   sudo journalctl --vacuum-time=3d
     2 │   sudo dnf clean all

  2. Restart PostgreSQL to ensure it recognizes the new space:


     1 │   sudo systemctl restart postgresql
     2 │   sudo systemctl status postgresql

  3. Verify PostgreSQL is working:


     sudo -u postgres psql -c "SELECT version();"

  4. Check your DenoKV service:


     sudo systemctl status denokv

  PostgreSQL will now have plenty of space for:
  • Data files
  • WAL files
  • Log files
  • Temporary files

  The connection recovery code we added earlier will also help handle any future transient connection issues. You're all set.


