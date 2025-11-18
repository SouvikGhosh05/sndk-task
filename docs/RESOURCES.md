# AWS Resources Inventory

Complete inventory of all AWS resources created for the SNDK Task infrastructure.

## Summary

| Category | Count | Primary Services |
|----------|-------|------------------|
| **Networking** | 21 | VPC, Subnets, NAT Gateway, IGW, Route Tables, Security Groups |
| **Container** | 2 | ECR Repository, Lifecycle Policy |
| **IAM** | 5 | IAM Roles, IAM Policies |
| **Load Balancer** | 3 | Application Load Balancer, Target Group, Listener |
| **Compute (ECS)** | 4 | ECS Cluster, Service, Task Definition, Log Group |
| **TOTAL** | **31** | - |

---

## Networking Resources (21 Resources)

### VPC (1)

| Resource Type | Name | ID | CIDR | Region |
|---------------|------|-----|------|--------|
| VPC | sndk-prod-vpc | `vpc-0e599a5815ee71e75` | 10.0.0.0/16 | ap-south-1 |

### Subnets (4)

| Type | Name | ID | CIDR | AZ | Public IP |
|------|------|-----|------|-----|-----------|
| Public | sndk-prod-public-subnet-1 | `subnet-0700f9642ac180a7a` | 10.0.1.0/24 | ap-south-1a | ✓ Yes |
| Public | sndk-prod-public-subnet-2 | `subnet-0711620e474af22c6` | 10.0.2.0/24 | ap-south-1b | ✓ Yes |
| Private | sndk-prod-private-subnet-1 | `subnet-06eebcc2a64387459` | 10.0.11.0/24 | ap-south-1a | ✗ No |
| Private | sndk-prod-private-subnet-2 | `subnet-054de174e008afbc6` | 10.0.12.0/24 | ap-south-1b | ✗ No |

### Gateways (2)

| Type | Name | ID | Public IP | Subnet |
|------|------|-----|-----------|--------|
| Internet Gateway | sndk-prod-igw | `igw-xxx` | N/A | Attached to VPC |
| NAT Gateway | sndk-prod-nat-gateway | `nat-05e0339850789221e` | 13.126.79.113 | public-subnet-1 |

### Elastic IP (1)

| Name | Allocation ID | Public IP | Associated With |
|------|---------------|-----------|-----------------|
| sndk-prod-nat-eip | `eipalloc-xxx` | 13.126.79.113 | NAT Gateway |

### Route Tables (2)

| Name | ID | Routes | Associated Subnets |
|------|-----|--------|-------------------|
| sndk-prod-public-rt | `rtb-xxx` | `10.0.0.0/16 → local`<br>`0.0.0.0/0 → igw-xxx` | public-subnet-1, public-subnet-2 |
| sndk-prod-private-rt | `rtb-xxx` | `10.0.0.0/16 → local`<br>`0.0.0.0/0 → nat-05e0339850789221e` | private-subnet-1, private-subnet-2 |

### Route Table Associations (4)

| Route Table | Subnet | Purpose |
|-------------|--------|---------|
| public-rt | public-subnet-1 | Internet access via IGW |
| public-rt | public-subnet-2 | Internet access via IGW |
| private-rt | private-subnet-1 | Internet access via NAT |
| private-rt | private-subnet-2 | Internet access via NAT |

### Security Groups (2)

| Name | ID | VPC | Purpose |
|------|-----|-----|---------|
| sndk-prod-alb-sg | `sg-0a2bc01db67e0e905` | vpc-0e599a5815ee71e75 | ALB security group |
| sndk-prod-ecs-sg | `sg-06671fdb926d13ab1` | vpc-0e599a5815ee71e75 | ECS tasks security group |

### Security Group Rules (5)

**ALB Security Group Rules (3)**:

| Direction | Type | Protocol | Port | Source/Destination | Description |
|-----------|------|----------|------|-------------------|-------------|
| Ingress | IPv4 | TCP | 80 | 0.0.0.0/0 | HTTP from internet |
| Ingress | IPv4 | TCP | 443 | 0.0.0.0/0 | HTTPS from internet |
| Egress | IPv4 | All | All | 0.0.0.0/0 | Allow all outbound |

**ECS Security Group Rules (2)**:

