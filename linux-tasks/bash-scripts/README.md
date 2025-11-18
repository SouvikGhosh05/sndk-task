# Bash Scripts for ECS Operations

Production-ready bash scripts for managing and monitoring ECS Fargate infrastructure.

## Overview

This directory contains 3 production-ready bash scripts with comprehensive error handling, logging, input validation, and idempotent operations.

## Scripts

### 1. deploy-ecs.sh

Deploys new versions of containerized applications to ECS Fargate with automated health checks and rollback capability.

**Features:**
- Updates ECS service with new Docker image
- Automatic task definition creation
- Health check validation
- Automatic rollback on failure
- Deployment timeout handling
- Detailed logging and status reporting

**Usage:**
```bash
# Basic deployment
./deploy-ecs.sh -c sndk-prod-cluster -s sndk-prod-service -i 654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest

# Deployment with stability wait
./deploy-ecs.sh -c sndk-prod-cluster -s sndk-prod-service -i IMAGE_URI --wait-stable

# With custom timeout
./deploy-ecs.sh -c CLUSTER -s SERVICE -i IMAGE_URI -t 900 --wait-stable
```

**Options:**
- `-c, --cluster` - ECS cluster name (required)
- `-s, --service` - ECS service name (required)
- `-i, --image` - Docker image URI (required)
- `-t, --timeout` - Deployment timeout in seconds (default: 600)
- `-w, --wait-stable` - Wait for service to become stable
- `-h, --help` - Show help message

**Exit Codes:**
- `0` - Success
- `1` - Invalid arguments
- `2` - AWS CLI error
- `3` - Deployment failed
- `4` - Health check failed

---

### 2. monitor-health.sh

Real-time health monitoring for ECS services, tasks, and ALB target groups.

**Features:**
- ECS service status monitoring (running/desired counts)
- Individual task health checks
- ALB target group health monitoring
- Real-time dashboard with auto-refresh
- JSON output mode for automation
- Verbose mode for debugging
- Configurable monitoring interval

**Usage:**
```bash
# Basic monitoring
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service

# With ALB target group monitoring
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -a arn:aws:elasticloadbalancing:...

# Custom interval and verbose output
./monitor-health.sh -c CLUSTER -s SERVICE -i 60 -v

# JSON output for automation
./monitor-health.sh -c CLUSTER -s SERVICE -j

# Limited iterations
./monitor-health.sh -c CLUSTER -s SERVICE -m 10
```

**Options:**
- `-c, --cluster` - ECS cluster name (required)
- `-s, --service` - ECS service name (required)
- `-a, --alb-arn` - ALB target group ARN (optional)
- `-i, --interval` - Monitoring interval in seconds (default: 30)
- `-m, --max-iterations` - Max iterations (default: unlimited)
- `-v, --verbose` - Enable verbose output
- `-j, --json` - Output in JSON format
- `-h, --help` - Show help message

**Exit Codes:**
- `0` - Success (all checks passed)
- `1` - Invalid arguments
- `2` - AWS CLI error
- `3` - Critical health issues detected

---

### 3. fetch-logs.sh

CloudWatch logs retrieval, analysis, and tailing with advanced filtering.

**Features:**
- Fetch logs from CloudWatch log groups
- Real-time log tailing (like `tail -f`)
- Error-only filtering
- Custom pattern filtering
- Automatic log analysis (error counts, HTTP status codes)
- Color-coded output by log level
- Save logs to file
- JSON output mode

**Usage:**
```bash
# Fetch last 100 lines
./fetch-logs.sh -g /ecs/sndk-prod-api

# Tail logs in real-time
./fetch-logs.sh -g /ecs/sndk-prod-api --tail

# Show only errors from last 30 minutes
./fetch-logs.sh -g /ecs/sndk-prod-api --errors-only -d 30

# Filter by pattern
./fetch-logs.sh -g /ecs/sndk-prod-api -f "POST /api" -n 200

# Save to file
./fetch-logs.sh -g /ecs/sndk-prod-api -d 120 -o logs-$(date +%Y%m%d).txt

# Specific log stream
./fetch-logs.sh -g /ecs/sndk-prod-api -s "ecs/api/abc123"
```

**Options:**
- `-g, --log-group` - CloudWatch log group name (required)
- `-s, --log-stream` - Log stream name pattern (optional)
- `-f, --filter` - Filter pattern for log events
- `-t, --tail` - Tail logs in real-time
- `-n, --lines` - Number of lines to fetch (default: 100)
- `-d, --duration` - Fetch logs from last N minutes (default: 60)
- `-e, --errors-only` - Show only ERROR level logs
- `-o, --output` - Save output to file
- `-j, --json` - Output in JSON format
- `-h, --help` - Show help message

**Exit Codes:**
- `0` - Success
- `1` - Invalid arguments
- `2` - AWS CLI error
- `3` - No logs found

---

## Common Features Across All Scripts

### Error Handling
- Comprehensive input validation
- AWS CLI error detection
- Graceful error messages
- Non-zero exit codes for automation

### Logging
- Timestamped log entries
- Multiple log levels (INFO, SUCCESS, WARN, ERROR)
- Log files: `/var/log/SCRIPT_NAME.log` (falls back to `/tmp` if needed)
- Color-coded console output

