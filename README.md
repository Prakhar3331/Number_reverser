# The Number Reverser Platform

A simple, secure, and production-ready microservice built with **Python + FastAPI**, deployed to **Amazon EKS** using **Terraform**, containerized with **Docker**, and delivered through a **Jenkins CI/CD pipeline** with security scanning (**Trivy**, **Checkov**, **Syft**, **Cosign**, **Kyverno**).

---

## 1. Project Overview

The **Number Reverser** service reverses numbers via an HTTP REST API while handling all mathematical and input edge cases:
* **Positive numbers**: `12345` $\rightarrow$ `54321`
* **Negative numbers**: `-123` $\rightarrow$ `-321` (negative sign is preserved)
* **Trailing zeros**: `1200` $\rightarrow$ integer `21` and string `"0021"` (`dropped_leading_zeros: 2`)
* **Leading zeros in string**: `"007"` $\rightarrow$ `700`
* **Zero values**: `0` $\rightarrow$ `0`
* **Non-numeric / Decimals**: `"abc"`, `"12.34"` $\rightarrow$ **HTTP 422 Unprocessable Entity**
* **Integer overflow**: Numbers exceeding signed 64-bit bounds $\rightarrow$ **HTTP 400 Bad Request**

---

## 2. Architecture & Secure Networking

```
+---------------------------------------------------------------------------------------------------+
|                                  AWS VPC (10.0.0.0/16) - Multi-AZ                                 |
|                                                                                                   |
|  +---------------------------------------+          +------------------------------------------+  |
|  | Public Subnet 1 (10.0.1.0/24)         |          | Public Subnet 2 (10.0.2.0/24)            |  |
|  | - Internet Gateway Route              |          | - Internet Gateway Route                 |  |
|  | - Elastic IP + NAT Gateway            |          | - Public Load Balancers                  |  |
|  +-------------------+-------------------+          +------------------------------------------+  |
|                      |                                                                            |
|                      +----------------------------------+                                         |
|                                                         v                                         |
|  +---------------------------------------+          +------------------------------------------+  |
|  | Private Subnet 1 (10.0.10.0/24)       |          | Private Subnet 2 (10.0.20.0/24)          |  |
|  | - Outbound via NAT Gateway            |          | - Outbound via NAT Gateway               |  |
|  | - EKS Worker Node (t3.micro)          |          | - Standby Subnet for Multi-AZ Quorum     |  |
|  | - Number Reverser Pod (20GB gp3 EBS)  |          | - No Direct Inbound from Internet        |  |
|  +---------------------------------------+          +------------------------------------------+  |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  | Amazon EKS Managed Control Plane (v1.30)                                                    |  |
|  | - Kyverno Policies (Enforces non-root, resource limits, no :latest tags)                    |  |
|  | - Zero-Trust NetworkPolicy (Port 8000 ingress, Port 53 DNS egress only)                      |  |
|  +---------------------------------------------------------------------------------------------+  |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  | Amazon ECR: AES-256 encrypted, 500MB Free Tier included, immutable tags                       |  |
|  +---------------------------------------------------------------------------------------------+  |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  | S3 Remote Backend + DynamoDB Lock Table: Encrypted remote Terraform state storage             |  |
|  +---------------------------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------------------------+
```

### Security & Free-Tier Cost Highlights:
* **Secure Subnet Isolation**: Worker nodes and application Pods run strictly inside **Private Subnets** with zero public IP addresses directly accessible from the internet.
* **NAT Gateway Egress**: Outbound internet traffic (pulling images, package updates) is securely routed through an Elastic IP and NAT Gateway located in the public subnet.
* **Free-Tier EC2 Worker Nodes**: Uses `t3.micro` or `t2.micro` instances (included in the **750 free hours/month** AWS Free Tier).
* **Free-Tier EBS Storage**: Worker node root disk is set to **20GB gp3** (within the **30GB/month** Free Tier allowance).
* **Free-Tier ECR**: 500MB/month free storage for private container images.
* **S3 Remote State Storage**: Encrypted S3 bucket with versioning + DynamoDB distributed state locking.
* **Instant Teardown**: Run `./scripts/destroy.sh` or `.\scripts\destroy.ps1` to destroy all resources when finished.

### Deployment Flow:
```
Git Repository ---> Jenkins CI/CD Pipeline ---> Docker Build ---> Security Scans (Trivy/Checkov/Syft) ---> ECR Push ---> Cosign Sign/Verify ---> Deploy to Amazon EKS
```

