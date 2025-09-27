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

## Running the Production Server

To start the DenoKV server for remote access, you need to set up authentication:

### 1. Set Required Environment Variables

```bash
# Required: Access token for authentication (minimum 12 characters)
export DENO_KV_ACCESS_TOKEN="your-secure-access-token-here"

# Required: PostgreSQL connection URL
export DENO_KV_POSTGRES_URL="postgresql://user:password@host:port/database"

# Optional: Additional configuration
export DENO_KV_DATABASE_TYPE="postgres"  # Default: postgres
export DENO_KV_NUM_WORKERS="4"           # Default: 4
```

### 2. Start the Server

```bash
./start-denokv-server.sh
```

The server will start on `0.0.0.0:4512` and be accessible remotely.

### 3. Client Authentication

When connecting from a Deno application, use the access token in the Authorization header:

```typescript
const kv = await Deno.openKv("http://your-server:4512", {
  accessToken: "your-secure-access-token-here"
});
```

**Important Security Notes:**
- The access token must be at least 12 characters long
- Use a strong, randomly generated token for production
- Keep the access token secure and don't commit it to version control
- The server validates tokens using constant-time comparison for security

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