| Direction | Type | Protocol | Port | Source/Destination | Description |
|-----------|------|----------|------|-------------------|-------------|
| Ingress | SG Reference | TCP | 3000 | sg-0a2bc01db67e0e905 (ALB) | Allow from ALB only |
| Egress | IPv4 | All | All | 0.0.0.0/0 | Allow all outbound |

---

## Container Resources (2 Resources)

### ECR Repository (1)

| Name | URI | Encryption | Image Scanning | Lifecycle Policy |
|------|-----|------------|----------------|------------------|
| sndk-prod-api | `654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api` | AES256 | ✓ Enabled | Keep last 10 images |

### ECR Lifecycle Policy (1)

| Repository | Policy | Description |
|------------|--------|-------------|
| sndk-prod-api | Keep 10 images | Automatically delete images older than the 10 most recent |

**Current Images**:
- `sndk-prod-api:latest` - 48.5 MB (sha256:9248187...)

---

## IAM Resources (5 Resources)

### IAM Roles (2)

| Role Name | ARN | Service Principal | Purpose |
|-----------|-----|-------------------|---------|
| sndk-prod-ecs-task-execution-role | `arn:aws:iam::654654234818:role/sndk-prod-ecs-task-execution-role` | ecs-tasks.amazonaws.com | ECS agent operations |
| sndk-prod-ecs-task-role | `arn:aws:iam::654654234818:role/sndk-prod-ecs-task-role` | ecs-tasks.amazonaws.com | Application runtime |

### IAM Role Policies (3)

**Task Execution Role Policies (2)**:

| Policy Name | Type | Permissions |
|-------------|------|-------------|
| AmazonECSTaskExecutionRolePolicy | AWS Managed | ECR pull, CloudWatch logs (standard) |
| sndk-prod-ecs-task-execution-ecr-policy | Inline | ECR: GetAuthorizationToken, BatchGetImage<br>CloudWatch: CreateLogGroup, PutLogEvents |

**Task Role Policies (1)**:

| Policy Name | Type | Permissions |
|-------------|------|-------------|
| sndk-prod-ecs-task-policy | Inline | CloudWatch: CreateLogStream, PutLogEvents |

---

## Load Balancer Resources (3 Resources)

### Application Load Balancer (1)

| Name | DNS Name | Scheme | AZs | Subnets |
|------|----------|--------|-----|---------|
| sndk-prod-alb | `sndk-prod-alb-1451949546.ap-south-1.elb.amazonaws.com` | internet-facing | ap-south-1a, ap-south-1b | public-subnet-1, public-subnet-2 |

**Configuration**:
- IP Address Type: ipv4
- Load Balancer Type: application
- Security Group: sg-0a2bc01db67e0e905
- Deletion Protection: Disabled
- HTTP/2: Enabled
- Idle Timeout: 60 seconds

### Target Group (1)

| Name | ARN | Port | Protocol | Target Type | VPC |
|------|-----|------|----------|-------------|-----|
| sndk-prod-tg | `arn:aws:elasticloadbalancing:ap-south-1:654654234818:targetgroup/sndk-prod-tg/340e1856790c7f5f` | 3000 | HTTP | ip | vpc-0e599a5815ee71e75 |

**Health Check Configuration**:
- Path: `/health`
- Protocol: HTTP
- Port: traffic-port (3000)
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy Threshold: 2 consecutive successes
- Unhealthy Threshold: 3 consecutive failures
- Matcher: 200

**Current Targets**:
| Target IP | Port | AZ | Health Status |
|-----------|------|-----|---------------|
| 10.0.11.174 | 3000 | ap-south-1a | healthy ✓ |
| 10.0.12.15 | 3000 | ap-south-1b | healthy ✓ |

### Listener (1)

| Protocol | Port | Default Action | Rules |
|----------|------|----------------|-------|
| HTTP | 80 | Forward to sndk-prod-tg | None (default only) |

---

## ECS Resources (4 Resources)

### ECS Cluster (1)

| Name | ARN | Status | Container Insights |
|------|-----|--------|-------------------|
| sndk-prod-cluster | `arn:aws:ecs:ap-south-1:654654234818:cluster/sndk-prod-cluster` | ACTIVE | ✓ Enabled |

**Current State**:
- Running Tasks: 2
- Pending Tasks: 0
- Services: 1

### ECS Task Definition (1)

| Family | Revision | ARN | Status |
|--------|----------|-----|--------|
| sndk-prod-task | 1 | `arn:aws:ecs:ap-south-1:654654234818:task-definition/sndk-prod-task:1` | ACTIVE |

