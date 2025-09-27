# Agent Onboarding Guide for DenoKV

## Project Overview

**DenoKV** is a self-hosted backend for [Deno KV](https://deno.com/kv), providing a JavaScript-first key-value database with ACID transactions and multiple consistency levels. This repository contains both the Rust server implementation and Node.js client libraries.

### Key Components

1. **`denokv`** - Main Rust server binary (HTTP server implementing KV Connect protocol)
2. **`denokv_proto`** - Shared protocol definitions and Database trait
3. **`denokv_sqlite`** - SQLite-backed database implementation
4. **`denokv_remote`** - Remote client implementation for KV Connect protocol
5. **`denokv_timemachine`** - Backup and time-travel functionality
6. **`npm/`** - Node.js client library with NAPI bindings

## Architecture Deep Dive

### Core Protocol: KV Connect

The project implements the **KV Connect protocol** (defined in `proto/kv-connect.md`), which consists of:

1. **Metadata Exchange Protocol** (JSON-based)
   - Authentication and protocol version negotiation
   - Database metadata retrieval
   - Endpoint discovery

2. **Data Path Protocol** (Protobuf-based)
   - Snapshot reads (`/snapshot_read`)
   - Atomic writes (`/atomic_write`) 
   - Watch operations (`/watch`)

### Database Abstraction

The `Database` trait in `proto/interface.rs` defines the core operations:
- `snapshot_read()` - Read operations with consistency levels
- `atomic_write()` - ACID transactions with checks/mutations/enqueues
- `watch()` - Real-time key change notifications

### SQLite Backend (`sqlite/`)

- **Multi-threaded architecture** with worker threads
- **Connection pooling** and retry logic
- **Queue message handling** with dead letter queues
- **Sum operations** for numeric values with clamping
- **Versionstamp-based** consistency and ordering

### Remote Client (`remote/`)

- **HTTP client** for KV Connect protocol
- **Authentication handling** with token management
- **Streaming support** for watch operations
- **Retry logic** with exponential backoff

## Development Setup

### Prerequisites

```bash
# Rust toolchain (1.83+)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Node.js 18+ for npm package development
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18

# Protobuf compiler
# Ubuntu/Debian:
sudo apt-get install protobuf-compiler
# macOS:
brew install protobuf
```

### Building the Project

```bash
# Build all Rust components
cargo build

# Build release binary
cargo build --release

# Run tests
cargo test

# Build Docker image
docker build -t denokv .
```

### Running the Server

```bash
# Basic server
cargo run -- --sqlite-path ./data.db serve --access-token my-secret-token

# With Docker
docker run -p 4512:4512 -v ./data:/data ghcr.io/denoland/denokv \
  --sqlite-path /data/denokv.sqlite serve --access-token my-token
```

### Testing

```bash
# Run integration tests (starts server, tests client)
cargo test --package denokv

# Run specific test
cargo test --package denokv basics

# Test npm package
cd npm/napi
npm test
```

## Key Files to Understand

### Core Server (`denokv/main.rs`)
- **Entry point** with CLI argument parsing
- **HTTP server setup** using Axum framework
- **Authentication middleware** with Bearer tokens
- **Endpoint handlers** for KV Connect protocol
- **S3 sync functionality** for replica mode

### Protocol Definitions (`proto/`)
- **`interface.rs`** - Core Database trait and types
- **`protobuf.rs`** - Generated protobuf message types
- **`convert.rs`** - Conversion between protobuf and internal types
- **`limits.rs`** - Size and count limits for operations

### SQLite Implementation (`sqlite/`)
- **`lib.rs`** - Main Sqlite struct implementing Database trait
- **`backend.rs`** - Low-level SQLite operations and schema
- **`sum_operand.rs`** - Sum operation logic with type checking

### Node.js Client (`npm/`)
- **`src/napi_based.ts`** - NAPI-based SQLite implementation
- **`src/remote.ts`** - HTTP client for remote databases
- **`src/in_memory.ts`** - Pure JS in-memory implementation
- **`src/kv_types.ts`** - TypeScript type definitions

## Common Development Tasks

### Adding New Database Operations

1. **Define in protocol** (`proto/interface.rs`)
2. **Implement in SQLite** (`sqlite/backend.rs`)
3. **Add protobuf messages** (`proto/schema/datapath.proto`)
4. **Update server handlers** (`denokv/main.rs`)
5. **Add client support** (`npm/src/`)

### Debugging Tips

```bash
# Enable debug logging
RUST_LOG=debug cargo run -- --sqlite-path ./test.db serve --access-token test

# Test with curl
curl -X POST http://localhost:4512/ \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"supportedVersions": [2, 3]}'

# Inspect SQLite database
sqlite3 ./test.db ".schema"
sqlite3 ./test.db "SELECT * FROM data LIMIT 10;"
```

### Performance Considerations

- **Batch operations** - Use atomic writes for multiple operations
- **Connection pooling** - SQLite backend uses worker threads
- **Consistency levels** - Use eventual consistency for better performance
- **Key design** - Prefix keys for efficient range queries

## Testing Strategy

### Integration Tests (`denokv/tests/integration.rs`)
- **Start real server** process
- **Test full protocol** flow
- **Verify ACID properties**
- **Test error conditions**

### Unit Tests
- **Protocol conversion** (`proto/`)
- **SQLite operations** (`sqlite/`)
- **Client implementations** (`npm/`)

### Manual Testing
```bash
# Start server
cargo run -- --sqlite-path ./test.db serve --access-token test

# Test with Deno
deno eval "
const kv = await Deno.openKv('http://localhost:4512');
await kv.set(['test'], 'hello');
console.log(await kv.get(['test']));
"
```

## Common Issues & Solutions

### Build Issues
- **Missing protobuf compiler** - Install protobuf-compiler package
- **NAPI build failures** - Ensure Node.js 18+ and proper toolchain
- **SQLite linking** - May need sqlite3-dev package

### Runtime Issues
- **Permission denied** - Check SQLite file permissions
- **Port conflicts** - Use different port with `--addr`
- **Token authentication** - Ensure consistent token usage

### Development Issues
- **Protobuf changes** - Run `cargo build` to regenerate
- **Type mismatches** - Check `proto/convert.rs` for conversion logic
- **Test failures** - Ensure server is properly started in tests

## Contributing Guidelines

### Code Style
- **Rust**: Follow standard rustfmt (run `cargo fmt`)
- **TypeScript**: Use Prettier (run `npm run format`)
- **Commits**: Use conventional commit messages

### Pull Request Process
1. **Write tests** for new functionality
2. **Update documentation** if needed
3. **Run full test suite** (`cargo test && cd npm/napi && npm test`)
4. **Check formatting** (`cargo fmt && npm run format`)

### Areas for Contribution
- **Performance optimizations** in SQLite backend
- **Additional client libraries** (Python, Go, etc.)
- **Monitoring and metrics** integration
- **Backup and recovery** improvements
- **Documentation** and examples

## Key Concepts to Master

### Versionstamps
- **10-byte identifiers** for ordering operations
- **Monotonic ordering** across all operations
- **Consistency guarantees** for reads

### Atomic Operations
- **Checks** - Conditional operations based on current values
- **Mutations** - Set, delete, sum operations
- **Enqueues** - Queue message operations
- **All-or-nothing** transaction semantics

### Consistency Levels
- **Strong** - Linearizable reads (default)
- **Eventual** - Eventually consistent reads (faster)

### Queue Operations
- **Message enqueuing** with deadlines
- **Dead letter queues** for failed messages
- **Backoff intervals** for retry logic

## Useful Commands Reference

```bash
# Development
cargo run -- --help                    # Show CLI options
cargo test --package denokv -- --nocapture  # Run tests with output
cargo clippy                           # Lint Rust code

# Server management
cargo run -- --sqlite-path ./db serve --access-token token --addr 0.0.0.0:4512
cargo run -- pitr list                 # List recoverable points
cargo run -- pitr checkout <version>   # Checkout specific version

# NPM package
cd npm/napi
npm run build                          # Build native bindings
npm run test                           # Run tests
npm run format                         # Format code

# Docker
docker build -t denokv .
docker run -p 4512:4512 -v ./data:/data denokv --sqlite-path /data/db serve --access-token token
```

## Learning Resources

- **Deno KV Documentation**: https://deno.com/kv
- **KV Connect Protocol**: `proto/kv-connect.md`
- **Rust Async Book**: https://rust-lang.github.io/async-book/
- **Axum Framework**: https://docs.rs/axum/
- **SQLite Documentation**: https://www.sqlite.org/docs.html
- **NAPI-RS**: https://napi.rs/

## Notes for Future Self

- **Always test with real server** - Unit tests aren't enough
- **Understand the protocol** - KV Connect is the foundation
- **SQLite is single-writer** - Design around this constraint
- **Versionstamps are critical** - They provide ordering guarantees
- **Authentication is simple** - Just Bearer tokens
- **Error handling matters** - Users depend on clear error messages
- **Performance is important** - This is a database, not just a toy

Remember: This is a production database system. Changes affect real users and their data. Test thoroughly, understand the implications, and always consider backward compatibility.