### Idempotency
- Safe to run multiple times
- No destructive operations without confirmation
- Automatic rollback on failure (deploy-ecs.sh)

### Best Practices
- `set -euo pipefail` for strict error handling
- Input validation before execution
- AWS credentials verification
- Prerequisite checks (AWS CLI, jq, etc.)
- Signal handling (Ctrl+C gracefully stops)

---

## Prerequisites

All scripts require:
- **AWS CLI v2** - Configured with valid credentials
- **jq** - JSON processing (install: `sudo apt install jq`)
- **Bash 4.0+**
- **AWS IAM permissions** for respective services

### IAM Permissions Required

**deploy-ecs.sh:**
- `ecs:DescribeServices`
- `ecs:DescribeTaskDefinition`
- `ecs:RegisterTaskDefinition`
- `ecs:UpdateService`

**monitor-health.sh:**
- `ecs:DescribeServices`
- `ecs:ListTasks`
- `ecs:DescribeTasks`
- `elasticloadbalancing:DescribeTargetHealth`

**fetch-logs.sh:**
- `logs:DescribeLogGroups`
- `logs:DescribeLogStreams`
- `logs:FilterLogEvents`

---

## Quick Start

### Make Scripts Executable
```bash
chmod +x *.sh
```

### Test AWS Connectivity
```bash
aws sts get-caller-identity
aws ecs list-clusters
```

### Run Health Check
```bash
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -m 1 -v
```

### Check Recent Logs
```bash
./fetch-logs.sh -g /ecs/sndk-prod-api -n 50
```

---

## Operational Workflows

### Deployment Workflow
```bash
# 1. Check current health
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -m 1

# 2. Deploy new version
./deploy-ecs.sh \
  -c sndk-prod-cluster \
  -s sndk-prod-service \
  -i 654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:v1.2.3 \
  --wait-stable

# 3. Monitor deployment
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -m 5 -i 30

# 4. Check logs for errors
./fetch-logs.sh -g /ecs/sndk-prod-api --errors-only -d 10
```

### Troubleshooting Workflow
```bash
# 1. Check service health
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -m 1 -v

# 2. Fetch recent error logs
./fetch-logs.sh -g /ecs/sndk-prod-api --errors-only -d 30 -o errors.log

# 3. Tail logs in real-time
./fetch-logs.sh -g /ecs/sndk-prod-api --tail --errors-only

# 4. Analyze specific patterns
./fetch-logs.sh -g /ecs/sndk-prod-api -f "500 Internal Server" -d 60
```

### Monitoring Workflow
```bash
# Continuous monitoring
./monitor-health.sh -c sndk-prod-cluster -s sndk-prod-service -i 60 -v

# In another terminal - tail logs
./fetch-logs.sh -g /ecs/sndk-prod-api --tail
```

---

## Integration with CI/CD

### Example Jenkins Pipeline
```groovy
stage('Deploy') {
    steps {
        sh """
            ./deploy-ecs.sh \
              -c ${ECS_CLUSTER} \
              -s ${ECS_SERVICE} \
              -i ${ECR_IMAGE}:${BUILD_TAG} \
              --wait-stable
        """
    }
}

stage('Health Check') {
    steps {
        sh """
            ./monitor-health.sh \
              -c ${ECS_CLUSTER} \
              -s ${ECS_SERVICE} \
              -m 3 -i 30
        """
    }
}
```

### Example GitHub Actions
```yaml
- name: Deploy to ECS
  run: |
    ./deploy-ecs.sh \
      -c ${{ env.ECS_CLUSTER }} \
      -s ${{ env.ECS_SERVICE }} \
      -i ${{ env.ECR_REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      --wait-stable

- name: Verify Deployment
  run: |
    ./monitor-health.sh \
      -c ${{ env.ECS_CLUSTER }} \
      -s ${{ env.ECS_SERVICE }} \
      -m 5 -i 20
```

---

## Troubleshooting

### Common Issues

**Problem: "AWS credentials not configured"**
```bash
# Solution: Configure AWS CLI
aws configure
# Or set environment variables
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_DEFAULT_REGION=ap-south-1
```

**Problem: "jq: command not found"**
```bash
# Solution: Install jq
sudo apt-get update && sudo apt-get install -y jq
```

**Problem: "Permission denied"**
```bash
# Solution: Make scripts executable
chmod +x *.sh
```

**Problem: "Cannot write to /var/log"**
- Scripts automatically fall back to `/tmp` for log files
- Check logs at: `/tmp/SCRIPT_NAME.log`

---

## Logs Location

- **Default:** `/var/log/SCRIPT_NAME.log`
- **Fallback:** `/tmp/SCRIPT_NAME.log`
- Each script maintains its own log file with timestamped entries

---

## Security Considerations

- Scripts validate all inputs before execution
- No hardcoded credentials
- AWS credentials from AWS CLI configuration or IAM roles
- Logs may contain sensitive information - secure appropriately
- Use IAM roles with least privilege principle

---

## Support

For issues or questions:
1. Check the script's help: `./SCRIPT_NAME.sh --help`
2. Review log files in `/var/log/` or `/tmp/`
3. Enable verbose mode: `-v` flag
4. Verify AWS permissions for the operation

---

## Version

All scripts: **v1.0.0**

Created: 2025-11-18