**Configuration**:
- Network Mode: awsvpc
- Requires Compatibilities: FARGATE
- CPU: 256 (0.25 vCPU)
- Memory: 512 MB
- Task Execution Role: sndk-prod-ecs-task-execution-role
- Task Role: sndk-prod-ecs-task-role

**Container Definition**:
- Name: api
- Image: `654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest`
- Port Mappings: 3000/tcp
- Environment Variables:
  - NODE_ENV=production
  - PORT=3000
  - AWS_REGION=ap-south-1
- Log Driver: awslogs
  - Log Group: /ecs/sndk-prod
  - Region: ap-south-1
  - Stream Prefix: ecs

**Health Check**:
```bash
Command: wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
Interval: 30 seconds
Timeout: 5 seconds
Retries: 3
Start Period: 60 seconds
```

### ECS Service (1)

| Name | Cluster | Desired Count | Running Count | Launch Type |
|------|---------|---------------|---------------|-------------|
| sndk-prod-service | sndk-prod-cluster | 2 | 2 | FARGATE |

**Configuration**:
- Platform Version: LATEST
- Scheduling Strategy: REPLICA
- Deployment Configuration:
  - Maximum Percent: 200
  - Minimum Healthy Percent: 100
- Health Check Grace Period: 60 seconds

**Network Configuration**:
- Subnets: private-subnet-1, private-subnet-2
- Security Groups: sg-06671fdb926d13ab1 (ECS)
- Assign Public IP: No

**Load Balancer**:
- Target Group: sndk-prod-tg
- Container Name: api
- Container Port: 3000

**Current Tasks**:
| Task ID | AZ | Private IP | Status | Health |
|---------|-----|------------|--------|--------|
| 00993ec7ab824391b3636703411f96ab | ap-south-1a | 10.0.11.174 | RUNNING | Healthy ✓ |
| 56607ecbf205481599e49ec426ad15e4 | ap-south-1b | 10.0.12.15 | RUNNING | Healthy ✓ |

### CloudWatch Log Group (1)

| Name | Retention | Encrypted | Size |
|------|-----------|-----------|------|
| /ecs/sndk-prod | 7 days | No | ~5 MB |

**Log Streams**:
- ecs/api/00993ec7ab824391b3636703411f96ab
- ecs/api/56607ecbf205481599e49ec426ad15e4

---

## Resource Dependencies

```
VPC
 ├── Subnets (4)
 │   ├── Public Subnets → NAT Gateway, ALB
 │   └── Private Subnets → ECS Tasks
 ├── Internet Gateway → VPC
 ├── NAT Gateway → Public Subnet, Elastic IP
 ├── Route Tables (2)
 │   ├── Public RT → Internet Gateway
 │   └── Private RT → NAT Gateway
 └── Security Groups (2)
     ├── ALB SG → ALB
     └── ECS SG → ECS Tasks

ECR Repository → ECS Task Definition

IAM Roles
 ├── Task Execution Role → ECS Service
 └── Task Role → ECS Service

ALB
 ├── Target Group → ECS Service
 └── Listener → Target Group

ECS Cluster
 └── ECS Service
     ├── Task Definition
     ├── Target Group
     ├── Security Group
     ├── Subnets
     └── IAM Roles
```

---

## Cost Breakdown

### Estimated Monthly Costs (ap-south-1)

| Resource | Unit Cost | Quantity | Monthly Cost |
|----------|-----------|----------|--------------|
| **NAT Gateway** | $0.045/hour | 1 | ~$32.40 |
| **NAT Gateway Data** | $0.045/GB | ~10 GB | ~$0.45 |
| **Elastic IP** | $0.00 (attached) | 1 | $0.00 |
| **ECS Fargate (vCPU)** | $0.04048/vCPU-hour | 0.5 vCPU | ~$14.57 |
| **ECS Fargate (Memory)** | $0.004445/GB-hour | 1 GB | ~$3.20 |
| **Application Load Balancer** | $0.0225/hour | 1 | ~$16.20 |
| **ALB LCU** | $0.008/LCU-hour | ~10 LCUs | ~$5.76 |
| **ECR Storage** | $0.10/GB-month | ~0.05 GB | ~$0.01 |
| **CloudWatch Logs** | $0.50/GB ingested | ~1 GB | ~$0.50 |
| **CloudWatch Storage** | $0.03/GB-month | ~5 GB | ~$0.15 |
| **Data Transfer OUT** | $0.09/GB (first 10 TB) | ~5 GB | ~$0.45 |

