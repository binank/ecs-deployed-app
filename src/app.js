const express = require('express');
const path = require('path');
const app = express();

const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// Health check — ECS & ALB use this to verify container health
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || 'unknown',
    environment: process.env.NODE_ENV || 'production',
  });
});

// Main page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// Info API
app.get('/api/info', (req, res) => {
  res.json({
    app: 'ECS Deployed App',
    platform: 'AWS ECS Fargate',
    region: process.env.AWS_REGION || 'us-east-1',
    taskArn: process.env.ECS_CONTAINER_METADATA_URI || 'N/A',
    imageTag: process.env.IMAGE_TAG || 'latest',
    deployedAt: process.env.DEPLOY_TIME || new Date().toISOString(),
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server running on port ${PORT}`);
  console.log(`🐳 Running in Docker on ECS Fargate`);
});

module.exports = app;
