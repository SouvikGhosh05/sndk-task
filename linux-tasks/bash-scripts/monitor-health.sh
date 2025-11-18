#!/bin/bash

################################################################################
# ECS and ALB Health Monitoring Script
#
# Description:
#   Monitors the health of ECS tasks, services, and Application Load Balancer.
#   Provides real-time status updates and can send alerts when issues are detected.
#
# Usage:
#   ./monitor-health.sh [OPTIONS]
#
# Options:
#   -c, --cluster CLUSTER       ECS cluster name (required)
#   -s, --service SERVICE       ECS service name (required)
#   -a, --alb-arn ARN          ALB target group ARN (optional)
#   -i, --interval SECONDS      Monitoring interval (default: 30)
#   -m, --max-iterations NUM    Max iterations (default: unlimited)
#   -v, --verbose               Enable verbose output
#   -j, --json                  Output in JSON format
#   -h, --help                  Show this help message
#
# Examples:
#   ./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service
#   ./monitor-health.sh --cluster my-cluster --service my-service --interval 60
#   ./monitor-health.sh -c cluster -s service -a arn:aws:elasticloadbalancing:... --verbose
#
# Exit Codes:
#   0 - Success (all checks passed or max iterations reached)
#   1 - Invalid arguments
#   2 - AWS CLI error
#   3 - Critical health issues detected
#
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Global variables
SCRIPT_NAME=$(basename "$0")
LOG_FILE="/var/log/${SCRIPT_NAME%.*}.log"
CLUSTER_NAME=""
SERVICE_NAME=""
TARGET_GROUP_ARN=""
INTERVAL=30
MAX_ITERATIONS=-1
VERBOSE=false
JSON_OUTPUT=false
ITERATION=0
CRITICAL_ISSUES=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$JSON_OUTPUT" = false ]; then
        echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    fi
}

log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
    log "INFO" "$*"
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}[✓]${NC} $*"
    fi
    log "SUCCESS" "$*"
}

log_warn() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}[⚠]${NC} $*"
    fi
    log "WARN" "$*"
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}[✗]${NC} $*" >&2
    fi
    log "ERROR" "$*"
}

log_verbose() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# Display usage
usage() {
    grep '^#' "$0" | grep -E '^# (Description:|Usage:|Options:|Examples:|Exit Codes:)' -A 50 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Validate prerequisites
validate_prerequisites() {
    # Adjust log file path if needed
    if [ ! -w "$(dirname "$LOG_FILE")" ]; then
        LOG_FILE="/tmp/${SCRIPT_NAME%.*}.log"
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 2
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 2
    fi

    # Check jq for JSON output
    if [ "$JSON_OUTPUT" = true ] && ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON output but not installed"
        exit 2
    fi
}

# Validate inputs
validate_inputs() {
    if [ -z "$CLUSTER_NAME" ]; then
        log_error "Cluster name is required. Use -c or --cluster option."
        exit 1
    fi

    if [ -z "$SERVICE_NAME" ]; then
        log_error "Service name is required. Use -s or --service option."
        exit 1
    fi

    if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 5 ]; then
        log_error "Interval must be a number >= 5 seconds"
        exit 1
    fi
}

