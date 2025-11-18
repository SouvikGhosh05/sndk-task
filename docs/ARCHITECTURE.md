# Architecture & Design Decisions

This document explains the architectural decisions, strategy, and logic behind the SNDK Task infrastructure deployment.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Network Architecture](#network-architecture)
- [Design Decisions](#design-decisions)
- [Data Flow Diagrams](#data-flow-diagrams)
- [Security Model](#security-model)
- [Deployment Strategy](#deployment-strategy)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │
        ┌────────────────┴────────────────┐
        │                                 │
        │ INBOUND (Users → App)          │ OUTBOUND (App → Internet)
        ↓                                 ↑
┌───────────────┐                  ┌──────────────┐
│Internet Gateway                  │Internet Gateway
└───────┬───────┘                  └──────┬───────┘
        │                                 │
        │                          ┌──────▼──────┐
┌───────▼───────┐                  │ NAT Gateway │
│     ALB       │                  │  (Public)   │
│ (Public Subnets)                 └──────┬──────┘
└───────┬───────┘                         │
        │                                 │
        │  ┌──────────────────────────────┘
        │  │
        │  │  VPC: 10.0.0.0/16 (ap-south-1)
        │  │
   ─────┴──┴───────────────────────────────────────
        │  │
        │  │
   ┌────▼──▼────┐              ┌────────────┐
   │ ECS Task 1 │              │ ECS Task 2 │
   │ 10.0.11.174│              │ 10.0.12.15 │
   │(Private 1a)│              │(Private 1b)│
   └────────────┘              └────────────┘
```

### Component Breakdown

| Component | Purpose | Location |
|-----------|---------|----------|
| **VPC** | Isolated network environment | 10.0.0.0/16 |
| **Internet Gateway** | Gateway for internet traffic | Attached to VPC |
| **NAT Gateway** | Outbound internet for private resources | Public Subnet 1a |
| **ALB** | Load balancer for incoming traffic | Public Subnets |
| **ECS Tasks** | Containerized application | Private Subnets |
| **ECR** | Container image registry | AWS Managed Service |
| **CloudWatch** | Logging and monitoring | AWS Managed Service |

---

## Network Architecture

### VPC Design

**CIDR Block**: 10.0.0.0/16 (65,536 IP addresses)

**Subnet Strategy**:

| Subnet Type | CIDR | AZ | Purpose | Public IP |
|-------------|------|-----|---------|-----------|
| Public 1 | 10.0.1.0/24 | ap-south-1a | NAT Gateway, ALB | ✓ Yes |
| Public 2 | 10.0.2.0/24 | ap-south-1b | ALB | ✓ Yes |
| Private 1 | 10.0.11.0/24 | ap-south-1a | ECS Tasks | ✗ No |
| Private 2 | 10.0.12.0/24 | ap-south-1b | ECS Tasks | ✗ No |

### Route Tables

**Public Route Table**:
```
Destination      Target
10.0.0.0/16  →  local (VPC)
0.0.0.0/0    →  Internet Gateway
```

**Private Route Table**:
```
Destination      Target
10.0.0.0/16  →  local (VPC)
0.0.0.0/0    →  NAT Gateway
```

### Subnet Allocation Logic

**Why 10.0.x.0/24 subnets?**
- Each /24 provides 251 usable IPs (256 - 5 AWS reserved)
- Sufficient for: ALB ENIs, NAT Gateway, ECS tasks
- Room for growth without re-subnetting

**Why separate public/private subnets?**
- **Security**: Isolate workloads from direct internet access
- **Compliance**: Align with security best practices
- **Flexibility**: Different routing for different use cases

**Why IP ranges 10.0.1.x vs 10.0.11.x?**
- Visual distinction: 1-9 = public, 11-19 = private
- Easy identification in AWS console
- Future expansion: 21-29 for databases, 31-39 for cache, etc.

---

## Design Decisions

### 1. NAT Gateway vs VPC Endpoints

**Decision**: ✅ Use NAT Gateway

**Alternatives Considered**:
- ❌ VPC Endpoints (for ECR, CloudWatch, S3)
- ❌ No internet access (highly restrictive)

**Rationale**:

| Factor | NAT Gateway | VPC Endpoints |
|--------|-------------|---------------|
| **Flexibility** | Access ANY internet service | Only specific AWS services |
| **Use Cases** | ECR, CloudWatch, npm, APIs | ECR, CloudWatch, S3 only |
| **Configuration** | Simple (one gateway) | Multiple endpoints needed |
| **Cost** | ~$35/month | ~$7/endpoint/month × 3 = $21 |
| **Future-proof** | Can add new services freely | Need new endpoint per service |

**Why we chose NAT Gateway**:
1. Containers might need npm packages from registry.npmjs.org
2. Future API integrations (payment gateways, third-party services)
3. Simpler troubleshooting (standard internet connectivity)
4. Operational flexibility outweighs marginal cost difference

---

### 2. Private Subnet Architecture for ECS Tasks

**Decision**: ✅ Deploy ECS tasks in private subnets (NO public IP)

**Alternatives Considered**:
- ❌ Public subnet with public IP
- ❌ Mixed (some tasks public, some private)

**Rationale**:

**Security Benefits**:
```
Public Subnet (Rejected)          Private Subnet (Chosen)
─────────────────────              ────────────────────────
Internet → Task (Direct)           Internet → ALB → Task
❌ Direct exposure                 ✓ ALB filters traffic
❌ DDoS vulnerability              ✓ DDoS protection via ALB
❌ Port scanning risk              ✓ Hidden from scanners
```

**Access Pattern**:
- **Inbound**: Users → ALB → Tasks (controlled)
- **Outbound**: Tasks → NAT → Internet (allowed)

**Why this works**:
1. **Defense in Depth**: Multiple security layers (SG, subnet, ALB)
2. **Compliance**: Many regulations require private subnets
3. **Attack Surface**: Reduced exposure = fewer vulnerabilities
4. **Cost**: No NAT traversal charges for inbound (via ALB)

**Trade-off**: Need NAT Gateway for outbound (~$35/month), but worth it for security

---

### 3. Two ECS Tasks Strategy

**Decision**: ✅ Run 2 tasks across 2 AZs

**Alternatives Considered**:
- ❌ 1 task (cheaper, no HA)
- ❌ 3+ tasks (over-provisioned for demo)

**Rationale**:

**High Availability Architecture**:
```
Scenario: AZ-A Failure

Before:                          After AZ-A Failure:
┌─────────┐  ┌─────────┐         ┌─────────┐  ┌─────────┐
│ Task 1  │  │ Task 2  │         │ Task 1  │  │ Task 2  │
│  AZ-A   │  │  AZ-B   │   →     │  FAILED │  │  AZ-B   │
│ Active  │  │ Active  │         │    ❌   │  │ Active  │
└─────────┘  └─────────┘         └─────────┘  └─────────┘
     ↓             ↓                                ↓
  50% load     50% load                         100% load
                                              (Still serving!)
```

**Benefits**:

1. **Zero-Downtime Deployments**:
```
Old Version:          Deployment:           New Version:
Task 1, Task 2   →   Task 3, Task 4    →   Task 3, Task 4
(running)            (new starting)         (running)
                     Task 1, Task 2
                     (draining)
```

2. **Load Distribution**:
- Each task handles ~50% of traffic
- Better response times under load
- No single point of failure

3. **Cost vs Reliability**:
- 1 task = $5/mo, 0% redundancy ❌
- 2 tasks = $10/mo, 100% redundancy ✓
- 3 tasks = $15/mo, overkill for this scale

**Task Placement**:
- Task 1: Private Subnet 1a (ap-south-1a)
- Task 2: Private Subnet 1b (ap-south-1b)
- ECS automatically distributes across AZs

---

### 4. Security Group Strategy

**Decision**: ✅ Restrictive Ingress + Permissive Egress

**Configuration**:

**ALB Security Group**:
```
Ingress:
  - Port 80 (HTTP) from 0.0.0.0/0
  - Port 443 (HTTPS) from 0.0.0.0/0

Egress:
  - All ports, all protocols to 0.0.0.0/0
```

**ECS Security Group**:
```
Ingress:
  - Port 3000 (TCP) from ALB Security Group ONLY

Egress:
  - All ports, all protocols to 0.0.0.0/0
```

**Why This Strategy?**

**Ingress = Who Can Connect TO You (RESTRICTIVE)**:
- ECS accepts connections ONLY from ALB
- No direct internet access to ECS
- If someone bypasses ALB, connection rejected

**Egress = Where You Can Connect TO (PERMISSIVE)**:
- ECS needs to pull Docker images (ECR)
- ECS needs to write logs (CloudWatch)
- ECS might call external APIs
- Future flexibility without firewall changes

**Common Misconception**:
> "Why not restrict ECS egress to only ALB?"

**Answer**:
- Response traffic is STATEFUL (automatically allowed)
- ECS doesn't initiate connections to ALB
- ALB initiates → ECS responds (automatic)
- Egress needed for ECR, CloudWatch, internet

---

### 5. Modular Terraform Structure

**Decision**: ✅ Separate modules per component

**Structure**:
```
infrastructure/
├── modules/
│   ├── networking/    # VPC, subnets, NAT, security groups
│   ├── ecr/          # Container registry
│   ├── iam/          # Roles and policies
│   ├── alb/          # Load balancer
│   └── ecs/          # Cluster, service, tasks
└── environments/
    └── prod/         # Production configuration
```

**Benefits**:

1. **Reusability**:
```
environments/
├── prod/      # Uses modules with prod values
├── staging/   # Same modules, staging values
└── dev/       # Same modules, dev values
```

2. **Maintainability**:
- Change networking? Edit one module
- All environments inherit the change
- Single source of truth

3. **Testing**:
- Deploy modules independently
- Test in isolation
- Easier troubleshooting

4. **Collaboration**:
- Different team members own different modules
- Clear boundaries and responsibilities

**Module Dependencies**:
```
networking → ecr, iam, alb, ecs
ecr → ecs
iam → ecs
alb → ecs
```

---

## Data Flow Diagrams

### 1. Inbound Traffic Flow (User Accessing Application)

```
Step 1: DNS Resolution
   User Browser
      ↓
   DNS Query: sndk-prod-alb-1451949546.ap-south-1.elb.amazonaws.com
      ↓
   Returns: ALB Public IP (e.g., 13.200.x.x)

Step 2: Request to ALB
   User (Internet)
      ↓
   HTTP GET / to 13.200.x.x:80
      ↓
   Internet Gateway (receives packet)
      ↓
   ALB (in public subnet: 10.0.1.x)

Step 3: ALB Routes to ECS
   ALB checks target group health
      ↓
   Selects healthy target: 10.0.11.174:3000 or 10.0.12.15:3000
      ↓
   Routes WITHIN VPC (no internet hop!)
      ↓
   ECS Task (in private subnet)

Step 4: Response Path
   ECS Task generates response
      ↓
   Sends to ALB (stateful, allowed automatically)
      ↓
   ALB aggregates response
      ↓
   Sends to user via Internet Gateway
```

**Key Points**:
- ALB → ECS uses VPC internal routing (route: 10.0.0.0/16 → local)
- No internet gateway involved for internal traffic
- Response traffic automatic (security groups are stateful)

---

### 2. Outbound Traffic Flow (ECS Pulling Docker Image)

```
Step 1: ECS Task Needs Image
   ECS Service: "Start new task"
      ↓
   Task Definition specifies: 654654234818.dkr.ecr.ap-south-1.amazonaws.com/sndk-prod-api:latest
      ↓
   ECS Task (10.0.11.174) needs to pull image

Step 2: Check Route Table
   Destination: ECR (internet endpoint)
      ↓
   Route Table lookup: 0.0.0.0/0 → NAT Gateway
      ↓
   Packet sent to NAT Gateway

Step 3: NAT Translation
   Source IP: 10.0.11.174 (private)
      ↓
   NAT Gateway translates
      ↓
   New Source IP: 13.126.79.113 (Elastic IP)

Step 4: Internet Gateway
   Packet from NAT (13.126.79.113) → Internet Gateway
      ↓
   Internet Gateway forwards to internet
      ↓
   ECR receives request from 13.126.79.113

Step 5: Response Path
   ECR sends image layers to 13.126.79.113
      ↓
   Internet Gateway → NAT Gateway
      ↓
   NAT Gateway translates back to 10.0.11.174
      ↓
   ECS Task receives image
```

**Key Points**:
- NAT Gateway is in PUBLIC subnet (needs internet access)
- NAT Gateway has Elastic IP (static public IP)
- All private subnet outbound traffic uses NAT's IP
- Response traffic tracked by NAT (stateful)

---

### 3. ECS Task Startup Flow

```
1. Terraform Apply
      ↓
   ECS Service created with desired_count = 2
      ↓
   ECS Scheduler: "Need to start 2 tasks"

2. Task Placement
      ↓
   Scheduler selects:
      - 1 task in ap-south-1a (subnet: 10.0.11.0/24)
      - 1 task in ap-south-1b (subnet: 10.0.12.0/24)

3. IAM Role Assumption
      ↓
   Task assumes Task Execution Role
      ↓
   Gets credentials to access ECR, CloudWatch

4. Image Pull
      ↓
   Task: "Need to pull image from ECR"
      ↓
   Uses NAT Gateway → Internet Gateway → ECR
      ↓
   Downloads: 654654...ecr.../sndk-prod-api:latest (~48 MB)

5. Container Start
      ↓
   Docker runtime starts container
      ↓
   Container: "Listening on 0.0.0.0:3000"
      ↓
   Health check: wget http://localhost:3000/health

6. Target Group Registration
      ↓
   ECS registers task IP with ALB target group
      ↓
   Target Group: "New target 10.0.11.174:3000"
      ↓
   Starts health checks every 30 seconds

7. Healthy State
      ↓
   2 consecutive health checks pass
      ↓
   Target marked "healthy"
      ↓
   ALB starts sending traffic
```

---

## Security Model

### Defense in Depth Strategy

```
Layer 1: Network Isolation
   ├─ Private subnets (no public IP)
   ├─ VPC isolation
   └─ Route table restrictions

Layer 2: Security Groups (Stateful Firewall)
   ├─ ALB SG: Allow 80/443 from internet
   ├─ ECS SG: Allow 3000 from ALB SG only
   └─ Default deny all other traffic

Layer 3: Load Balancer
   ├─ DDoS protection
   ├─ SSL termination (future)
   └─ Health check filtering

Layer 4: IAM (Identity & Access)
   ├─ Task Execution Role (ECR, CloudWatch)
   ├─ Task Role (Application runtime)
   └─ Least privilege policies

Layer 5: Container Security
   ├─ Non-root user in Docker
   ├─ Image scanning (ECR)
   └─ Read-only root filesystem (future)

Layer 6: Monitoring & Logging
   ├─ CloudWatch Logs (all requests)
   ├─ Container Insights (metrics)
   └─ ALB access logs (future)
```

### IAM Least Privilege

**Two Separate Roles**:

**Task Execution Role** (Used by ECS Agent):
```
Permissions:
  - ecr:GetAuthorizationToken
  - ecr:BatchGetImage
  - ecr:GetDownloadUrlForLayer
  - logs:CreateLogGroup
  - logs:CreateLogStream
  - logs:PutLogEvents

Principal: ecs-tasks.amazonaws.com
```

**Task Role** (Used by Application):
```
Permissions:
  - logs:PutLogEvents (application logs)

Principal: ecs-tasks.amazonaws.com
```

**Why Separate?**:
- Infrastructure operations vs application operations
- Principle of least privilege
- Easier auditing and troubleshooting
- Security best practice

---

## Deployment Strategy

### Phased Deployment Approach

**Decision**: Deploy modules incrementally using `-target` flag

**Phases**:
```
Phase 1: Networking
   terraform apply -target=module.networking
   → Creates: VPC, subnets, NAT, security groups
   → Validation: Check NAT gateway has Elastic IP

Phase 2: ECR
   terraform apply -target=module.ecr
   → Creates: ECR repository
   → Validation: Push Docker image, verify

Phase 3: IAM
   terraform apply -target=module.iam
   → Creates: IAM roles and policies
   → Validation: Check role trust relationships

Phase 4: ALB
   terraform apply -target=module.alb
   → Creates: ALB, target group, listener
   → Validation: Check ALB DNS resolves

Phase 5: ECS
   terraform apply -target=module.ecs
   → Creates: Cluster, service, task definition
   → Validation: Check tasks running, health checks passing
```

**Benefits**:
1. **Incremental Validation**: Test each layer works before proceeding
2. **Faster Troubleshooting**: Isolate issues to specific phase
3. **Learning**: Understand dependencies between components
4. **Rollback**: Easier to destroy/recreate specific components

**Why Not Single Apply?**:
- Large blast radius if something fails
- Harder to identify which component failed
- Less educational value
- All-or-nothing approach risky for complex infra

---

## Summary

This architecture provides:
- ✅ **Security**: Defense in depth with multiple layers
- ✅ **Availability**: Multi-AZ deployment with redundancy
- ✅ **Scalability**: Auto-scaling capable infrastructure
- ✅ **Maintainability**: Modular, reusable Terraform code
- ✅ **Observability**: CloudWatch logging and monitoring
- ✅ **Cost-Effective**: ~$50/month for production-grade setup

The design balances security, reliability, and operational simplicity while maintaining flexibility for future enhancements.
