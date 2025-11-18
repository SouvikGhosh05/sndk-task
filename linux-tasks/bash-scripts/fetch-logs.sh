#!/bin/bash

################################################################################
# CloudWatch Logs Retrieval and Analysis Script
#
# Description:
#   Fetches and analyzes CloudWatch logs for ECS containers.
#   Supports filtering, searching, tailing, and error detection.
#
# Usage:
#   ./fetch-logs.sh [OPTIONS]
#
# Options:
#   -g, --log-group GROUP       CloudWatch log group name (required)
#   -s, --log-stream STREAM     Log stream name pattern (optional)
#   -f, --filter PATTERN        Filter pattern for log events
#   -t, --tail                  Tail logs in real-time (like tail -f)
#   -n, --lines NUM             Number of lines to fetch (default: 100)
#   -d, --duration MINUTES      Fetch logs from last N minutes (default: 60)
#   -e, --errors-only           Show only ERROR level logs
#   -o, --output FILE           Save output to file
#   -j, --json                  Output in JSON format
#   -h, --help                  Show this help message
#
# Examples:
#   # Fetch last 100 lines from all streams
#   ./fetch-logs.sh -g /ecs/sndk-prod-api
#
#   # Tail logs in real-time
#   ./fetch-logs.sh -g /ecs/sndk-prod-api --tail
#
#   # Show only errors from last 30 minutes
#   ./fetch-logs.sh -g /ecs/sndk-prod-api --errors-only -d 30
#
#   # Filter logs containing specific pattern
#   ./fetch-logs.sh -g /ecs/sndk-prod-api -f "POST /api" -n 200
#
#   # Save logs to file
#   ./fetch-logs.sh -g /ecs/sndk-prod-api -d 120 -o logs-output.txt
#
# Exit Codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - AWS CLI error
#   3 - No logs found
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Global variables
SCRIPT_NAME=$(basename "$0")
LOG_GROUP=""
LOG_STREAM_PATTERN=""
FILTER_PATTERN=""
TAIL_MODE=false
NUM_LINES=100
DURATION_MINUTES=60
ERRORS_ONLY=false
OUTPUT_FILE=""
JSON_OUTPUT=false
LAST_EVENT_TIME=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Functions
################################################################################

log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $*" >&2
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
    fi
}

log_warn() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $*" >&2
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

# Display usage
usage() {
    grep '^#' "$0" | grep -E '^# (Description:|Usage:|Options:|Examples:|Exit Codes:)' -A 50 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Validate prerequisites
validate_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 2
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 2
    fi

    if [ "$JSON_OUTPUT" = true ] && ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON output but not installed"
        exit 2
    fi
}

# Validate inputs
validate_inputs() {
    if [ -z "$LOG_GROUP" ]; then
        log_error "Log group is required. Use -g or --log-group option."
        exit 1
    fi

    if ! [[ "$NUM_LINES" =~ ^[0-9]+$ ]] || [ "$NUM_LINES" -lt 1 ]; then
        log_error "Number of lines must be a positive integer"
        exit 1
    fi

    if ! [[ "$DURATION_MINUTES" =~ ^[0-9]+$ ]] || [ "$DURATION_MINUTES" -lt 1 ]; then
        log_error "Duration must be a positive integer"
        exit 1
    fi

    # Check if log group exists
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query "logGroups[?logGroupName=='$LOG_GROUP']" --output text | grep -q .; then
        log_error "Log group '$LOG_GROUP' not found"
        exit 2
    fi
}

# Get log streams
get_log_streams() {
    log_info "Fetching log streams from $LOG_GROUP..."

    local query="logStreams[*].logStreamName"
    if [ -n "$LOG_STREAM_PATTERN" ]; then
        query="logStreams[?contains(logStreamName, '$LOG_STREAM_PATTERN')].logStreamName"
    fi

    local streams
    streams=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --max-items 50 \
        --query "$query" \
        --output text 2>&1) || {
        log_error "Failed to fetch log streams: $streams"
        exit 2
    }

    if [ -z "$streams" ] || [ "$streams" = "None" ]; then
        log_warn "No log streams found"
        return 1
    fi

    echo "$streams"
}

