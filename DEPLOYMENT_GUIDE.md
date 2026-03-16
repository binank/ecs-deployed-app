# 🐳 Deploy Node.js App on AWS ECS Fargate with GitHub Actions
## Complete Step-by-Step Guide

---

## 🏗️ Architecture Overview

```
Developer
    │
    │  git push to main
    ▼
GitHub Repository
    │
    ├─ Job 1: Run Tests (Jest)
    │
    └─ Job 2: Build & Push Docker Image
              │
              ▼
       Amazon ECR
    (Elastic Container Registry)
              │
              └─ Job 3: Deploy to ECS
                        │
                        ▼
              ┌─────────────────────┐
              │   ECS Cluster       │
              │  ┌───────────────┐  │
              │  │  ECS Service  │  │
              │  │  (Fargate)    │  │
              │  │  ┌─────────┐  │  │
              │  │  │  Task   │  │  │
              │  │  │ (Docker │  │  │
              │  │  │container│  │  │
              │  │  └─────────┘  │  │
              │  └───────────────┘  │
              └─────────────────────┘
                        │
                   Public IP:3000
                 (or ALB on port 80)
```

**Key AWS Services Used:**
- **ECR** — Stores Docker images (like Docker Hub but private in AWS)
- **ECS** — Runs containers in the cloud
- **Fargate** — Serverless compute for containers (no EC2 to manage)
- **CloudWatch** — Container logs
- **IAM** — Permissions

---

## 📁 Project Structure

```
ecs-app/
├── .github/
│   └── workflows/
│       └── deploy.yml            ← CI/CD pipeline (3 jobs)
├── src/
│   └── app.js                    ← Express server
├── public/
│   └── index.html                ← Frontend
├── Dockerfile                    ← Multi-stage Docker build
├── .dockerignore
├── ecs-task-definition.json      ← ECS task config (edit once)
├── aws-setup.sh                  ← One-time AWS infra setup
├── app.test.js
└── package.json
```

---

## STEP 1 — Prerequisites

Install these on your local machine:

### 1.1 — AWS CLI v2
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Verify
aws --version   # aws-cli/2.x.x
```

### 1.2 — Docker Desktop
Download from: https://www.docker.com/products/docker-desktop/
```bash
docker --version   # Docker version 24.x.x
```

### 1.3 — Configure AWS CLI
```bash
aws configure
```
Enter when prompted:
```
AWS Access Key ID:     [your key]
AWS Secret Access Key: [your secret]
Default region:        us-east-1
Default output format: json
```

> Get your Access Key from: AWS Console → IAM → Users → Your User → Security Credentials → Create Access Key

---

## STEP 2 — Create GitHub Repository & Push Code

```bash
# Create repo on GitHub, then:
git clone https://github.com/YOUR_USERNAME/ecs-deployed-app.git
cd ecs-deployed-app

