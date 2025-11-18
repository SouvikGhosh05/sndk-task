#!/bin/bash

################################################################################
# ECS Deployment Script
#
# Description:
#   Deploys a new version of the containerized application to ECS Fargate.
#   Includes health check validation, rollback capability, and detailed logging.
#
# Usage:
#   ./deploy-ecs.sh [OPTIONS]
#
# Options:
#   -c, --cluster CLUSTER       ECS cluster name (required)
#   -s, --service SERVICE       ECS service name (required)
#   -i, --image IMAGE_URI       Docker image URI (required)
#   -t, --timeout SECONDS       Deployment timeout (default: 600)
#   -w, --wait-stable           Wait for service to become stable
#   -h, --help                  Show this help message
#
# Examples:
#   ./deploy-ecs.sh -c sndk-prod-cluster -s sndk-prod-service -i 123456.dkr.ecr.region.amazonaws.com/app:v1.2.3
#   ./deploy-ecs.sh --cluster my-cluster --service my-service --image my-image:latest --wait-stable
#
# Exit Codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - AWS CLI error
#   3 - Deployment failed
#   4 - Health check failed
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
IMAGE_URI=""
TIMEOUT=600
WAIT_STABLE=false
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

# Logging function with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    log "WARN" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$*"
}

# Display usage information
usage() {
    grep '^#' "$0" | grep -E '^# (Description:|Usage:|Options:|Examples:|Exit Codes:)' -A 50 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if running with proper permissions
    if [ ! -w "$(dirname "$LOG_FILE")" ]; then
        LOG_FILE="/tmp/${SCRIPT_NAME%.*}.log"
        log_warn "Cannot write to /var/log, using $LOG_FILE instead"
    fi

    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 2
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 2
    fi

    log_success "Prerequisites validated"
}

# Validate input parameters
validate_inputs() {
    log_info "Validating input parameters..."

    if [ -z "$CLUSTER_NAME" ]; then
        log_error "Cluster name is required. Use -c or --cluster option."
        exit 1
    fi

    if [ -z "$SERVICE_NAME" ]; then
        log_error "Service name is required. Use -s or --service option."
        exit 1
    fi

    if [ -z "$IMAGE_URI" ]; then
        log_error "Image URI is required. Use -i or --image option."
        exit 1
    fi

    if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 60 ]; then
        log_error "Timeout must be a number >= 60 seconds."
        exit 1
    fi

    log_success "Input parameters validated"
}

# Get current task definition
get_current_task_definition() {
    log_info "Retrieving current task definition..."

    local service_desc
    service_desc=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0].taskDefinition' \
        --output text 2>&1) || {
        log_error "Failed to describe service: $service_desc"
        exit 2
    }

    if [ "$service_desc" == "None" ] || [ -z "$service_desc" ]; then
        log_error "Service '$SERVICE_NAME' not found in cluster '$CLUSTER_NAME'"
        exit 2
    fi

    echo "$service_desc"
}

# Create new task definition with updated image
create_new_task_definition() {
    local current_task_def="$1"
    log_info "Creating new task definition with image: $IMAGE_URI"

    # Get current task definition JSON
    local task_def_json
    task_def_json=$(aws ecs describe-task-definition \
        --task-definition "$current_task_def" \
        --query 'taskDefinition' 2>&1) || {
        log_error "Failed to retrieve task definition: $task_def_json"
        exit 2
    }

    # Update image in container definitions
    local new_task_def
    new_task_def=$(echo "$task_def_json" | jq --arg img "$IMAGE_URI" '
        .containerDefinitions[0].image = $img |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
    ') || {
        log_error "Failed to parse task definition JSON"
        exit 2
    }

    # Register new task definition
    local new_task_arn
    new_task_arn=$(aws ecs register-task-definition \
        --cli-input-json "$new_task_def" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text 2>&1) || {
        log_error "Failed to register new task definition: $new_task_arn"
        exit 2
    }

    log_success "New task definition created: $new_task_arn"
    echo "$new_task_arn"
}

# Update ECS service with new task definition
update_service() {
    local new_task_def="$1"
    log_info "Updating service '$SERVICE_NAME' with new task definition..."

    local update_result
    update_result=$(aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$new_task_def" \
        --force-new-deployment \
        --query 'service.deployments[0].id' \
        --output text 2>&1) || {
        log_error "Failed to update service: $update_result"
        exit 3
    }

    log_success "Service update initiated. Deployment ID: $update_result"
    echo "$update_result"
}

