const express = require('express');
const app = express();

// Configuration
const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';

// Middleware for JSON parsing
app.use(express.json());

// Main route
app.get('/', (req, res) => {
  res.json({
    message: 'Hello World from ECS Fargate!',
    application: 'Hello API',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'production',
    version: '1.0.0',
    region: process.env.AWS_REGION || 'ap-south-1',
    hostname: require('os').hostname()
  });
});

// Health check endpoint (required for ALB target group)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Additional info endpoint
app.get('/info', (req, res) => {
  res.json({
    nodeVersion: process.version,
    platform: process.platform,
    architecture: process.arch,
    memory: {
      total: Math.round(require('os').totalmem() / 1024 / 1024) + ' MB',
      free: Math.round(require('os').freemem() / 1024 / 1024) + ' MB'
    },
    cpus: require('os').cpus().length
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path,
    message: 'The requested resource was not found'
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Error:', err.message);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message
  });
});

// Start server
app.listen(PORT, HOST, () => {
  console.log(`✓ Server is running on http://${HOST}:${PORT}`);
  console.log(`✓ Environment: ${process.env.NODE_ENV || 'production'}`);
  console.log(`✓ Node version: ${process.version}`);
  console.log(`✓ Health check available at: http://${HOST}:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT signal received: closing HTTP server');
  process.exit(0);
});