# Copy all project files into this folder, then:
git add .
git commit -m "Initial ECS app setup"
git push origin main
```

---

## STEP 3 — Edit the Task Definition File

Open `ecs-task-definition.json` and replace the two placeholders:

```bash
# Get your AWS Account ID
aws sts get-caller-identity --query Account --output text
# Output: 123456789012
```

Replace in the file:
```
YOUR_ACCOUNT_ID  →  123456789012
```

Your ECR image line will look like:
```json
"image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:latest"
```

Also update these if needed:
```json
"executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
"taskRoleArn":      "arn:aws:iam::123456789012:role/ecsTaskRole"
```

---

## STEP 4 — Run the AWS Infrastructure Setup Script

This creates all the AWS resources in one go:

```bash
chmod +x aws-setup.sh
bash aws-setup.sh
```

**What it creates:**

| Resource | Name | Purpose |
|----------|------|---------|
| ECR Repository | `my-node-app` | Stores Docker images |
| CloudWatch Log Group | `/ecs/my-node-app` | Container logs |
| IAM Role | `ecsTaskExecutionRole` | ECS permission to pull images |
| ECS Cluster | `my-app-cluster` | Groups your services |
| Security Group | `my-node-app-sg` | Allows traffic on port 3000 |
| ECS Service | `my-node-app-service` | Keeps 1 task always running |

> ⚠️ You can also create these manually in the AWS Console (see Step 4b below)

### Step 4b — Manual Setup (Alternative to the script)

#### 4b.1 — Create ECR Repository
```
AWS Console → ECR → Create Repository
Name: my-node-app
Image scanning: Enable
Click: Create
```

#### 4b.2 — Create ECS Cluster
```
AWS Console → ECS → Clusters → Create Cluster
Cluster name: my-app-cluster
Infrastructure: AWS Fargate (serverless)
Click: Create
```

#### 4b.3 — Create IAM Role for ECS
```
AWS Console → IAM → Roles → Create Role
Trusted entity: AWS Service → Elastic Container Service → ECS Task
Attach policy: AmazonECSTaskExecutionRolePolicy
Role name: ecsTaskExecutionRole
Click: Create Role
```

#### 4b.4 — Register Task Definition
```
AWS Console → ECS → Task Definitions → Create new
Launch type: Fargate
OS/Arch: Linux/x86_64
CPU: 0.25 vCPU | Memory: 0.5 GB
Container name: my-node-app
Image URI: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:latest
Port: 3000
Log driver: awslogs → /ecs/my-node-app
```

#### 4b.5 — Create ECS Service
```
AWS Console → ECS → Clusters → my-app-cluster → Services → Create
Launch type: FARGATE
Task definition: my-node-app (latest)
Service name: my-node-app-service
Desired tasks: 1
Networking: Default VPC, any subnet
Security group: Open port 3000
Public IP: Enabled
Click: Create
```

---

## STEP 5 — Create IAM User for GitHub Actions

GitHub Actions needs AWS credentials to push to ECR and update ECS.

### 5.1 — Create IAM Policy
```
AWS Console → IAM → Policies → Create Policy
Click JSON tab, paste:
```

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:ListTaskDefinitions"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["iam:PassRole"],
      "Resource": "arn:aws:iam::*:role/ecsTaskExecutionRole"
    }
  ]
}
```

```
Name: GitHubActionsECSPolicy
Click: Create Policy
```

### 5.2 — Create IAM User
```
AWS Console → IAM → Users → Create User
Username: github-actions-deployer
Attach policy: GitHubActionsECSPolicy (just created)
Click: Create User
```

### 5.3 — Create Access Key
```
Click on the user → Security Credentials
→ Create Access Key → Application running outside AWS
→ Download/Copy the Access Key ID and Secret
```

> ⚠️ Copy these NOW — the secret is shown only once!

---

## STEP 6 — Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

Add exactly **2 secrets**:

| Secret Name | Value | Where to find |
|-------------|-------|---------------|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | Step 5.3 above |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/...` | Step 5.3 above |

The region and other config are set directly in the workflow file `deploy.yml` (not as secrets).

---

## STEP 7 — Understand the GitHub Actions Pipeline

The file `.github/workflows/deploy.yml` has **3 jobs**:

```
git push to main
      │
      ▼
┌─────────────┐
│  Job 1:     │   npm ci → npm test
│  test       │   Fails fast if tests break
└──────┬──────┘
       │ (only if tests pass)
       ▼
