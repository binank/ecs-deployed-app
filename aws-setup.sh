#!/bin/bash
# ================================================================
# AWS ECS Infrastructure Setup Script
# Run this ONCE from your local machine with AWS CLI configured
# Prerequisites: aws cli v2, jq
# Usage: bash aws-setup.sh
# ================================================================

set -e

# ── CONFIGURATION — Edit these values ───────────────────────────
APP_NAME="my-node-app"
CLUSTER_NAME="my-app-cluster"
SERVICE_NAME="my-node-app-service"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
         --query "Vpcs[0].VpcId" --output text --region $REGION)

echo "🔧 Setting up ECS infrastructure..."
echo "   Account: $ACCOUNT_ID"
echo "   Region:  $REGION"
echo "   VPC:     $VPC_ID"

# ── STEP 1: Create ECR Repository ───────────────────────────────
echo ""
echo "📦 [1/7] Creating ECR repository..."
aws ecr create-repository \
  --repository-name $APP_NAME \
  --region $REGION \
  --image-scanning-configuration scanOnPush=true \
  2>/dev/null || echo "  (ECR repo already exists, skipping)"

ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$APP_NAME"
echo "  ECR URI: $ECR_URI"

# ── STEP 2: Create CloudWatch Log Group ─────────────────────────
echo ""
echo "📋 [2/7] Creating CloudWatch log group..."
aws logs create-log-group \
  --log-group-name "/ecs/$APP_NAME" \
  --region $REGION \
  2>/dev/null || echo "  (Log group already exists, skipping)"

# ── STEP 3: Create ECS Task Execution Role ───────────────────────
echo ""
echo "🔐 [3/7] Creating IAM ECS Task Execution Role..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document "$TRUST_POLICY" \
  2>/dev/null || echo "  (Role already exists, skipping)"

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  2>/dev/null || true

# ── STEP 4: Create ECS Cluster ───────────────────────────────────
echo ""
echo "🏗️  [4/7] Creating ECS cluster..."
aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --capacity-providers FARGATE \
  --region $REGION \
  2>/dev/null || echo "  (Cluster already exists, skipping)"

# ── STEP 5: Get Subnet IDs from default VPC ───────────────────────
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=defaultForAz,Values=true" \
  --query "Subnets[*].SubnetId" \
  --output text --region $REGION | tr '\t' ',')
echo ""
echo "🌐 [5/7] Found subnets: $SUBNET_IDS"

# ── STEP 6: Create Security Group ────────────────────────────────
echo ""
echo "🔒 [6/7] Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-sg" \
  --description "Security group for $APP_NAME ECS tasks" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" --output text 2>/dev/null) || \
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${APP_NAME}-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region $REGION)

# Allow inbound on port 3000
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 3000 --cidr 0.0.0.0/0 \
  --region $REGION 2>/dev/null || true

echo "  Security Group ID: $SG_ID"

# ── STEP 7: Register initial Task Definition ─────────────────────
echo ""
echo "📝 [7/7] Registering ECS task definition..."

# Replace placeholders in task definition file
sed -i.bak \
  "s|YOUR_ACCOUNT_ID|$ACCOUNT_ID|g; s|us-east-1|$REGION|g" \
  ecs-task-definition.json

aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition.json \
  --region $REGION

# Restore backup
mv ecs-task-definition.json.bak ecs-task-definition.json 2>/dev/null || true

# ── Create ECS Service ────────────────────────────────────────────
echo ""
echo "🚀 Creating ECS Service..."
FIRST_SUBNET=$(echo $SUBNET_IDS | cut -d',' -f1)

aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $APP_NAME \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$FIRST_SUBNET],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region $REGION \
  2>/dev/null || echo "  (Service already exists, skipping)"

echo ""
echo "══════════════════════════════════════════════════════"
echo "✅ ECS Infrastructure setup complete!"
echo ""
echo "  ECR Repository:  $ECR_URI"
echo "  ECS Cluster:     $CLUSTER_NAME"
echo "  ECS Service:     $SERVICE_NAME"
echo "  Security Group:  $SG_ID"
echo ""
echo "👉 Next Steps:"
echo "   1. Update ecs-task-definition.json:"
echo "      Replace YOUR_ACCOUNT_ID with: $ACCOUNT_ID"
echo "   2. Add GitHub Secrets:"
echo "      AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
echo "   3. Push code to main → pipeline deploys automatically!"
echo "══════════════════════════════════════════════════════"
