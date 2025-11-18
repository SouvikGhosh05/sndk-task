# Application Containerization

This directory contains a containerized Node.js Express application demonstrating Docker best practices for production deployment.

## 📋 Overview

A simple Node.js Express API that demonstrates:
- **Multi-stage Docker builds** for optimized image size
- **Security best practices** (non-root user, minimal base image)
- **Health check endpoints** for container orchestration
- **Production-ready configuration**

---

## 🏗️ Application Structure

```
application/
├── nodejs-app/
│   ├── app.js              # Express application
│   ├── package.json        # Dependencies
│   └── package-lock.json   # Lockfile
├── Dockerfile              # Multi-stage optimized build
├── .dockerignore           # Build context exclusions
└── README.md               # This file
```

---

## 🚀 Quick Start

### Prerequisites

- Docker installed (v20.10+)
- Node.js 18+ (for local development only)

### Build the Docker Image

```bash
cd /home/ubuntu/sndk-task/application
docker build -t hello-api:latest .
```

### Run the Container

```bash
docker run -d -p 3000:3000 --name hello-api hello-api:latest
```

### Test the Application

```bash
# Main endpoint
curl http://localhost:3000

# Health check endpoint
curl http://localhost:3000/health

# System info endpoint
curl http://localhost:3000/info
```

### Stop the Container

```bash
docker stop hello-api
docker rm hello-api
```

---

## 🔍 Application Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main endpoint - returns Hello World message |
| `/health` | GET | Health check endpoint for ALB/ECS |
| `/info` | GET | System information (Node version, platform, memory) |

### Example Response (/)

```json
{
  "message": "Hello World from ECS Fargate!",
  "application": "Hello API",
  "timestamp": "2025-11-16T10:20:25.487Z",
  "environment": "production",
  "version": "1.0.0",
  "region": "ap-south-1",
  "hostname": "6f7f04c3178a"
}
```

---

## 🐳 Dockerfile Best Practices Implemented

### 1. Multi-Stage Build
```dockerfile
# Stage 1: Dependencies
FROM node:20-alpine AS dependencies
# Install production dependencies only

# Stage 2: Production Runtime
FROM node:20-alpine
# Copy only runtime files
```

**Benefits:**
- ✅ Smaller final image (no build tools)
- ✅ Faster builds (cached dependency layer)
- ✅ Clear separation of concerns

### 2. Minimal Base Image
- Using **Alpine Linux** (`node:20-alpine`)
- Image size: **~197MB** (vs ~1GB for full Node.js image)
- Reduced attack surface

### 3. Non-Root User
```dockerfile
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs
USER nodejs
```

**Security:**
- ✅ Container runs as user `nodejs` (UID 1001)
- ✅ Not running as root (prevents privilege escalation)
- ✅ Follows principle of least privilege

### 4. Proper Signal Handling
```dockerfile
RUN apk add --no-cache dumb-init
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "app.js"]
```

**Benefits:**
- ✅ Proper PID 1 signal forwarding
- ✅ Graceful shutdown on SIGTERM/SIGINT
- ✅ Prevents zombie processes

### 5. Docker Health Check
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', ...)"
```

**Benefits:**
- ✅ Container orchestration knows container health
- ✅ Auto-restart unhealthy containers
- ✅ Better monitoring and alerting

### 6. Optimized Layer Caching
- Package files copied before application code
- Dependencies installed in separate stage
- `.dockerignore` excludes unnecessary files

---

## 📦 Image Optimization

### Image Size Comparison

| Approach | Image Size | Notes |
|----------|------------|-------|
| `node:20` (full) | ~1.1 GB | Includes full OS, dev tools |
| `node:20-alpine` | ~150 MB | Minimal Alpine base |
| **Our multi-stage** | **~197 MB** | Alpine + production deps only |

### What We Excluded

The `.dockerignore` file prevents these from entering the image:
- `node_modules/` (reinstalled in Dockerfile)
- `.git/` and Git files
- IDE configuration (`.vscode/`, `.idea/`)
- Test files and documentation
- Environment files (`.env`)
- Log files

---

## 🔒 Security Features

### 1. Non-Root Execution
```bash
# Verify non-root user
docker exec hello-api whoami
# Output: nodejs
```

### 2. No Secrets in Image
- No hardcoded credentials
- Environment variables used for configuration
- `.dockerignore` prevents `.env` files from being copied

### 3. Minimal Attack Surface
- Alpine Linux (minimal packages)
- Only production dependencies
- No unnecessary binaries or shells in final image

### 4. Security Scanning Ready
```bash
# Scan with Docker Scout (if available)
docker scout cves hello-api:latest

# Or use Trivy
trivy image hello-api:latest
```

---

## 🛠️ Local Development

### Run Without Docker

```bash
cd nodejs-app
npm install
npm start
```

### Development with Hot Reload

```bash
npm install -g nodemon
nodemon app.js
```

---

## 📊 Verification Checklist

- ✅ Image builds successfully
- ✅ Image size < 200MB
- ✅ Container runs without errors
- ✅ Application responds on port 3000
- ✅ Health check passes
- ✅ Runs as non-root user
- ✅ Graceful shutdown works
- ✅ No vulnerabilities in base image

---

## 🔧 Troubleshooting

### Container exits immediately
```bash
# Check logs
docker logs hello-api

# Common cause: Port already in use
lsof -i :3000
```

### Permission denied errors
```bash
# Ensure running as non-root
docker exec hello-api id
# Should show uid=1001(nodejs)
```

### Image build fails
```bash
# Clear Docker cache
docker builder prune

# Rebuild from scratch
docker build --no-cache -t hello-api:latest .
```

---

## 📚 References

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Node.js Docker Guide](https://nodejs.org/en/docs/guides/nodejs-docker-webapp/)
- [Alpine Linux](https://alpinelinux.org/)
- [dumb-init](https://github.com/Yelp/dumb-init)
