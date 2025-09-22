#!/bin/bash

# Keylime Attestation Health Monitor
# 
# This script provides automated monitoring and recovery for Keylime attestation
# infrastructure running in Docker containers. It monitors agent health, container
# status, and attestation progress, automatically restarting components when issues
# are detected.
#
# Usage: ./final_monitor.sh {monitor|status|restart|restart-all|test}
#
# Key Features:
# - Continuous health monitoring with graduated recovery
# - Automatic agent and full system restart capabilities  
# - Comprehensive logging and status reporting
# - Container lifecycle management
#
# Version: 1.0

# Configuration
AGENT_UUID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"  # Target agent UUID for monitoring
LOGFILE="/home/shubhgupta/keylime/monitor.log"       # Centralized log file location
SWTPM_ATTESTATION_LIMIT=75                           # Proactive restart before swtpm limit (80)

# Logging function with timestamp
log() {
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local message="$timestamp: $*"
    
    # Always output to console
    echo "$message"
    
    # Try to write to log file, but don't fail if we can't
    if ! echo "$message" >> "$LOGFILE" 2>/dev/null; then
        # If we can't write to the log file, try to fix permissions or use a fallback
        if [[ ! -w "$LOGFILE" ]] && [[ -f "$LOGFILE" ]]; then
            # Try to fix ownership if the file exists but we can't write to it
            sudo chown "$(whoami):$(whoami)" "$LOGFILE" 2>/dev/null || true
            echo "$message" >> "$LOGFILE" 2>/dev/null || true
        elif [[ ! -f "$LOGFILE" ]]; then
            # Create the file if it doesn't exist
            touch "$LOGFILE" 2>/dev/null || true
            echo "$message" >> "$LOGFILE" 2>/dev/null || true
        fi
    fi
}

# Get agent operational status from verifier
# Returns the current attestation state (e.g., "Get Quote", "Registered", "Invalid Quote")
get_status() {
    # Query verifier for agent status and extract the operational_state from the last JSON response
    # This represents the actual attestation state, not just registration status
    local output=$(docker exec keylime-verifier keylime_tenant -c status -u "${AGENT_UUID}" 2>&1)
    echo "$output" | grep '"operational_state"' | tail -1 | \
        sed 's/.*"operational_state": "\([^"]*\)".*/\1/'
}

# Get current attestation count
# Returns the number of successful attestations performed by the agent
get_count() {
    local output=$(docker exec keylime-verifier keylime_tenant -c status -u "${AGENT_UUID}" 2>&1)
    echo "$output" | grep '"attestation_count"' | tail -1 | \
        sed 's/.*"attestation_count": \([0-9]*\).*/\1/'
}

# Check how many Keylime containers are currently running
# Expected: 3 containers (agent, verifier, registrar)
check_containers() {
    local running=$(docker ps --format "{{.Names}}" | grep -c keylime || echo 0)
    echo "$running"
}

# Restart agent container and re-register with verifier
# This is the lighter-weight recovery option that preserves other containers
restart_agent() {
    log "Restarting agent and re-registering..."
    
    # Clear any TPM dictionary attack lockout first
    log "Clearing TPM lockout state..."
    docker exec keylime-agent bash -c "export TPM2TOOLS_TCTI=mssim:host=localhost,port=2321 && tpm2_dictionarylockout -c" >/dev/null 2>&1 || true
    sleep 2
    
    # Clean slate: remove agent from verifier's records
    docker exec keylime-verifier keylime_tenant -c delete -u "${AGENT_UUID}" >/dev/null 2>&1 || true
    sleep 3   # Brief pause between delete and add operations
    
    # Restart the agent container to clear any internal state issues
    docker restart keylime-agent
    sleep 15  # Allow container to fully initialize
    
    # Clear lockout again after restart
    docker exec keylime-agent bash -c "export TPM2TOOLS_TCTI=mssim:host=localhost,port=2321 && tpm2_dictionarylockout -c" >/dev/null 2>&1 || true
    sleep 2
    
    # Re-register agent with verifier to establish fresh attestation relationship
    local registration_attempts=0
    local max_attempts=3
    
    while [[ $registration_attempts -lt $max_attempts ]]; do
        registration_attempts=$((registration_attempts + 1))
        log "Registration attempt $registration_attempts/$max_attempts"
        
        if docker exec keylime-verifier keylime_tenant -c add -t keylime-agent -u "${AGENT_UUID}" >/dev/null 2>&1; then
            log "Agent restart successful"
            return 0
        else
            log "Registration attempt $registration_attempts failed"
            if [[ $registration_attempts -lt $max_attempts ]]; then
                sleep 5
            fi
        fi
    done
    
    log "Agent restart failed after $max_attempts attempts"
    return 1
}