---

## 3. Prerequisites & Required Tools

Install the following tools before running or deploying the project:

| Tool | Minimum Version | Installation Command / Link |
| :--- | :--- | :--- |
| **Python** | `3.11+` | [python.org](https://www.python.org/downloads/) |
| **Docker** | `20.10+` | [docker.com](https://docs.docker.com/get-docker/) |
| **Terraform** | `1.5.0+` | `choco install terraform` or [terraform.io](https://developer.hashicorp.com/terraform/install) |
| **AWS CLI** | `v2` | `choco install awscli` or [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| **Kubectl** | `1.28+` | `choco install kubernetes-cli` or [kubernetes.io/docs/tasks/tools/](https://kubernetes.io/docs/tasks/tools/) |
| **Trivy** | `0.45+` | `choco install trivy` or [trivy.dev](https://trivy.dev/) |
| **Syft** | `0.90+` | `choco install syft` or [github.com/anchore/syft](https://github.com/anchore/syft) |
| **Cosign** | `2.2+` | `choco install cosign` or [docs.sigstore.dev/cosign/overview/](https://docs.sigstore.dev/cosign/overview/) |
| **Checkov** | `3.0+` | `pip install checkov` |

---

## 4. Repository Structure

```
Devops_project/
├── app/
│   ├── main.py             # FastAPI microservice with reversing logic & health probes
│   └── test_main.py        # Pytest test suite covering all edge cases
├── k8s/
│   ├── deployment.yaml     # Kubernetes Namespace, Deployment (non-root), and Service
│   ├── networkpolicy.yaml  # Zero-Trust network isolation policy
│   └── kyverno.yaml        # Kyverno admission policies (non-root, limits, no :latest)
├── terraform/
│   ├── main.tf                  # VPC (public/private), EKS, Node Group, ECR, and IAM
│   ├── variables.tf             # AWS region, environment, and project name variables
│   ├── outputs.tf               # EKS cluster name, endpoint, and ECR repository URL outputs
│   ├── backend.tf.example       # S3 Remote State & DynamoDB locking configuration
│   └── terraform.tfvars.example # Example variable definitions
├── scripts/
│   ├── dev.sh / dev.ps1                 # Run application locally
│   ├── test.sh / test.ps1               # Run tests, linters, and coverage
│   ├── setup-backend.sh / setup-backend.ps1 # Create S3 bucket & DynamoDB lock table
│   ├── deploy.sh / deploy.ps1           # Provision AWS infrastructure and deploy to EKS
│   └── destroy.sh / destroy.ps1         # Destroy all AWS infrastructure and clean up
├── Dockerfile              # Production multi-stage, non-root container image
├── .dockerignore           # Files excluded from Docker build context
├── Jenkinsfile             # Declarative Jenkins CI/CD pipeline (10 stages)
├── pyproject.toml          # Pytest and coverage settings
├── requirements.txt        # Production dependencies (FastAPI, Uvicorn, Pydantic)
├── requirements-dev.txt    # Development & test dependencies (Pytest, Flake8, Black, Bandit)
└── README.md               # Complete end-to-end documentation
```

---

## 5. Local Setup & Testing

### 5.1 Install Dependencies
```bash
# Linux / macOS
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt

# Windows (PowerShell)
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
```

### 5.2 Run the Application Locally
```bash
# Using helper script
./scripts/dev.sh           # Linux/macOS
.\scripts\dev.ps1          # Windows PowerShell

# Or directly with uvicorn
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
The API is available at `http://localhost:8000` (Swagger docs at `http://localhost:8000/docs`).

### 5.3 Test the Endpoints Locally
```bash
# 1. Test Positive Number Reversal (12345 -> 54321)
curl -X POST http://localhost:8000/api/v1/reverse \
     -H "Content-Type: application/json" \
     -d '{"number": 12345}'

# 2. Test Negative Number Reversal (-123 -> -321)
curl -X POST http://localhost:8000/api/v1/reverse \
     -H "Content-Type: application/json" \
     -d '{"number": -123}'

# 3. Test Trailing Zeros (1200 -> 21, reversed_string: "0021")
curl -X POST http://localhost:8000/api/v1/reverse \
     -H "Content-Type: application/json" \
     -d '{"number": 1200}'

# 4. Test Query Parameter GET Endpoint
curl "http://localhost:8000/api/v1/reverse?number=98700"

# 5. Test Liveness Probe
curl http://localhost:8000/healthz

# 6. Test Readiness Probe
curl http://localhost:8000/ready
```

### 5.4 Run Unit Tests & Code Quality Checks
```bash
# Using helper script
./scripts/test.sh          # Linux/macOS
.\scripts\test.ps1         # Windows PowerShell

# Or individually
pytest -v --cov=app --cov-fail-under=90
flake8 app/ --max-line-length=100
black --check app/
bandit -r app/ -ll -ii
```

### 5.5 Build and Scan Docker Image Locally
```bash
# Build image
docker build -t number-reverser:local .

# Scan image for vulnerabilities with Trivy
trivy image --severity HIGH,CRITICAL number-reverser:local

# Generate SBOM with Syft
syft number-reverser:local -o spdx-json=sbom.spdx.json
```

---

## 6. AWS Infrastructure Setup (Terraform)

### 6.1 Configure AWS Credentials
Ensure your AWS credentials have permissions to manage VPC, EKS, EC2, IAM, ECR, S3, and DynamoDB:
```bash
export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
export AWS_REGION="us-east-1"
```

### 6.2 Set Up S3 Remote State Backend & DynamoDB Lock Table (Optional but Recommended)
To store your Terraform state securely in Amazon S3 with DynamoDB distributed state locking:

```bash
# Option A: Run the automated helper script
./scripts/setup-backend.sh <YOUR_UNIQUE_STATE_BUCKET_NAME> us-east-1    # Linux/macOS
.\scripts\setup-backend.ps1 -BucketName <YOUR_UNIQUE_STATE_BUCKET_NAME> # Windows PowerShell

# Option B: Run manual AWS CLI commands
# 1. Create S3 Bucket (must be globally unique)
aws s3api create-bucket --bucket <YOUR_UNIQUE_STATE_BUCKET_NAME> --region us-east-1

# 2. Enable Bucket Versioning
aws s3api put-bucket-versioning --bucket <YOUR_UNIQUE_STATE_BUCKET_NAME> --versioning-configuration Status=Enabled

# 3. Enable Server-Side Encryption (AES256)
aws s3api put-bucket-encryption --bucket <YOUR_UNIQUE_STATE_BUCKET_NAME> \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Block Public Access
aws s3api put-public-access-block --bucket <YOUR_UNIQUE_STATE_BUCKET_NAME> \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 5. Create DynamoDB Lock Table
aws dynamodb create-table \
    --table-name terraform-state-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1
```

After creating the bucket, copy `terraform/backend.tf.example` to `terraform/backend.tf` and fill in your bucket name:
```hcl
terraform {
  backend "s3" {
    bucket         = "<YOUR_UNIQUE_STATE_BUCKET_NAME>"
    key            = "number-reverser/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

### 6.3 Provision Infrastructure
```bash
cd terraform

# Initialize Terraform (fetches providers and connects to S3 backend)
terraform init

# Validate configuration
terraform validate

# Scan IaC for security issues
checkov -d . --framework terraform

# Plan and Apply
terraform plan -out=tfplan
terraform apply tfplan

# Note the outputs:
# - cluster_name: number-reverser-cluster
# - ecr_repository_url: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/number-reverser
cd ..
```

### 6.4 Connect Kubectl to EKS Cluster
```bash
aws eks update-kubeconfig --region us-east-1 --name number-reverser-cluster
kubectl get nodes
```

---

## 7. Manual Kubernetes Deployment

If deploying manually without CI/CD:

```bash
# 1. Login to Amazon ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# 2. Build, tag, and push Docker image
docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/number-reverser:v1.0.0 .
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/number-reverser:v1.0.0

# 3. Apply Kyverno security policies & NetworkPolicy
kubectl apply -f k8s/kyverno.yaml
kubectl apply -f k8s/networkpolicy.yaml

# 4. Apply Deployment and Service
kubectl apply -f k8s/deployment.yaml

# 5. Set the image tag on deployment
kubectl set image deployment/number-reverser number-reverser=<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/number-reverser:v1.0.0 -n number-reverser

# 6. Verify rollout
kubectl rollout status deployment/number-reverser -n number-reverser --timeout=120s
kubectl get pods,svc -n number-reverser
```

---

## 8. Jenkins CI/CD Pipeline

The repository includes a declarative [`Jenkinsfile`](file:///c:/Users/lenovo/Documents/Devops_project/Jenkinsfile) that automates the entire delivery pipeline.

### 8.1 Required Jenkins Credentials
Configure the following in **Manage Jenkins $\rightarrow$ Credentials $\rightarrow$ System $\rightarrow$ Global credentials**:

| Credential ID | Type | Description |
| :--- | :--- | :--- |
| `aws-account-id` | **Secret text** | Your 12-digit AWS Account ID (e.g., `123456789012`) |
| `aws-credentials` | **AWS Credentials** | AWS Access Key ID and Secret Access Key |
| `cosign-key` | **Secret file** | `cosign.key` private key file for signing images |

### 8.3 Pipeline Stages Explained
1. **Lint & Security Check**: Runs `black`, `flake8`, and `bandit` AST security linter.
2. **Unit Tests**: Runs `pytest` and verifies code coverage is at least 90%.
3. **Terraform Validation & Checkov**: Validates Terraform syntax and runs Checkov IaC security scan.
4. **Docker Build**: Builds the minimal non-root Docker image.
5. **Trivy Security Scan**: Scans container image. Fails the build immediately (`--exit-code 1`) if any `CRITICAL` or `HIGH` vulnerabilities are found.
6. **Generate SBOM (Syft)**: Produces an SPDX JSON Software Bill of Materials and archives it as a build artifact.
7. **Push to Amazon ECR**: Authenticates to ECR and pushes the immutable image tag (`v1.0.0-<BUILD_NUMBER>`).
8. **Cosign Sign & Verify**: Cryptographically signs the container image with Cosign and verifies the signature against `cosign.pub` before deploying.
9. **Deploy to EKS & Verify**: Applies Kyverno policies, NetworkPolicy, updates the deployment image, and waits for `kubectl rollout status`.
10. **Smoke Test**: Port-forwards to the service and executes live health and reverse API checks.

### 8.4 Triggering the Pipeline
1. Create a **Pipeline** job in Jenkins.
2. Under **Pipeline Definition**, select **Pipeline script from SCM**.
3. Set SCM to **Git** and enter the repository URL.
4. Set Script Path to `Jenkinsfile`.
5. Click **Build Now**.

---

## 9. Verification & Troubleshooting

### How to Verify Deployment:
```bash
# Check pod status
kubectl get pods -n number-reverser

# Check service status
kubectl get svc -n number-reverser

# Port-forward to local machine to test live
kubectl port-forward svc/number-reverser 8000:80 -n number-reverser

# Run verification request
curl -X POST http://localhost:8000/api/v1/reverse -H "Content-Type: application/json" -d '{"number": 12345}'
# Expected output: {"original_input":12345,"reversed_number":54321,"reversed_string":"54321","is_negative":false,"dropped_leading_zeros":0,"execution_time_ms":...}
```

### Troubleshooting Common Issues:

* **Issue: Trivy scan fails during pipeline**
  * *Cause*: Base image has newly discovered CVEs.
  * *Fix*: Update `python:3.11-slim` in `Dockerfile` to the latest patch or run `apt-get upgrade -y` in builder stage.
* **Issue: Kyverno blocks Pod deployment**
  * *Cause*: Pod manifest violates security policy (e.g. running as root, missing resource limits, or using `:latest` tag).
  * *Fix*: Ensure `deployment.yaml` contains `securityContext.runAsNonRoot: true`, CPU/memory requests and limits, and an explicit image tag.
* **Issue: Pod in `CrashLoopBackOff`**
  * *Cause*: Application failed to start.
  * *Fix*: Inspect logs using `kubectl logs deployment/number-reverser -n number-reverser`.
* **Issue: Terraform fails on EKS node group creation**
  * *Cause*: IAM role missing EC2 worker node permissions or subnets misconfigured.
  * *Fix*: Verify AWS credentials and ensure the subnets have internet egress via the NAT Gateway.

---

## 10. Teardown & Clean Up

To destroy all AWS cloud resources and avoid ongoing cloud costs:

```bash
# Using helper script
./scripts/destroy.sh       # Linux/macOS
.\scripts\destroy.ps1      # Windows PowerShell

# Or manually
kubectl delete namespace number-reverser --ignore-not-found=true
cd terraform
terraform destroy -auto-approve
```
