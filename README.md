# SNDK Task - ECS Fargate Infrastructure

Production-ready containerized application infrastructure on AWS ECS Fargate, deployed using Terraform with infrastructure-as-code best practices.

## Overview

This project demonstrates a complete AWS ECS Fargate deployment with:
- **Containerized Node.js application** running on ECS Fargate
- **Multi-AZ high availability** across 2 availability zones
- **Private subnet architecture** for enhanced security
- **Auto-scaling capable** infrastructure with load balancing
- **Infrastructure as Code** using Terraform with modular design

## Architecture Summary

```
Internet
   │
   ├─→ [Internet Gateway] ──→ [ALB] (Public Subnets)
   │                            │
   │                            ├─→ [ECS Task 1] (Private Subnet 1a)
   │                            └─→ [ECS Task 2] (Private Subnet 1b)
   │
   └─→ [Internet Gateway] ──→ [NAT Gateway] ←── [ECS Tasks]
                                                 (Outbound Internet Access)
```

### Traffic Flows

**Inbound (User → Application):**
```
Internet User → ALB → ECS Tasks (Private Subnets)
```

**Outbound (Application → Internet):**
```
ECS Tasks → NAT Gateway → Internet Gateway → Internet
```

## Quick Start

### Prerequisites
- AWS CLI v2 configured with credentials
- Terraform v1.10.3+
- Docker installed
- AWS account with admin access

### Deployment

```bash
# 1. Build and push Docker image
cd application
docker build -t hello-api:latest -f Dockerfile .
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com
docker tag hello-api:latest <account-id>.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest
docker push <account-id>.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest

# 2. Deploy infrastructure (phased approach)
cd ../infrastructure/environments/prod
terraform init
terraform apply -target=module.networking -auto-approve
terraform apply -target=module.ecr -auto-approve
terraform apply -target=module.iam -auto-approve
terraform apply -target=module.alb -auto-approve
terraform apply -target=module.ecs -auto-approve

# 3. Access application
curl http://<alb-dns-name>/
```

### Application URLs

After deployment, access your application at:
- **Main Endpoint**: `http://sndk-prod-alb-<id>.ap-south-1.elb.amazonaws.com/`
- **Health Check**: `http://sndk-prod-alb-<id>.ap-south-1.elb.amazonaws.com/health`
- **System Info**: `http://sndk-prod-alb-<id>.ap-south-1.elb.amazonaws.com/info`

## Directory Structure

```
sndk-task/
├── application/              # Containerized Node.js application
│   ├── Dockerfile           # Multi-stage Docker build
│   ├── .dockerignore
│   └── nodejs-app/          # Express.js application
│       ├── app.js
│       └── package.json
│
├── infrastructure/          # Terraform infrastructure code
│   ├── modules/            # Reusable Terraform modules
│   │   ├── networking/     # VPC, subnets, NAT, security groups
│   │   ├── ecr/           # Container registry
│   │   ├── iam/           # IAM roles and policies
│   │   ├── alb/           # Application Load Balancer
│   │   └── ecs/           # ECS cluster, service, tasks
│   └── environments/
│       └── prod/          # Production environment configuration
│
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md    # Architecture decisions and strategy
│   └── RESOURCES.md       # Complete resource inventory
│
└── README.md              # This file
```

## Key Features

### High Availability
- **Multi-AZ Deployment**: Resources distributed across ap-south-1a and ap-south-1b
- **2 ECS Tasks**: Running simultaneously for redundancy
- **Auto-healing**: ECS automatically replaces failed tasks
- **Load Balancing**: ALB distributes traffic across healthy tasks

### Security
- **Private Subnets**: ECS tasks have no public IP addresses
- **Network Isolation**: Tasks accessible only through ALB
- **Security Groups**: Restrictive ingress, permissive egress
- **IAM Least Privilege**: Separate execution and task roles
- **Container Scanning**: ECR scans images on push

### Scalability
- **Fargate**: Serverless compute, no EC2 management
- **Auto-scaling Ready**: Infrastructure supports ECS auto-scaling
- **Stateless Design**: Tasks can scale horizontally
- **Container Insights**: Monitoring and metrics enabled

## Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Cloud Provider** | AWS | - |
| **Region** | ap-south-1 (Mumbai) | - |
| **Infrastructure as Code** | Terraform | v1.10.3 |
| **AWS Provider** | hashicorp/aws | ~> 6.0 |
| **Container Runtime** | Docker | - |
| **Application** | Node.js | v20 (Alpine) |
| **Framework** | Express.js | v4.18.2 |
| **Compute** | AWS ECS Fargate | - |
| **Container Registry** | AWS ECR | - |
| **Load Balancer** | AWS ALB | - |
| **Networking** | VPC, NAT Gateway | - |
| **Logging** | CloudWatch Logs | 7-day retention |

## Resources Created

**Total: 31 AWS Resources**