# Perform full system restart (all containers)
# This is the heavy-weight recovery option for persistent issues
full_restart() {
    log "Performing full system restart..."
    
    # Stop all containers and clean up networks/volumes
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose down --remove-orphans >/dev/null 2>&1 || true
    else
        docker compose down --remove-orphans >/dev/null 2>&1 || true
    fi
    
    sleep 5  # Allow cleanup to complete
    
    # Start entire stack from clean state
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d >/dev/null 2>&1
    else
        docker compose up -d >/dev/null 2>&1
    fi
    
    sleep 30  # Allow all services to initialize properly
    
    # Register agent with fresh verifier instance
    docker exec keylime-verifier keylime_tenant -c add -t keylime-agent -u "${AGENT_UUID}" >/dev/null 2>&1 || true
    log "Full restart completed"
}

# Reset TPM state to work around swtpm limitations
# This clears the TPM state directory and restarts containers
# reset_tpm_state() {
#     log "Resetting TPM state to work around swtpm limitations..."
    
#     # Stop all containers
#     if command -v docker-compose >/dev/null 2>&1; then
#         docker-compose down --remove-orphans >/dev/null 2>&1 || true
#     else
#         docker compose down --remove-orphans >/dev/null 2>&1 || true
#     fi
    
#     # Clear TPM state directory (this resets the TPM emulator)
#     if [[ -d "/home/shubhgupta/tpm_state" ]]; then
#         log "Clearing TPM state directory..."
#         rm -rf /home/shubhgupta/tmp_state/*
#     fi
    
#     sleep 5
    
#     # Start containers with fresh TPM state
#     if command -v docker-compose >/dev/null 2>&1; then
#         docker-compose up -d >/dev/null 2>&1
#     else
#         docker compose up -d >/dev/null 2>&1
#     fi
    
#     sleep 30  # Allow initialization
    
#     # Clear any TPM dictionary attack lockout before registration
#     log "Clearing TPM lockout state..."
#     docker exec keylime-agent bash -c "export TPM2TOOLS_TCTI=mssim:host=localhost,port=2321 && tpm2_dictionarylockout -c" >/dev/null 2>&1 || true
#     sleep 3
    
#     # Register agent with enhanced error handling
#     log "Registering agent with fresh TPM state..."
#     local registration_attempts=0
#     local max_attempts=3
    
#     while [[ $registration_attempts -lt $max_attempts ]]; do
#         registration_attempts=$((registration_attempts + 1))
#         log "Registration attempt $registration_attempts/$max_attempts"
        
#         if docker exec keylime-verifier keylime_tenant -c add -t keylime-agent -u "${AGENT_UUID}" >/dev/null 2>&1; then
#             log "Agent registration successful"
#             break
#         else
#             log "Registration attempt $registration_attempts failed"
#             if [[ $registration_attempts -lt $max_attempts ]]; then
#                 sleep 10
#             fi
#         fi
#     done
    
#     sleep 5
#     log "TPM state reset completed"
#     show_status
# }

# Show status
show_status() {
    local containers=$(check_containers)
    local status=$(get_status)
    local count=$(get_count)
    
    echo "=== Keylime Monitoring Status ==="
    echo "Timestamp: $(date)"
    echo "Containers running: $containers/3"
    echo "Agent status: $status"
    echo "Attestation count: $count"
    echo
    
    # Health assessment
    if [[ "$containers" -eq 3 ]]; then
        echo "✅ All containers running"
    else
        echo "❌ Missing containers"
        return 1
    fi
    
    case "$status" in
        "Get Quote"|"Start"|"Tenant Start")
            if [[ "$count" -gt 0 ]]; then
                echo "✅ Agent is healthy and attesting"
                return 0
            else
                echo "⚠️  Agent active but no attestations"
                return 1
            fi
            ;;
        "Registered")
            if [[ "$count" -gt 0 ]]; then
                echo "✅ Agent registered and attesting"
                return 0
            else
                echo "⚠️  Agent registered but no attestations yet"
                return 1
            fi
            ;;
        "Invalid Quote"|"Failed")
            echo "❌ Agent in error state"
            return 2
            ;;
        *)
            echo "⚠️  Agent in unknown state: $status"
            return 1
            ;;
    esac
}

