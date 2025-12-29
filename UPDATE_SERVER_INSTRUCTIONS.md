# Instructions to Update DenoKV Server

Based on your setup, here's the correct process to update the server:

## Current Setup

- **Binary location**: `/usr/local/bin/denokv`
- **Service**: systemd service at `/etc/systemd/system/denokv.service`
- **Service name**: `denokv.service`
- **Working directory**: `/var/lib/denokv`
- **User**: `denokv`

## Update Process

### Option 1: Using the Upgrade Script (Recommended)

If you're on the server and have the git repository:

```bash
# SSH into server
ssh -i ./rawkakani_db.pem rawkakani@102.37.137.29

# Navigate to project directory (if you have it there)
cd ~/codebender/nguvu/db  # or wherever your repo is

# Run upgrade script
./upgrade-denokv.sh

# After build completes, install and restart
sudo cp target/release/denokv /usr/local/bin/denokv
sudo systemctl restart denokv
sudo systemctl status denokv
```

### Option 2: Manual Update (If building locally)

If you're building on your local machine:

```bash
# 1. Build on local machine
cd ~/codebender/nguvu/db
cargo build --release

# 2. Copy binary to server
scp -i ./rawkakani_db.pem target/release/denokv rawkakani@102.37.137.29:/tmp/denokv

# 3. SSH into server and install
ssh -i ./rawkakani_db.pem rawkakani@102.37.137.29
sudo cp /tmp/denokv /usr/local/bin/denokv
sudo chmod +x /usr/local/bin/denokv
sudo chown root:root /usr/local/bin/denokv

# 4. Restart service
sudo systemctl restart denokv
sudo systemctl status denokv
```

### Option 3: Build Directly on Server

If you have the code on the server:

```bash
# SSH into server
ssh -i ./rawkakani_db.pem rawkakani@102.37.137.29

# Navigate to project directory
cd ~/codebender/nguvu/db  # or wherever your repo is

# Build
cargo build --release

# Install
sudo cp target/release/denokv /usr/local/bin/denokv
sudo chmod +x /usr/local/bin/denokv
sudo chown root:root /usr/local/bin/denokv

# Restart service
sudo systemctl restart denokv
sudo systemctl status denokv
```

## Verify Update

After restarting, verify it's working:

```bash
# Check service status
sudo systemctl status denokv

# Check logs
sudo journalctl -u denokv -n 50 --no-pager

# Verify binary version (if you have version info)
/usr/local/bin/denokv --version  # if supported
```

## Important Notes

1. **No downtime**: The systemd service will restart automatically, but there will be a brief moment when the service is down
2. **Database connection**: PostgreSQL should remain running - the service depends on it
3. **Access token**: The service uses the access token from the systemd service file - no need to change it
4. **Configuration**: All settings are in `/etc/systemd/system/denokv.service` - they persist across updates

## Quick One-Liner (If building on server)

```bash
cd ~/codebender/nguvu/db && cargo build --release && sudo cp target/release/denokv /usr/local/bin/denokv && sudo systemctl restart denokv && sudo systemctl status denokv
```