| Category | Count | Key Resources |
|----------|-------|---------------|
| **Networking** | 21 | VPC, 4 Subnets, NAT Gateway, IGW, Route Tables, Security Groups |
| **Container** | 2 | ECR Repository, Lifecycle Policy |
| **IAM** | 5 | 2 Roles, 3 Policies |
| **Load Balancer** | 3 | ALB, Target Group, Listener |
| **ECS** | 4 | Cluster, Service, Task Definition, Log Group |

See [docs/RESOURCES.md](docs/RESOURCES.md) for complete inventory.

## Strategy & Design Decisions

### 1. NAT Gateway vs VPC Endpoints
**Decision**: Use NAT Gateway instead of VPC Endpoints

**Rationale**:
- Containers may need general internet access beyond just ECR/CloudWatch
- NAT Gateway provides unrestricted outbound access
- Simpler configuration and troubleshooting
- Future-proof for additional external API calls

**Trade-off**: Slightly higher cost (~$35/month) but greater flexibility

### 2. Private Subnet Architecture
**Decision**: Deploy ECS tasks in private subnets without public IPs

**Rationale**:
- **Security**: Tasks not directly accessible from internet
- **Attack Surface**: Reduced exposure to threats
- **Compliance**: Aligns with security best practices
- **Access Control**: All traffic must go through ALB

**Implementation**: NAT Gateway provides outbound internet access

### 3. Two ECS Tasks
**Decision**: Run 2 tasks instead of 1

**Rationale**:
- **High Availability**: One task per AZ (ap-south-1a, ap-south-1b)
- **Zero Downtime**: Rolling deployments without service interruption
- **Load Distribution**: Better performance under load
- **Fault Tolerance**: Service continues if one AZ fails

**Cost**: $10/month vs $5/month for single task

### 4. Security Group Strategy
**Decision**: Restrictive ingress, permissive egress

**Ingress**: ECS accepts connections ONLY from ALB security group on port 3000
**Egress**: ECS can connect to 0.0.0.0/0 (all destinations)

**Rationale**:
- Security enforced at ingress (who can connect to you)
- Egress needed for: ECR image pulls, CloudWatch logs, external APIs
- Stateful connections automatically allow response traffic

### 5. Modular Terraform Structure
**Decision**: Separate modules for each component

**Modules**: networking, ecr, iam, alb, ecs

**Benefits**:
- **Reusability**: Modules can be used across environments
- **Maintainability**: Changes isolated to specific modules
- **Testing**: Deploy and test modules independently
- **Phased Deployment**: Validate each layer before proceeding

### 6. Phased Deployment Approach
**Decision**: Use `-target` flag for incremental deployment

**Phases**:
1. Networking (VPC, subnets, NAT, security groups)
2. ECR (container registry)
3. IAM (roles and policies)
4. ALB (load balancer)
5. ECS (cluster, service, tasks)

**Benefits**:
- **Validation**: Test each layer before proceeding
- **Troubleshooting**: Easier to identify issues
- **Learning**: Understand dependencies between components

## Cost Estimation

**Estimated Monthly Cost**: ~$50-60 USD

| Resource | Cost/Month |
|----------|-----------|
| NAT Gateway | ~$32 |
| ECS Fargate (2 tasks, 0.25 vCPU, 0.5 GB) | ~$10 |
| ALB | ~$16 |
| ECR Storage | ~$1 |
| CloudWatch Logs | ~$1 |
| Data Transfer | Variable |

*Costs are estimates for ap-south-1 region. Actual costs may vary.*

## Monitoring & Logs

### CloudWatch Logs
- **Log Group**: `/ecs/sndk-prod`
- **Retention**: 7 days
- **Stream Prefix**: `ecs`

### Container Insights
- Enabled on ECS cluster
- Metrics for CPU, memory, network usage

### Health Checks
- **ALB Health Checks**: `/health` endpoint every 30 seconds
- **Container Health Checks**: wget to localhost:3000/health

## Next Steps / Future Enhancements

1. **Auto-scaling**: Configure ECS service auto-scaling based on CPU/memory
2. **HTTPS**: Add ACM certificate and HTTPS listener to ALB
3. **Custom Domain**: Route53 domain with friendly DNS name
4. **CI/CD**: GitHub Actions or AWS CodePipeline for automated deployments
5. **Monitoring**: CloudWatch alarms for health checks, CPU, memory
6. **Backup**: Automated ECR image lifecycle policies
7. **Secrets**: AWS Secrets Manager for sensitive configuration
8. **WAF**: AWS WAF for application-layer protection
9. **Multi-Environment**: Staging and development environments
10. **Database**: RDS for stateful data storage

## Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed architecture and design decisions
- **[RESOURCES.md](docs/RESOURCES.md)** - Complete AWS resource inventory
- **[application/README.md](application/README.md)** - Application-specific documentation

## License

This project is for educational and assessment purposes.

## Author

Infrastructure provisioned as part of DevOps practical assessment.
