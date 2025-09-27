#!/bin/bash

# Test script for PostgreSQL backend

set -e

echo "Starting PostgreSQL test environment..."

# Start PostgreSQL
docker-compose -f docker-compose.test.yml up -d postgres

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker-compose -f docker-compose.test.yml exec postgres pg_isready -U postgres; do
  echo "PostgreSQL is not ready yet..."
  sleep 2
done

echo "PostgreSQL is ready!"

# Set environment variable for tests
export POSTGRES_URL="postgresql://postgres:password@localhost:5432/denokv_test"

# Run the tests
echo "Running PostgreSQL tests..."
cargo test --package denokv_postgres test_postgres

# Clean up
echo "Cleaning up..."
docker-compose -f docker-compose.test.yml down

echo "Tests completed!"