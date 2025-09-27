# Rocky Linux Setup for DenoKV PostgreSQL Testing

This document describes how to set up a Rocky Linux environment for testing DenoKV PostgreSQL integration.

## Prerequisites

- Rocky Linux 8 or 9
- Internet connection
- Non-root user with sudo privileges

## Quick Setup

Run the setup script:

```bash
chmod +x setup-rocky-linux.sh
./setup-rocky-linux.sh
```

## What the Setup Script Does

1. **Updates system packages** - Ensures all packages are up to date
2. **Installs development tools** - Installs essential development packages
3. **Installs PostgreSQL development libraries** - Required for PostgreSQL backend compilation
4. **Installs Docker and Docker Compose** - For running PostgreSQL test container
5. **Installs Rust** - Required for building the project
6. **Installs additional dependencies** - OpenSSL and pkg-config for Rust compilation
7. **Clones the repository** - Downloads the DenoKV source code
8. **Builds the project** - Compiles all components
9. **Creates test script** - Generates a script to run PostgreSQL integration tests

## Running Tests

After setup, you can run the PostgreSQL integration tests:

```bash
./test-postgres-integration.sh
```

## Manual Steps After Setup

1. **Log out and log back in** - This ensures Docker group membership takes effect
2. **Verify Docker access** - Run `docker ps` to confirm Docker is accessible
3. **Run tests** - Execute the test script to verify everything works

## Troubleshooting

### Docker Permission Issues
If you get permission denied errors with Docker:
```bash
sudo usermod -aG docker $USER
# Then log out and log back in
```

### Rust Not Found
If Rust commands are not found:
```bash
source ~/.cargo/env
```

### PostgreSQL Connection Issues
Make sure the PostgreSQL container is running:
```bash
docker-compose -f docker-compose.test.yml ps
```

## Project Structure

- `denokv/` - Main DenoKV project
- `postgres/` - PostgreSQL backend implementation
- `docker-compose.test.yml` - PostgreSQL test container configuration
- `test-postgres.sh` - Original test script
- `test-postgres-integration.sh` - Enhanced test script for Rocky Linux

## Environment Variables

The test script sets the following environment variable:
- `POSTGRES_URL=postgresql://postgres:password@localhost:5432/denokv_test`

## Cleanup

To stop and remove the PostgreSQL test container:
```bash
docker-compose -f docker-compose.test.yml down
```