# =============================================================================
# Multi-Stage Dockerfile for Node.js Application
# Optimized for security, performance, and minimal image size
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Dependencies (Build Stage)
# Purpose: Install production dependencies in a separate stage
# -----------------------------------------------------------------------------
FROM node:20-alpine AS dependencies

# Set working directory
WORKDIR /app

# Copy package files
COPY nodejs-app/package*.json ./

# Install production dependencies only
# --production flag ensures dev dependencies are not installed
# npm ci for clean install (faster and more reliable than npm install)
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# -----------------------------------------------------------------------------
# Stage 2: Production (Runtime Stage)
# Purpose: Create minimal production image with only necessary files
# -----------------------------------------------------------------------------
FROM node:20-alpine

# Add metadata labels (best practice for container management)
LABEL maintainer="hello-api"
LABEL description="Node.js Express API for ECS Fargate"
LABEL version="1.0.0"

# Install dumb-init for proper signal handling
# dumb-init ensures proper process signal forwarding (PID 1 problem)
RUN apk add --no-cache dumb-init

# Create non-root user and group for security
# Running as non-root is a security best practice
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Copy node_modules from dependencies stage
# --from=dependencies copies only from the build stage
# --chown ensures files are owned by nodejs user
COPY --from=dependencies --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application code
COPY --chown=nodejs:nodejs nodejs-app/package*.json ./
COPY --chown=nodejs:nodejs nodejs-app/app.js ./

# Switch to non-root user
# All subsequent commands and container runtime will use this user
USER nodejs

# Expose application port
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000

# Health check (Docker native health checking)
# This is optional but good practice for container orchestration
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use dumb-init as PID 1 to handle signals properly
# This ensures graceful shutdowns work correctly
ENTRYPOINT ["dumb-init", "--"]

# Run the application
CMD ["node", "app.js"]