# Format log entry
format_log_entry() {
    local timestamp="$1"
    local message="$2"
    local stream="$3"

    # Convert timestamp from epoch milliseconds to readable format
    local readable_time
    if command -v date &> /dev/null; then
        readable_time=$(date -d "@$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")
    else
        readable_time="$timestamp"
    fi

    # Color code based on log level
    local color="$NC"
    if echo "$message" | grep -qiE "ERROR|FATAL|CRITICAL"; then
        color="$RED"
    elif echo "$message" | grep -qiE "WARN|WARNING"; then
        color="$YELLOW"
    elif echo "$message" | grep -qiE "INFO"; then
        color="$GREEN"
    elif echo "$message" | grep -qiE "DEBUG|TRACE"; then
        color="$CYAN"
    fi

    # Format output
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${MAGENTA}[${readable_time}]${NC} ${BLUE}[$(basename "$stream")]${NC} ${color}${message}${NC}"
    fi
}

# Fetch logs
fetch_logs() {
    local start_time=$(($(date +%s) * 1000 - DURATION_MINUTES * 60 * 1000))
    local end_time=$(($(date +%s) * 1000))

    # Build filter pattern
    local filter_opt=""
    if [ "$ERRORS_ONLY" = true ]; then
        filter_opt="--filter-pattern \"ERROR\""
    elif [ -n "$FILTER_PATTERN" ]; then
        filter_opt="--filter-pattern \"$FILTER_PATTERN\""
    fi

    # Get log streams
    local log_streams
    log_streams=$(get_log_streams) || {
        log_warn "No log streams available"
        return 1
    }

    # Fetch events
    log_info "Fetching logs from last $DURATION_MINUTES minutes..."

    local events
    if [ -n "$filter_opt" ]; then
        events=$(eval aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            "$filter_opt" \
            --max-items "$NUM_LINES" \
            --query 'events[*].[timestamp,message,logStreamName]' \
            --output text 2>&1) || {
            log_error "Failed to fetch logs: $events"
            return 2
        }
    else
        events=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --max-items "$NUM_LINES" \
            --query 'events[*].[timestamp,message,logStreamName]' \
            --output text 2>&1) || {
            log_error "Failed to fetch logs: $events"
            return 2
        }
    fi

    if [ -z "$events" ] || [ "$events" = "None" ]; then
        log_warn "No log events found"
        return 3
    fi

    # Process and display events
    local count=0
    while IFS=$'\t' read -r timestamp message stream; do
        if [ -n "$timestamp" ] && [ "$timestamp" != "None" ]; then
            format_log_entry "$timestamp" "$message" "$stream"
            LAST_EVENT_TIME=$timestamp
            count=$((count + 1))

            # Save to file if specified
            if [ -n "$OUTPUT_FILE" ]; then
                echo "[$(date -d "@$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")] [$stream] $message" >> "$OUTPUT_FILE"
            fi
        fi
    done <<< "$events"

    if [ $count -eq 0 ]; then
        log_warn "No matching log entries found"
        return 3
    fi

    log_success "Fetched $count log entries"
    return 0
}