# Check ECS service status
check_ecs_service() {
    log_verbose "Checking ECS service status..."

    local service_data
    service_data=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0]' \
        --output json 2>&1) || {
        log_error "Failed to describe service: $service_data"
        return 1
    }

    # Extract service metrics
    local status running_count desired_count pending_count deployments_count
    status=$(echo "$service_data" | jq -r '.status // "UNKNOWN"')
    running_count=$(echo "$service_data" | jq -r '.runningCount // 0')
    desired_count=$(echo "$service_data" | jq -r '.desiredCount // 0')
    pending_count=$(echo "$service_data" | jq -r '.pendingCount // 0')
    deployments_count=$(echo "$service_data" | jq '.deployments | length')

    # Store for JSON output
    ECS_SERVICE_STATUS="$status"
    ECS_RUNNING_COUNT="$running_count"
    ECS_DESIRED_COUNT="$desired_count"
    ECS_PENDING_COUNT="$pending_count"
    ECS_DEPLOYMENTS_COUNT="$deployments_count"

    # Display status
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}ECS Service Status${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    # Check if service is active
    if [ "$status" = "ACTIVE" ]; then
        log_success "Service status: $status"
    else
        log_error "Service status: $status"
        CRITICAL_ISSUES=true
    fi

    # Check task counts
    if [ "$running_count" -eq "$desired_count" ] && [ "$running_count" -gt 0 ]; then
        log_success "Tasks: $running_count/$desired_count running"
    elif [ "$running_count" -lt "$desired_count" ]; then
        log_warn "Tasks: $running_count/$desired_count running (${pending_count} pending)"
        CRITICAL_ISSUES=true
    else
        log_info "Tasks: $running_count/$desired_count running (${pending_count} pending)"
    fi

    # Check deployments
    if [ "$deployments_count" -eq 1 ]; then
        log_success "Deployments: $deployments_count (stable)"
    else
        log_warn "Deployments: $deployments_count (deployment in progress)"
    fi

    return 0
}

# Check individual ECS tasks
check_ecs_tasks() {
    log_verbose "Checking individual ECS tasks..."

    local task_arns
    task_arns=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --desired-status RUNNING \
        --query 'taskArns[]' \
        --output text 2>&1) || {
        log_error "Failed to list tasks: $task_arns"
        return 1
    }

    if [ -z "$task_arns" ] || [ "$task_arns" == "None" ]; then
        log_error "No running tasks found"
        CRITICAL_ISSUES=true
        ECS_HEALTHY_TASKS=0
        ECS_UNHEALTHY_TASKS=0
        return 1
    fi

    # Count healthy/unhealthy tasks
    local healthy_count=0
    local unhealthy_count=0

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}ECS Tasks Health${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    for task_arn in $task_arns; do
        local task_id=$(basename "$task_arn")
        local task_data
        task_data=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$task_arn" \
            --query 'tasks[0]' \
            --output json)

        local health_status last_status cpu memory private_ip
        health_status=$(echo "$task_data" | jq -r '.healthStatus // "UNKNOWN"')
        last_status=$(echo "$task_data" | jq -r '.lastStatus // "UNKNOWN"')
        cpu=$(echo "$task_data" | jq -r '.cpu // "N/A"')
        memory=$(echo "$task_data" | jq -r '.memory // "N/A"')
        private_ip=$(echo "$task_data" | jq -r '.containers[0].networkInterfaces[0].privateIpv4Address // "N/A"')

        if [ "$health_status" = "HEALTHY" ]; then
            healthy_count=$((healthy_count + 1))
            if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
                log_success "Task ${task_id:0:8}: $last_status | Health: $health_status | IP: $private_ip | CPU: $cpu | Mem: $memory"
            fi
        else
            unhealthy_count=$((unhealthy_count + 1))
            log_warn "Task ${task_id:0:8}: $last_status | Health: $health_status | IP: $private_ip"
            if [ "$health_status" != "UNKNOWN" ]; then
                CRITICAL_ISSUES=true
            fi
        fi
    done

    ECS_HEALTHY_TASKS=$healthy_count
    ECS_UNHEALTHY_TASKS=$unhealthy_count

    if [ "$JSON_OUTPUT" = false ]; then
        if [ $healthy_count -gt 0 ] && [ $unhealthy_count -eq 0 ]; then
            log_success "All $healthy_count task(s) are healthy"
        elif [ $unhealthy_count -gt 0 ]; then
            log_warn "Healthy: $healthy_count | Unhealthy: $unhealthy_count"
        fi
    fi

    return 0
}