**Total Estimated Cost**: **~$73.69 per month**

### Cost Optimization Opportunities

1. **Single AZ Deployment**: Remove second task → Save ~$9/month (reduces HA)
2. **Reserved Capacity**: Not available for Fargate
3. **Spot Instances**: Not available for Fargate
4. **VPC Endpoints**: Replace NAT Gateway → Save ~$15/month (lose flexibility)
5. **Log Retention**: Reduce to 1 day → Save ~$0.10/month
6. **ALB Deletion**: Use NLB → Save ~$5/month (lose Layer 7 features)

---

## Resource Tags

All resources are tagged with:

| Tag Key | Tag Value | Purpose |
|---------|-----------|---------|
| Project | sndk | Group resources by project |
| Environment | prod | Identify environment |
| ManagedBy | Terraform | Identify management method |
| Name | `<resource-specific>` | Human-readable identifier |

---

## Verification Commands

### Networking
```bash
# List VPCs
aws ec2 describe-vpcs --vpc-ids vpc-0e599a5815ee71e75

# List Subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0e599a5815ee71e75"

# Check NAT Gateway
aws ec2 describe-nat-gateways --nat-gateway-ids nat-05e0339850789221e

# List Security Groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-0e599a5815ee71e75"
```

### ECR
```bash
# List repositories
aws ecr describe-repositories --repository-names sndk-prod-api

# List images
aws ecr list-images --repository-name sndk-prod-api
```

### IAM
```bash
# List roles
aws iam get-role --role-name sndk-prod-ecs-task-execution-role
aws iam get-role --role-name sndk-prod-ecs-task-role
```

### Load Balancer
```bash
# Describe ALB
aws elbv2 describe-load-balancers --names sndk-prod-alb

# Check target health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:ap-south-1:654654234818:targetgroup/sndk-prod-tg/340e1856790c7f5f
```

### ECS
```bash
# List clusters
aws ecs describe-clusters --clusters sndk-prod-cluster

# List services
aws ecs describe-services --cluster sndk-prod-cluster --services sndk-prod-service

# List tasks
aws ecs list-tasks --cluster sndk-prod-cluster --service-name sndk-prod-service
```

### CloudWatch
```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix /ecs/sndk-prod

# Get recent logs
aws logs tail /ecs/sndk-prod --follow
```

---

## Resource Creation Timeline

1. **Phase 1 - Networking** (2 minutes):
   - VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables, Security Groups

2. **Phase 2 - ECR** (5 seconds):
   - ECR Repository, Lifecycle Policy

3. **Phase 3 - IAM** (3 seconds):
   - IAM Roles, IAM Policies

4. **Phase 4 - ALB** (3 minutes):
   - Application Load Balancer, Target Group, Listener

5. **Phase 5 - ECS** (2 minutes):
   - ECS Cluster, Task Definition, Service, CloudWatch Log Group

**Total Deployment Time**: ~7 minutes

---

## Cleanup Commands

To destroy all resources (in reverse order):

```bash
cd infrastructure/environments/prod

# Phase 5: ECS
terraform destroy -target=module.ecs -auto-approve

# Phase 4: ALB
terraform destroy -target=module.alb -auto-approve

# Phase 3: IAM
terraform destroy -target=module.iam -auto-approve

# Phase 2: ECR (delete images first)
aws ecr batch-delete-image --repository-name sndk-prod-api --image-ids imageTag=latest
terraform destroy -target=module.ecr -auto-approve

# Phase 1: Networking
terraform destroy -target=module.networking -auto-approve

# Or destroy everything at once
terraform destroy -auto-approve
```

**Note**: ECR images must be deleted manually before destroying the repository.

---

## Additional Resources

- **Terraform State**: Stored locally in `terraform.tfstate`
- **Terraform Lock**: Stored in `.terraform.lock.hcl`
- **AWS Console**: https://console.aws.amazon.com/
- **CloudWatch Logs**: https://console.aws.amazon.com/cloudwatch/home?region=ap-south-1#logsV2:log-groups/log-group/$252Fecs$252Fsndk-prod

---

**Last Updated**: 2025-11-18
**Total Resources**: 31
**Deployment Status**: ✅ All resources healthy and operational