# Tail logs (continuous monitoring)
tail_logs() {
    log_info "Tailing logs from $LOG_GROUP (press Ctrl+C to stop)..."

    # Initial fetch
    fetch_logs || true

    # Continuous polling
    local poll_interval=5
    while true; do
        sleep $poll_interval

        # Fetch new events since last timestamp
        local start_time=$LAST_EVENT_TIME
        if [ "$start_time" -eq 0 ]; then
            start_time=$(($(date +%s) * 1000 - 60 * 1000))  # Last minute
        fi

        local end_time=$(($(date +%s) * 1000))

        local filter_opt=""
        if [ "$ERRORS_ONLY" = true ]; then
            filter_opt="--filter-pattern \"ERROR\""
        elif [ -n "$FILTER_PATTERN" ]; then
            filter_opt="--filter-pattern \"$FILTER_PATTERN\""
        fi

        local events
        if [ -n "$filter_opt" ]; then
            events=$(eval aws logs filter-log-events \
                --log-group-name "$LOG_GROUP" \
                --start-time "$start_time" \
                --end-time "$end_time" \
                "$filter_opt" \
                --query 'events[*].[timestamp,message,logStreamName]' \
                --output text 2>/dev/null) || continue
        else
            events=$(aws logs filter-log-events \
                --log-group-name "$LOG_GROUP" \
                --start-time "$start_time" \
                --end-time "$end_time" \
                --query 'events[*].[timestamp,message,logStreamName]' \
                --output text 2>/dev/null) || continue
        fi

        if [ -n "$events" ] && [ "$events" != "None" ]; then
            while IFS=$'\t' read -r timestamp message stream; do
                if [ -n "$timestamp" ] && [ "$timestamp" != "None" ] && [ "$timestamp" -gt "$LAST_EVENT_TIME" ]; then
                    format_log_entry "$timestamp" "$message" "$stream"
                    LAST_EVENT_TIME=$timestamp

                    if [ -n "$OUTPUT_FILE" ]; then
                        echo "[$(date -d "@$((timestamp / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp")] [$stream] $message" >> "$OUTPUT_FILE"
                    fi
                fi
            done <<< "$events"
        fi
    done
}

# Analyze logs for common issues
analyze_logs() {
    log_info "Analyzing logs for common issues..."

    local temp_log="/tmp/cloudwatch-analysis-$$.txt"

    # Fetch logs to temp file
    local start_time=$(($(date +%s) * 1000 - DURATION_MINUTES * 60 * 1000))
    local events
    events=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$start_time" \
        --query 'events[*].message' \
        --output text 2>&1) || {
        log_error "Failed to fetch logs for analysis"
        return 2
    }

    echo "$events" > "$temp_log"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Log Analysis Summary${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Count by log level
    local error_count warn_count info_count
    error_count=$(grep -ciE "ERROR|FATAL|CRITICAL" "$temp_log" 2>/dev/null || echo "0")
    warn_count=$(grep -ciE "WARN|WARNING" "$temp_log" 2>/dev/null || echo "0")
    info_count=$(grep -ciE "INFO" "$temp_log" 2>/dev/null || echo "0")

    echo -e "${RED}Errors:${NC}    $error_count"
    echo -e "${YELLOW}Warnings:${NC}  $warn_count"
    echo -e "${GREEN}Info:${NC}      $info_count"

    # Top error patterns
    if [ "$error_count" -gt 0 ]; then
        echo ""
        echo -e "${CYAN}Top Error Patterns:${NC}"
        grep -iE "ERROR|FATAL|CRITICAL" "$temp_log" 2>/dev/null | \
            sed 's/^.*ERROR/ERROR/' | \
            sort | uniq -c | sort -rn | head -5 | \
            awk '{$1="  "$1; print}'
    fi

    # HTTP status codes
    echo ""
    echo -e "${CYAN}HTTP Status Codes:${NC}"
    grep -oE "HTTP/[0-9.]+ [0-9]{3}" "$temp_log" 2>/dev/null | \
        awk '{print $2}' | sort | uniq -c | sort -rn | head -10 | \
        awk '{
            color="'$GREEN'"
            if ($2 >= 400 && $2 < 500) color="'$YELLOW'"
            if ($2 >= 500) color="'$RED'"
            printf "  %s%-3s%s: %d\n", color, $2, "'$NC'", $1
        }' || echo "  No HTTP status codes found"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    rm -f "$temp_log"
}

################################################################################
# Main Script
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--log-group)
                LOG_GROUP="$2"
                shift 2
                ;;
            -s|--log-stream)
                LOG_STREAM_PATTERN="$2"
                shift 2
                ;;
            -f|--filter)
                FILTER_PATTERN="$2"
                shift 2
                ;;
            -t|--tail)
                TAIL_MODE=true
                shift
                ;;
            -n|--lines)
                NUM_LINES="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION_MINUTES="$2"
                shift 2
                ;;
            -e|--errors-only)
                ERRORS_ONLY=true
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    validate_prerequisites
    validate_inputs

    # Initialize output file
    if [ -n "$OUTPUT_FILE" ]; then
        : > "$OUTPUT_FILE"
        log_info "Saving output to: $OUTPUT_FILE"
    fi

    # Execute mode
    if [ "$TAIL_MODE" = true ]; then
        tail_logs
    else
        fetch_logs
        if [ "$JSON_OUTPUT" = false ]; then
            analyze_logs
        fi
    fi
}

# Handle Ctrl+C gracefully
trap 'echo ""; log_info "Stopped by user"; exit 0' INT TERM

main "$@"