# Check ALB target group health
check_alb_targets() {
    if [ -z "$TARGET_GROUP_ARN" ]; then
        log_verbose "Skipping ALB check (no target group ARN provided)"
        return 0
    fi

    log_verbose "Checking ALB target group health..."

    local targets_data
    targets_data=$(aws elbv2 describe-target-health \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --query 'TargetHealthDescriptions' \
        --output json 2>&1) || {
        log_error "Failed to describe target health: $targets_data"
        return 1
    }

    local healthy_count=0
    local unhealthy_count=0
    local total_count=$(echo "$targets_data" | jq 'length')

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}ALB Target Health${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    for i in $(seq 0 $((total_count - 1))); do
        local target_ip target_port health_state reason
        target_ip=$(echo "$targets_data" | jq -r ".[$i].Target.Id")
        target_port=$(echo "$targets_data" | jq -r ".[$i].Target.Port")
        health_state=$(echo "$targets_data" | jq -r ".[$i].TargetHealth.State")
        reason=$(echo "$targets_data" | jq -r ".[$i].TargetHealth.Reason // \"N/A\"")

        if [ "$health_state" = "healthy" ]; then
            healthy_count=$((healthy_count + 1))
            if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
                log_success "Target $target_ip:$target_port - $health_state"
            fi
        else
            unhealthy_count=$((unhealthy_count + 1))
            log_warn "Target $target_ip:$target_port - $health_state (Reason: $reason)"
            CRITICAL_ISSUES=true
        fi
    done

    ALB_HEALTHY_TARGETS=$healthy_count
    ALB_UNHEALTHY_TARGETS=$unhealthy_count
    ALB_TOTAL_TARGETS=$total_count

    if [ "$JSON_OUTPUT" = false ]; then
        if [ $healthy_count -eq $total_count ]; then
            log_success "All $total_count target(s) are healthy"
        else
            log_warn "Healthy: $healthy_count | Unhealthy: $unhealthy_count | Total: $total_count"
        fi
    fi

    return 0
}

# Output JSON summary
output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat <<EOF
{
  "timestamp": "$timestamp",
  "iteration": $ITERATION,
  "cluster": "$CLUSTER_NAME",
  "service": "$SERVICE_NAME",
  "ecs_service": {
    "status": "$ECS_SERVICE_STATUS",
    "running_count": $ECS_RUNNING_COUNT,
    "desired_count": $ECS_DESIRED_COUNT,
    "pending_count": $ECS_PENDING_COUNT,
    "deployments_count": $ECS_DEPLOYMENTS_COUNT
  },
  "ecs_tasks": {
    "healthy": ${ECS_HEALTHY_TASKS:-0},
    "unhealthy": ${ECS_UNHEALTHY_TASKS:-0}
  },
  "alb_targets": {
    "healthy": ${ALB_HEALTHY_TARGETS:-0},
    "unhealthy": ${ALB_UNHEALTHY_TARGETS:-0},
    "total": ${ALB_TOTAL_TARGETS:-0}
  },
  "critical_issues": $CRITICAL_ISSUES
}
EOF
}

# Main monitoring loop
monitor() {
    while true; do
        ITERATION=$((ITERATION + 1))
        CRITICAL_ISSUES=false

        if [ "$JSON_OUTPUT" = false ]; then
            clear
            echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║  ECS & ALB Health Monitor - Iter #$ITERATION   ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
            echo ""
            echo "Cluster: $CLUSTER_NAME"
            echo "Service: $SERVICE_NAME"
            echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        fi

        # Run checks
        check_ecs_service
        check_ecs_tasks
        check_alb_targets

        # Output results
        if [ "$JSON_OUTPUT" = true ]; then
            output_json
        else
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            if [ "$CRITICAL_ISSUES" = true ]; then
                echo -e "${RED}⚠  CRITICAL ISSUES DETECTED${NC}"
            else
                echo -e "${GREEN}✓  All Systems Healthy${NC}"
            fi
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "Next check in ${INTERVAL}s... (Press Ctrl+C to stop)"
        fi

        # Check if we've reached max iterations
        if [ "$MAX_ITERATIONS" -ne -1 ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
            log_info "Reached maximum iterations ($MAX_ITERATIONS)"
            break
        fi

        sleep "$INTERVAL"
    done

    # Exit with error code if critical issues were detected
    if [ "$CRITICAL_ISSUES" = true ]; then
        exit 3
    fi
}

################################################################################
# Main Script
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cluster)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -s|--service)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -a|--alb-arn)
                TARGET_GROUP_ARN="$2"
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -m|--max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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
    monitor
}

# Handle Ctrl+C gracefully
trap 'echo ""; log_info "Monitoring stopped by user"; exit 0' INT TERM

main "$@"
