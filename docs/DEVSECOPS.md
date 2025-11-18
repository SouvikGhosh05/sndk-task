# DevSecOps Implementation Guide

Comprehensive security implementation documentation for the SNDK Task infrastructure, covering secrets management, image scanning, network security, and security best practices.

## Table of Contents
- [Overview](#overview)
- [Container Image Scanning](#container-image-scanning)
- [Secrets Management](#secrets-management)
- [Network Security](#network-security)
- [IAM Security](#iam-security)
- [Monitoring & Logging](#monitoring--logging)
- [Security Best Practices](#security-best-practices)
- [Compliance & Hardening](#compliance--hardening)

---

## Overview

This infrastructure implements DevSecOps principles with security integrated at every layer:

| Security Layer | Implementation | Status |
|----------------|----------------|--------|
| **Container Security** | ECR image scanning, non-root user | ✅ Implemented |
| **Network Security** | Private subnets, security groups, NACLs | ✅ Implemented |
| **Access Control** | IAM least privilege, separate roles | ✅ Implemented |
| **Secrets Management** | AWS Secrets Manager ready | ⚠️ Documented |
| **Monitoring** | CloudWatch Logs, Container Insights | ✅ Implemented |
| **Encryption** | At-rest (ECR), in-transit (HTTPS ready) | ✅ Implemented |

---

## Container Image Scanning

### ECR Image Scanning Configuration

**Current Implementation**:
```hcl
# infrastructure/modules/ecr/main.tf
resource "aws_ecr_repository" "main" {
  name                 = "sndk-prod-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true    # ← Automatic scanning enabled
  }

  encryption_configuration {
    encryption_type = "AES256"    # ← At-rest encryption
  }
}
```

### How Image Scanning Works

**Process Flow**:
```
1. Docker Push
   docker push 654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest
      ↓
2. ECR Receives Image
   Image stored in ECR repository
      ↓
3. Automatic Scan Triggered
   ECR scans image for CVEs (Common Vulnerabilities and Exposures)
      ↓
4. Scan Results Available
   Check via AWS Console or CLI
```

### Checking Scan Results

**Command**:
```bash
# Get scan findings for latest image
aws ecr describe-image-scan-findings \
  --repository-name sndk-prod-api \
  --image-id imageTag=latest \
  --region ap-south-1
```

**Example Output**:
```json
{
  "imageScanFindings": {
    "findings": [
      {
        "name": "CVE-2024-1234",
        "severity": "MEDIUM",
        "uri": "https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-1234",
        "description": "Sample vulnerability description"
      }
    ],
    "findingSeverityCounts": {
      "CRITICAL": 0,
      "HIGH": 0,
      "MEDIUM": 2,
      "LOW": 5,
      "INFORMATIONAL": 10
    }
  }
}
```

### Scan Results Interpretation

| Severity | Action Required | Description |
|----------|----------------|-------------|
| **CRITICAL** | 🔴 Immediate fix | Actively exploited vulnerabilities |
| **HIGH** | 🟠 Fix within 7 days | Serious security impact |
| **MEDIUM** | 🟡 Fix within 30 days | Moderate security impact |
| **LOW** | 🟢 Fix when convenient | Minor security impact |
| **INFORMATIONAL** | ℹ️ No action needed | Advisory information |

### Security Mitigation Strategy

**For Critical/High Findings**:
1. Review the CVE details
2. Check if vulnerability applies to your use case
3. Update base image: `FROM node:20-alpine` → `FROM node:20.x.x-alpine`
4. Rebuild and push new image
5. Update ECS task definition
6. Deploy new revision

**Automated Scanning in CI/CD**:
```bash
# In GitHub Actions or similar
- name: Scan Image
  run: |
    aws ecr wait image-scan-complete \
      --repository-name sndk-prod-api \
      --image-id imageTag=${{ github.sha }}

    CRITICAL=$(aws ecr describe-image-scan-findings \
      --repository-name sndk-prod-api \
      --image-id imageTag=${{ github.sha }} \
      --query 'imageScanFindings.findingSeverityCounts.CRITICAL' \
      --output text)

    if [ "$CRITICAL" != "0" ]; then
      echo "Critical vulnerabilities found!"
      exit 1
    fi
```

### Container Security Best Practices (Implemented)

✅ **Non-Root User**:
```dockerfile
# application/Dockerfile
FROM node:20-alpine

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Switch to non-root user
USER nodejs
```

✅ **Minimal Base Image**:
- Using Alpine Linux (5 MB vs 100+ MB for standard)
- Fewer packages = smaller attack surface

✅ **Multi-Stage Builds**:
```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Production stage
FROM node:20-alpine
COPY --from=builder /app/node_modules ./node_modules
# Only production dependencies copied
```

✅ **.dockerignore**:
- Excludes sensitive files (.env, .git, secrets)
- Reduces image size
- Prevents secret leakage

---

## Secrets Management

### Current State

**Environment Variables** (Non-Sensitive):
```hcl
# infrastructure/modules/ecs/main.tf
environment = [
  {
    name  = "NODE_ENV"
    value = "production"    # ← OK: Not sensitive
  },
  {
    name  = "PORT"
    value = "3000"          # ← OK: Not sensitive
  },
  {
    name  = "AWS_REGION"
    value = "ap-south-1"    # ← OK: Not sensitive
  }
]
```

### AWS Secrets Manager Integration

**Step 1: Create Secret**:
```bash
# Create database credentials secret
aws secretsmanager create-secret \
  --name sndk/prod/database \
  --description "Database credentials for production" \
  --secret-string '{
    "username": "admin",
    "password": "YourSecurePassword123!",
    "host": "prod-db.abc123.ap-south-1.rds.amazonaws.com",
    "port": "5432",
    "database": "app_db"
  }' \
  --region ap-south-1

# Create API key secret
aws secretsmanager create-secret \
  --name sndk/prod/api-keys \
  --description "External API keys" \
  --secret-string '{
    "stripe_api_key": "sk_live_...",
    "sendgrid_api_key": "SG...."
  }' \
  --region ap-south-1
```

**Step 2: Grant IAM Permissions**:
```hcl
# Add to infrastructure/modules/iam/main.tf
resource "aws_iam_role_policy" "ecs_task_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-task-secrets-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:sndk/prod/*"
        ]
      }
    ]
  })
}
```

**Step 3: Reference in Task Definition**:
```hcl
# Update infrastructure/modules/ecs/main.tf
container_definitions = jsonencode([{
  name  = var.container_name
  image = var.container_image

  # Environment variables (non-sensitive)
  environment = [
    {
      name  = "NODE_ENV"
      value = "production"
    }
  ]

  # Secrets (sensitive values)
  secrets = [
    {
      name      = "DB_USERNAME"
      valueFrom = "arn:aws:secretsmanager:ap-south-1:654654234818:secret:sndk/prod/database:username::"
    },
    {
      name      = "DB_PASSWORD"
      valueFrom = "arn:aws:secretsmanager:ap-south-1:654654234818:secret:sndk/prod/database:password::"
    },
    {
      name      = "STRIPE_API_KEY"
      valueFrom = "arn:aws:secretsmanager:ap-south-1:654654234818:secret:sndk/prod/api-keys:stripe_api_key::"
    }
  ]
}])
```

**Step 4: Access in Application**:
```javascript
// application/nodejs-app/app.js
const dbConfig = {
  username: process.env.DB_USERNAME,  // Injected from Secrets Manager
  password: process.env.DB_PASSWORD,  // Injected from Secrets Manager
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME
};

// Never log secrets!
console.log('Database config loaded'); // ✓ Good
// console.log(dbConfig); // ✗ Bad - would expose secrets
```

### AWS Systems Manager Parameter Store (Alternative)

**When to Use**:
- Simpler secrets (API keys, config values)
- Free tier: 10,000 parameters
- Lower cost: $0.05/10,000 API calls

**Example**:
```bash
# Create parameter
aws ssm put-parameter \
  --name "/sndk/prod/app/api-key" \
  --value "secret-api-key-here" \
  --type "SecureString" \
  --region ap-south-1

# Reference in task definition
secrets = [
  {
    name      = "API_KEY"
    valueFrom = "arn:aws:ssm:ap-south-1:654654234818:parameter/sndk/prod/app/api-key"
  }
]
```

### Secret Rotation

**Automatic Rotation with Lambda**:
```bash
# Enable automatic rotation (example for RDS)
aws secretsmanager rotate-secret \
  --secret-id sndk/prod/database \
  --rotation-lambda-arn arn:aws:lambda:ap-south-1:654654234818:function:SecretsManagerRotation \
  --rotation-rules AutomaticallyAfterDays=30
```

### Secrets Best Practices

✅ **DO**:
- Use Secrets Manager for sensitive data
- Rotate secrets regularly (30-90 days)
- Use separate secrets per environment (dev/staging/prod)
- Grant least-privilege IAM access
- Audit secret access with CloudTrail

❌ **DON'T**:
- Hard-code secrets in code
- Commit secrets to Git
- Log secrets to CloudWatch
- Share secrets via email/Slack
- Use same secrets across environments

---

## Network Security

### Security Groups (Implemented)

**Current Configuration**:

**ALB Security Group** (`sg-0a2bc01db67e0e905`):
```
Ingress Rules:
┌──────────────────────────────────────────────┐
│ Rule 1: HTTP from Internet                  │
│   Protocol: TCP                              │
│   Port: 80                                   │
│   Source: 0.0.0.0/0 (internet)               │
│   Purpose: Public web access                 │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│ Rule 2: HTTPS from Internet                  │
│   Protocol: TCP                              │
│   Port: 443                                  │
│   Source: 0.0.0.0/0 (internet)               │
│   Purpose: Secure web access (future)        │
└──────────────────────────────────────────────┘

Egress Rules:
┌──────────────────────────────────────────────┐
│ Rule 1: All traffic to anywhere              │
│   Protocol: All                              │
│   Port: All                                  │
│   Destination: 0.0.0.0/0                     │
│   Purpose: Allow responses to ECS            │
└──────────────────────────────────────────────┘
```

**ECS Security Group** (`sg-06671fdb926d13ab1`):
```
Ingress Rules:
┌──────────────────────────────────────────────┐
│ Rule 1: Application port from ALB ONLY       │
│   Protocol: TCP                              │
│   Port: 3000                                 │
│   Source: sg-0a2bc01db67e0e905 (ALB SG)      │
│   Purpose: Accept traffic from ALB only      │
└──────────────────────────────────────────────┘

Egress Rules:
┌──────────────────────────────────────────────┐
│ Rule 1: All traffic to internet              │
│   Protocol: All                              │
│   Port: All                                  │
│   Destination: 0.0.0.0/0                     │
│   Purpose: ECR pulls, CloudWatch, APIs       │
└──────────────────────────────────────────────┘
```

### Security Group Testing

**Verify Isolation**:
```bash
# Test 1: Direct access to ECS task should FAIL
curl http://10.0.11.174:3000
# Expected: Timeout (task in private subnet, no route)

# Test 2: Access via ALB should SUCCEED
curl http://sndk-prod-alb-1451949546.ap-south-1.elb.amazonaws.com/
# Expected: 200 OK

# Test 3: Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-06671fdb926d13ab1 \
  --region ap-south-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

### Network ACLs (Default - Stateless)

**Current State**: Using default VPC NACLs (allow all)

**Enhanced Security** (Optional):
```hcl
# Add to infrastructure/modules/networking/main.tf
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Inbound: Allow from VPC only
  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }

  # Outbound: Allow to internet
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-nacl"
  }
}
```

### VPC Flow Logs (Enhanced Monitoring)

**Enable Flow Logs**:
```bash
# Create CloudWatch log group for flow logs
aws logs create-log-group \
  --log-group-name /aws/vpc/sndk-prod-flowlogs \
  --region ap-south-1

# Create IAM role for VPC Flow Logs
aws iam create-role \
  --role-name VPCFlowLogsRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "vpc-flow-logs.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-0e599a5815ee71e75 \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/sndk-prod-flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::654654234818:role/VPCFlowLogsRole \
  --region ap-south-1
```

**Use Cases**:
- Detect unusual traffic patterns
- Troubleshoot connectivity issues
- Security incident investigation
- Compliance auditing

---

## IAM Security

### Implemented Roles

**1. Task Execution Role** (Infrastructure Operations):
```
Role: sndk-prod-ecs-task-execution-role
Principal: ecs-tasks.amazonaws.com

Permissions:
  ✓ Pull images from ECR
  ✓ Create CloudWatch log streams
  ✓ Write logs to CloudWatch
  ✗ NO access to application secrets (yet)
  ✗ NO access to S3/DynamoDB

Use Case: ECS agent pulls image and sets up logging
```

**2. Task Role** (Application Operations):
```
Role: sndk-prod-ecs-task-role
Principal: ecs-tasks.amazonaws.com

Permissions:
  ✓ Write application logs to CloudWatch
  ✗ NO access to other AWS services

Use Case: Application runtime, minimal permissions
```

### Least Privilege Principles

**What We Did Right**:
✅ Separate execution role and task role
✅ Scoped permissions to specific log groups
✅ No wildcard (*) permissions
✅ Resource-specific ARNs

**Example - Scoped Permissions**:
```hcl
# BAD - Too broad
Resource = "*"

# GOOD - Specific resources
Resource = "arn:aws:logs:ap-south-1:654654234818:log-group:/ecs/sndk-prod*"
```

### IAM Policy Testing

**Verify Permissions**:
```bash
# Simulate ECR pull permission
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::654654234818:role/sndk-prod-ecs-task-execution-role \
  --action-names ecr:GetAuthorizationToken ecr:BatchGetImage \
  --resource-arns arn:aws:ecr:ap-south-1:654654234818:repository/sndk-prod-api

# Check effective permissions
aws iam get-role-policy \
  --role-name sndk-prod-ecs-task-execution-role \
  --policy-name sndk-prod-ecs-task-execution-ecr-policy
```

### IAM Best Practices

✅ **Implement**:
- Separate roles per function
- Time-based access (temporary credentials)
- MFA for sensitive operations
- Regular permission audits
- CloudTrail logging for all API calls

❌ **Avoid**:
- Sharing IAM credentials
- Long-term access keys
- Root account usage
- Overly permissive policies

---

## Monitoring & Logging

### CloudWatch Logs (Implemented)

**Configuration**:
```
Log Group: /ecs/sndk-prod
Retention: 7 days
Encryption: AES256 (default)
```

**Log Streams**:
```
/ecs/sndk-prod/api/00993ec7ab824391b3636703411f96ab
/ecs/sndk-prod/api/56607ecbf205481599e49ec426ad15e4
```

### Viewing Logs

**Real-time Monitoring**:
```bash
# Tail logs (follow mode)
aws logs tail /ecs/sndk-prod --follow

# Filter for errors
aws logs tail /ecs/sndk-prod --follow --filter-pattern "ERROR"

# View specific time range
aws logs tail /ecs/sndk-prod \
  --since 1h \
  --format short
```

**Query Logs with Insights**:
```bash
# Count requests by status code
aws logs start-query \
  --log-group-name /ecs/sndk-prod \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | stats count() by @message'
```

### Container Insights (Implemented)

**Enabled On**:
```hcl
resource "aws_ecs_cluster" "main" {
  name = "sndk-prod-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"    # ← Monitoring enabled
  }
}
```

**Metrics Available**:
- CPU Utilization (per task, per service, per cluster)
- Memory Utilization
- Network In/Out
- Storage I/O
- Task count (running, pending, desired)

**View Metrics**:
```bash
# Get CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=sndk-prod-cluster Name=ServiceName,Value=sndk-prod-service \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --period 300 \
  --statistics Average
```

### CloudWatch Alarms (Recommended)

**High CPU Alert**:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name sndk-prod-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=sndk-prod-service Name=ClusterName,Value=sndk-prod-cluster
```

**Health Check Failures**:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name sndk-prod-unhealthy-tasks \
  --alarm-description "Alert when tasks become unhealthy" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --dimensions Name=TargetGroup,Value=targetgroup/sndk-prod-tg/340e1856790c7f5f Name=LoadBalancer,Value=app/sndk-prod-alb/700e076abca1f599
```

### AWS X-Ray (Optional - Distributed Tracing)

**Enable in Task Definition**:
```hcl
container_definitions = jsonencode([{
  name  = "api"
  image = var.container_image

  # Add X-Ray daemon sidecar
  dependsOn = [{
    containerName = "xray-daemon"
    condition     = "START"
  }]
},
{
  name  = "xray-daemon"
  image = "public.ecr.aws/xray/aws-xray-daemon:latest"
  cpu   = 32
  memory = 256
  portMappings = [{
    containerPort = 2000
    protocol      = "udp"
  }]
}])
```

---

## Security Best Practices

### 1. Defense in Depth

**Multiple Security Layers**:
```
Layer 1: Network (Private subnets, Security Groups)
Layer 2: Application (Non-root user, minimal image)
Layer 3: Access Control (IAM least privilege)
Layer 4: Data (Encryption at rest and in transit)
Layer 5: Monitoring (Logs, alerts, auditing)
```

### 2. Encryption

**At Rest**:
- ✅ ECR: AES256 encryption
- ✅ EBS volumes: Encrypted by default (Fargate)
- ⚠️ S3: Not used yet
- ⚠️ RDS: Not used yet

**In Transit**:
- ⚠️ ALB → ECS: HTTP (within VPC, acceptable)
- ❌ Internet → ALB: HTTP only (HTTPS recommended)

**Enable HTTPS** (Recommended):
```bash
# 1. Request ACM certificate
aws acm request-certificate \
  --domain-name app.yourdomain.com \
  --validation-method DNS \
  --region ap-south-1

# 2. Add HTTPS listener to ALB
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:ap-south-1:654654234818:loadbalancer/app/sndk-prod-alb/700e076abca1f599 \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:ap-south-1:654654234818:certificate/xxxxx \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:ap-south-1:654654234818:targetgroup/sndk-prod-tg/340e1856790c7f5f
```

### 3. Regular Updates

**Container Images**:
```bash
# Update base image monthly
FROM node:20-alpine → FROM node:20.11.1-alpine

# Rebuild and redeploy
docker build -t hello-api:latest .
# ... push to ECR
# ... update ECS service (forces new deployment)
```

**Terraform Providers**:
```bash
# Check for updates
terraform init -upgrade

# Review provider changes
terraform plan
```

### 4. Audit & Compliance

**Enable CloudTrail** (All API Calls):
```bash
aws cloudtrail create-trail \
  --name sndk-prod-audit \
  --s3-bucket-name sndk-cloudtrail-logs \
  --is-multi-region-trail \
  --enable-log-file-validation
```

**AWS Config** (Configuration Compliance):
```bash
# Enable Config to track resource changes
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::654654234818:role/aws-config-role \
  --recording-group allSupported=true,includeGlobalResourceTypes=true
```

### 5. Incident Response

**Runbook for Security Incident**:
1. **Detect**: CloudWatch Alarm triggers
2. **Isolate**: Modify security group to block traffic
   ```bash
   aws ec2 revoke-security-group-ingress \
     --group-id sg-06671fdb926d13ab1 \
     --protocol tcp --port 3000 \
     --source-group sg-0a2bc01db67e0e905
   ```
3. **Investigate**: Review CloudWatch Logs, VPC Flow Logs
4. **Remediate**: Update task definition, deploy new version
5. **Document**: Create incident report

---

## Compliance & Hardening

### CIS Benchmarks

**Implemented**:
✅ Separate IAM roles per function
✅ Encryption at rest (ECR)
✅ Logging enabled (CloudWatch)
✅ Non-root container user
✅ Private subnets for compute
✅ Security groups configured

**Recommended**:
⚠️ Enable MFA for root account
⚠️ Enable AWS Config
⚠️ Enable GuardDuty (threat detection)
⚠️ Enable CloudTrail
⚠️ Implement password policy

### AWS Security Hub

**Enable**:
```bash
aws securityhub enable-security-hub --region ap-south-1
```

**Benefits**:
- Aggregates security findings
- Checks against CIS AWS Foundations Benchmark
- Provides security score
- Automated compliance checks

### AWS GuardDuty (Threat Detection)

**Enable**:
```bash
aws guardduty create-detector --enable --region ap-south-1
```

**What It Monitors**:
- Unusual API calls
- Compromised instances
- Reconnaissance attacks
- Bitcoin mining activity

---

## Summary

### Security Posture

| Area | Status | Notes |
|------|--------|-------|
| **Container Security** | ✅ Strong | Image scanning, non-root user, minimal image |
| **Network Security** | ✅ Strong | Private subnets, security groups, NAT Gateway |
| **Access Control** | ✅ Strong | IAM least privilege, separate roles |
| **Secrets** | ⚠️ Ready | Infrastructure ready, needs implementation |
| **Monitoring** | ✅ Strong | CloudWatch Logs, Container Insights enabled |
| **Encryption** | ⚠️ Partial | At-rest yes, in-transit needs HTTPS |
| **Compliance** | ⚠️ Partial | Good foundation, needs CloudTrail/Config |

### Priority Security Enhancements

**High Priority**:
1. Enable HTTPS on ALB with ACM certificate
2. Implement CloudTrail for audit logging
3. Set up CloudWatch alarms for critical metrics
4. Migrate sensitive config to Secrets Manager

**Medium Priority**:
5. Enable AWS Config for compliance tracking
6. Enable GuardDuty for threat detection
7. Implement VPC Flow Logs
8. Set up automated secret rotation

**Low Priority**:
9. Implement WAF rules on ALB
10. Enable AWS Security Hub
11. Add read-only root filesystem to containers
12. Implement network ACLs

---

**Document Version**: 1.0
**Last Updated**: 2025-11-18
**Status**: Production-Ready with Recommended Enhancements