┌─────────────────────────────────┐
│  Job 2: build-and-push          │
│                                 │
│  1. aws-actions/configure-aws   │ ← Uses your GitHub secrets
│  2. aws-actions/ecr-login       │ ← Gets ECR login token
│  3. docker build                │ ← Builds image (2-stage)
│     tag: git commit SHA         │ ← Unique tag per deploy
│     tag: latest                 │
│  4. docker push to ECR          │ ← Uploads to AWS ECR
│  outputs: image URI             │ ← Passes URI to Job 3
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  Job 3: deploy                  │
│                                 │
│  1. amazon-ecs-render-task-def  │ ← Injects new image URI
│     (updates task def JSON)     │   into task definition
│  2. amazon-ecs-deploy-task-def  │ ← Registers new task def
│     wait-for-stability: true    │   + Updates ECS service
│                                 │   + Waits for rollout
└─────────────────────────────────┘
```

**Image tagging strategy:**
- `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:abc1234f` ← commit SHA (immutable)
- `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:latest` ← always latest

---

## STEP 8 — First Deployment

### 8.1 — Push initial Docker image manually (first time only)

The ECS service needs at least one image to start:

```bash
# Log into ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Build and push
docker build -t my-node-app .
docker tag my-node-app:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:latest
docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/my-node-app:latest
```

### 8.2 — Trigger the pipeline

```bash
echo "# Trigger deploy" >> README.md
git add . && git commit -m "Trigger ECS deployment"
git push origin main
```

### 8.3 — Watch it in GitHub Actions

Repo → **Actions** tab → Click running workflow:

```
✅ Run Tests              12s
✅ Build & Push to ECR    45s
✅ Deploy to ECS          90s
```

---

## STEP 9 — Find Your App's Public IP

After the ECS task is running:

```bash
# Get task public IP via CLI
TASK_ARN=$(aws ecs list-tasks \
  --cluster my-app-cluster \
  --service-name my-node-app-service \
  --query "taskArns[0]" --output text --region us-east-1)

ENI=$(aws ecs describe-tasks \
  --cluster my-app-cluster \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)

aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI \
  --query "NetworkInterfaces[0].Association.PublicIp" \
  --output text
```

Or in the console:
```
ECS → Clusters → my-app-cluster → Tasks → [Task ID]
→ Network tab → Public IP
```

Access at: `http://TASK_PUBLIC_IP:3000`

---

## STEP 10 — (Optional) Add Application Load Balancer

For production use: persistent URL + HTTPS + multiple tasks

### 10.1 — Create ALB
```
AWS Console → EC2 → Load Balancers → Create
Type: Application Load Balancer
Name: my-app-alb
Scheme: Internet-facing
Listener: HTTP:80
Target group:
  Type: IP
  Port: 3000
  Health check path: /health
```

### 10.2 — Update ECS Service to use ALB
```
ECS → Service → Update
Load balancing: Application Load Balancer
Select your ALB + target group
```

Now your app is always at: `http://my-app-alb-xxxx.us-east-1.elb.amazonaws.com`

---

## STEP 11 — Monitor & Logs

### View logs in CloudWatch
```
AWS Console → CloudWatch → Log groups → /ecs/my-node-app
```

### Via CLI
```bash
aws logs tail /ecs/my-node-app --follow --region us-east-1
```

### Check service status
```bash
aws ecs describe-services \
  --cluster my-app-cluster \
  --services my-node-app-service \
  --region us-east-1 \
  --query "services[0].{status:status,running:runningCount,desired:desiredCount}"
```

---

## 🔑 ECS vs EC2 Deployment Comparison

| Feature | EC2 Approach | ECS Fargate Approach |
|---------|-------------|---------------------|
| Server management | You manage Ubuntu | AWS manages compute |
| Scaling | Manual or ASG | Set desired count |
| Deployment | rsync + SSH + PM2 | Docker image + task def |
| Cost | Pay for EC2 uptime | Pay per vCPU/memory per second |
| Rollback | Manual | Register old task def |
| Zero-downtime | PM2 reload | ECS rolling update |
| Logs | Files on server | CloudWatch (searchable) |
| Image storage | Not needed | ECR (required) |

---

## 🐛 Troubleshooting

### "CannotPullContainerError" in ECS
- ECR image URI is wrong in task definition
- `ecsTaskExecutionRole` missing ECR permissions
- Check: `aws ecr describe-repositories`

### GitHub Actions: "AccessDenied"
- IAM user missing permissions
- Check the policy from Step 5.1 is attached

### Task keeps stopping
- App crashing — check CloudWatch logs
- Health check failing — ensure `/health` returns 200
- Memory too low — increase from 512 to 1024 in task def

### ECR push fails in pipeline
- Check `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets
- ECR login step needs `ecr:GetAuthorizationToken` permission

---

## 📋 Quick Reference: All GitHub Secrets Needed

| Secret | Example Value |
|--------|---------------|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

> Region, cluster name, ECR repo name etc. are set in `deploy.yml` env vars — not secrets.
