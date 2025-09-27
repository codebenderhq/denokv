#!/bin/bash

# Service management script for DenoKV on Rocky Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

case "${1:-help}" in
    start)
        print_status "Starting all services..."
        
        # Start PostgreSQL service
        print_status "Starting PostgreSQL service..."
        sudo systemctl start postgresql
        
        # Wait for PostgreSQL
        until sudo -u postgres pg_isready; do
            echo "Waiting for PostgreSQL..."
            sleep 2
        done
        print_success "PostgreSQL service started"
        
        # Start DenoKV server
        print_status "Starting DenoKV server..."
        source ~/.cargo/env
        source .env 2>/dev/null || true
        
        if pgrep -f "denokv.*serve" > /dev/null; then
            print_warning "DenoKV server is already running"
        else
            nohup cargo run --release -- serve --addr 0.0.0.0:4512 > denokv.log 2>&1 &
            sleep 2
            if pgrep -f "denokv.*serve" > /dev/null; then
                print_success "DenoKV server started"
            else
                print_error "Failed to start DenoKV server"
            fi
        fi
        ;;
        
    stop)
        print_status "Stopping DenoKV server..."
        
        # Stop DenoKV server only
        if pgrep -f "denokv.*serve" > /dev/null; then
            pkill -f "denokv.*serve"
            print_success "DenoKV server stopped"
        else
            print_warning "DenoKV server was not running"
        fi
        
        print_status "PostgreSQL service remains running (persistent)"
        ;;
        
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
        
    stop-postgres)
        print_status "Stopping PostgreSQL service..."
        sudo systemctl stop postgresql
        print_success "PostgreSQL service stopped"
        print_warning "Note: DenoKV server will not work without PostgreSQL"
        ;;
        
    start-postgres)
        print_status "Starting PostgreSQL service..."
        sudo systemctl start postgresql
        until sudo -u postgres pg_isready; do
            echo "Waiting for PostgreSQL..."
            sleep 2
        done
        print_success "PostgreSQL service started"
        ;;
        
    status)
        print_status "Service Status:"
        echo ""
        
        # Check PostgreSQL service
        if systemctl is-active --quiet postgresql; then
            print_success "PostgreSQL Service: Running"
        else
            print_warning "PostgreSQL Service: Stopped"
        fi
        
        # Check DenoKV server
        if pgrep -f "denokv.*serve" > /dev/null; then
            print_success "DenoKV Server: Running (PID: $(pgrep -f 'denokv.*serve'))"
        else
            print_warning "DenoKV Server: Stopped"
        fi
        
        # Check port 4512
        if netstat -tlnp 2>/dev/null | grep -q ":4512 "; then
            print_success "Port 4512: Open"
        else
            print_warning "Port 4512: Closed"
        fi
        ;;
        
    logs)
        if [ -f "denokv.log" ]; then
            tail -f denokv.log
        else
            print_warning "No log file found"
        fi
        ;;
        
    *)
        echo "DenoKV Service Manager"
        echo "Usage: $0 {start|stop|restart|status|logs|start-postgres|stop-postgres}"
        echo ""
        echo "Commands:"
        echo "  start         - Start DenoKV server (PostgreSQL must be running)"
        echo "  stop          - Stop DenoKV server only (PostgreSQL stays running)"
        echo "  restart       - Restart DenoKV server only"
        echo "  status        - Show service status"
        echo "  logs          - Show DenoKV server logs"
        echo "  start-postgres - Start PostgreSQL service"
        echo "  stop-postgres  - Stop PostgreSQL service (use with caution)"
        echo ""
        echo "Note: PostgreSQL runs as a persistent system service"
        echo "      DenoKV server can be started/stopped independently"
        ;;
esac