# Wait for service to stabilize
wait_for_stable() {
    log_info "Waiting for service to become stable (timeout: ${TIMEOUT}s)..."

    local elapsed=0
    local interval=10

    while [ $elapsed -lt "$TIMEOUT" ]; do
        # Check service status
        local running_count desired_count
        running_count=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --query 'services[0].runningCount' \
            --output text)

        desired_count=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --query 'services[0].desiredCount' \
            --output text)

        # Check deployment status
        local deployments_count
        deployments_count=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --query 'length(services[0].deployments)' \
            --output text)

        log_info "Status: $running_count/$desired_count tasks running, $deployments_count active deployment(s)"

        # Service is stable when running count matches desired and only 1 deployment exists
        if [ "$running_count" -eq "$desired_count" ] && [ "$deployments_count" -eq 1 ]; then
            log_success "Service is stable!"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for service to stabilize"
    return 1
}

# Check health of tasks
check_task_health() {
    log_info "Checking health of running tasks..."

    local task_arns
    task_arns=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --desired-status RUNNING \
        --query 'taskArns' \
        --output text)

    if [ -z "$task_arns" ] || [ "$task_arns" == "None" ]; then
        log_error "No running tasks found"
        return 1
    fi

    # Describe tasks
    local unhealthy_count=0
    for task_arn in $task_arns; do
        local task_health
        task_health=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$task_arn" \
            --query 'tasks[0].healthStatus' \
            --output text)

        local task_status
        task_status=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$task_arn" \
            --query 'tasks[0].lastStatus' \
            --output text)

        if [ "$task_health" != "HEALTHY" ] && [ "$task_health" != "UNKNOWN" ]; then
            log_warn "Task $(basename "$task_arn") is $task_status with health: $task_health"
            unhealthy_count=$((unhealthy_count + 1))
        else
            log_info "Task $(basename "$task_arn") is $task_status with health: $task_health"
        fi
    done

    if [ $unhealthy_count -gt 0 ]; then
        log_warn "$unhealthy_count task(s) are not healthy"
        return 1
    fi

    log_success "All tasks are healthy"
    return 0
}

# Rollback to previous task definition
rollback() {
    local previous_task_def="$1"
    log_warn "Initiating rollback to previous task definition: $previous_task_def"

    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$previous_task_def" \
        --force-new-deployment \
        --no-cli-pager &> /dev/null || {
        log_error "Rollback failed! Manual intervention required."
        exit 3
    }

    log_success "Rollback initiated successfully"
}

# Cleanup and summary
cleanup_and_summary() {
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    echo ""
    log_info "========================================="
    log_info "Deployment Summary"
    log_info "========================================="
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Service: $SERVICE_NAME"
    log_info "Image: $IMAGE_URI"
    log_info "Duration: ${duration}s"
    log_info "Exit Code: $exit_code"
    log_info "Log File: $LOG_FILE"
    log_info "========================================="

    exit $exit_code
}

################################################################################
# Main Script
################################################################################

main() {
    log_info "========================================="
    log_info "ECS Deployment Script Started"
    log_info "========================================="

    # Parse command line arguments
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
            -i|--image)
                IMAGE_URI="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -w|--wait-stable)
                WAIT_STABLE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate and execute
    validate_prerequisites
    validate_inputs

    # Store current task definition for rollback
    local current_task_def
    current_task_def=$(get_current_task_definition)
    log_info "Current task definition: $current_task_def"

    # Create new task definition and update service
    local new_task_def
    new_task_def=$(create_new_task_definition "$current_task_def")

    local deployment_id
    deployment_id=$(update_service "$new_task_def")

    # Wait for deployment if requested
    if [ "$WAIT_STABLE" = true ]; then
        if ! wait_for_stable; then
            log_error "Service failed to stabilize"
            rollback "$current_task_def"
            exit 3
        fi

        # Additional health check
        sleep 15
        if ! check_task_health; then
            log_error "Health check failed"
            rollback "$current_task_def"
            exit 4
        fi
    else
        log_info "Deployment initiated. Use --wait-stable to wait for completion."
    fi

    log_success "Deployment completed successfully!"
}

# Trap to ensure cleanup runs
trap cleanup_and_summary EXIT

# Run main function
main "$@"