# Monitor function
monitor() {
    log "Starting Keylime attestation monitoring..."
    local failure_count=0
    local last_attestation_count=0
    local stale_rounds=0
    
    while true; do
        # Check container status
        local containers=$(check_containers)
        if [[ "$containers" -lt 3 ]]; then
            log "Only $containers/3 containers running - performing full restart"
            full_restart
            failure_count=0
            sleep 60
            continue
        fi
        
        # Get current state
        local status=$(get_status)
        local count=$(get_count)
        
        log "Status: $status, Attestations: $count"
        
        # # Proactive swtpm restart before hitting the ~80 attestation limit
        # if [[ "$count" -ge "$SWTPM_ATTESTATION_LIMIT" ]]; then
        #     log "⚠️  Approaching swtpm attestation limit ($count >= $SWTPM_ATTESTATION_LIMIT) - performing proactive TPM reset"
        #     reset_tpm_state
        #     failure_count=0
        #     last_attestation_count=0
        #     sleep 60
        #     continue
        # fi
        
        # Evaluate health
        local health_ok=0
        case "$status" in
            "Get Quote"|"Start"|"Tenant Start")
                if [[ "$count" -gt "$last_attestation_count" ]]; then
                    health_ok=1
                    failure_count=0
                    stale_rounds=0
                    last_attestation_count="$count"
                    log "✅ Healthy - attestations progressing ($count total)"
                else
                    stale_rounds=$((stale_rounds + 1))
                    if [[ $stale_rounds -ge 3 ]]; then
                        log "⚠️  Attestations appear stale"
                        health_ok=0
                        stale_rounds=0
                    else
                        health_ok=1  # Give it a few more chances
                    fi
                fi
                ;;
            "Registered")
                if [[ "$count" -gt 0 ]]; then
                    health_ok=1
                    failure_count=0
                    log "✅ Registered and has attestations"
                else
                    log "⚠️  Registered but no attestations yet"
                    health_ok=0
                fi
                ;;
            *)
                log "❌ Unhealthy state: $status"
                health_ok=0
                ;;
        esac
        
        # Take corrective action if needed
        if [[ $health_ok -eq 0 ]]; then
            failure_count=$((failure_count + 1))
            log "Health issue detected (failure #$failure_count)"
            
            if [[ $failure_count -le 2 ]]; then
                log "Attempting agent restart..."
                restart_agent
            else
                log "Multiple failures - performing full restart..."
                full_restart
                failure_count=0
            fi
        fi
        
        # Wait before next check
        sleep 2
    done
}

# Command line interface - Main script entry point
case "${1:-monitor}" in
    "monitor")
        # Start continuous monitoring mode (default action)
        monitor
        ;;
    "status") 
        # Display current health status with visual indicators
        show_status
        ;;
    "restart")
        # Restart agent container and re-register (lightweight recovery)
        restart_agent
        ;;
    "restart-all")
        # Full system restart - all containers (heavy recovery)
        full_restart
    #     ;;
    # "reset-tpm")
    #     # Reset TPM state to work around swtpm limitations
    #     reset_tpm_state
        ;;
    "test")
        # Test core monitoring functions for debugging
        echo "Testing functions..."
        echo "Containers: $(check_containers)"
        echo "Status: $(get_status)"
        echo "Count: $(get_count)"
        ;;
    *)
        # Display usage information
        echo "Keylime Attestation Health Monitor"
        echo "Usage: $0 {monitor|status|restart|restart-all|reset-tpm|test}"
        echo ""
        echo "Commands:"
        echo "  monitor      - Start continuous monitoring (default)"
        echo "  status       - Show current health status"
        echo "  restart      - Restart agent container only"
        echo "  restart-all  - Full system restart (all containers)"
        echo "  reset-tpm    - Reset TPM state (fixes swtpm limitations)"
        echo "  test         - Test core monitoring functions"
        echo ""
        echo "Examples:"
        echo "  $0              # Start monitoring"
        echo "  $0 status       # Quick health check"
        echo "  $0 restart      # Fix agent issues"
        echo "  $0 reset-tpm    # Fix swtpm 80-attestation limit"
        echo "  $0 restart-all  # Nuclear option for persistent problems"
        ;;
esac
