# Number Reverser Platform: Cloud & DevOps Infrastructure

An enterprise cloud platform and DevSecOps pipeline on **Amazon Web Services (AWS)** using **Terraform**, **Amazon EKS (Kubernetes v1.30)**, **Amazon ECR**, and **Jenkins**.

---

## 1. Infrastructure Architecture

The platform is provisioned across a Multi-AZ Virtual Private Cloud (VPC) in **`ap-south-1` (Mumbai)**:

* **Amazon VPC (`10.0.0.0/16`)**: Multi-AZ network topology across `ap-south-1a` and `ap-south-1b`.
* **Subnets**:
  * **2 Public Subnets** (`10.0.1.0/24`, `10.0.2.0/24`): Hosts public AWS Elastic Load Balancer (ELB) and NAT Gateway.
  * **2 Private Subnets** (`10.0.10.0/24`, `10.0.11.0/24`): Dedicated isolated subnets hosting EKS worker nodes and Pods.
* **NAT Gateway & EIP**: Single NAT Gateway in the public subnet providing secure outbound internet egress for private workloads.
* **Default Security Group Lockdown**: Default VPC security group stripped of all ingress/egress rules to prevent unauthorized traffic inheritance (CIS / Checkov CKV_AWS_260).
* **Amazon ECR**: Container registry with `AES256` encryption, automatic vulnerability scan-on-push, and **`IMMUTABLE`** tag policies to prevent image tampering.
* **Amazon EKS Cluster (v1.30)**: Managed Kubernetes control plane with CloudWatch audit logging and customer-managed **AWS KMS envelope encryption** (`aws_kms_key.eks`) for Secrets at rest.
* **EKS Managed Node Group**: Amazon Linux 2023 (`AL2023_x86_64_STANDARD`) worker nodes with **AWS VPC CNI Prefix Delegation** enabled.
* **AWS Elastic Load Balancer (ELB)**: Public-facing load balancer routing external client traffic to private Kubernetes Pods on port 8000.
* **Jenkins Automation Server**: Standalone CI/CD orchestrator executing the end-to-end delivery pipeline.
* **Terraform IaC**: Modular, declarative infrastructure as code managing all 25 AWS resources.

### Infrastructure Flow Diagram

```text
[ Internet / Public Clients ]
              │
              ▼
   [ AWS Elastic Load Balancer (ELB) ]  <── (Public Subnet: 10.0.1.0/24)
              │
              ▼ (Private Subnet: 10.0.10.0/24)
   [ Amazon EKS Node Group (AL2023) ]
              │
              ▼
   [ Kubernetes Pod: number-reverser (Port 8000) ]
              │
              ▼ (Outbound Only)
   [ NAT Gateway & Internet Gateway ]
```

---

## 2. Security Controls

The platform implements zero-trust security controls across infrastructure, container, pipeline, and cluster layers:

* **IAM & Least Privilege**: Dedicated IAM roles for EKS Cluster (`cluster-role`) and Worker Nodes (`node-role`) restricted to required AWS service policies.
* **Zero Hardcoded Secrets**: CI/CD pipeline dynamically discovers AWS Account ID at runtime via **AWS STS** (`aws sts get-caller-identity`); no static AWS credentials or Account IDs are stored in source code.
* **Jenkins Credential Binding**: Secured via native `AmazonWebServicesCredentialsBinding` injecting temporary credentials into isolated execution scopes.
* **Docker & Container Security**: Multi-stage build on minimal `python:3.11-alpine` (~28MB image size); executed strictly as an unprivileged non-root user (**`UID 10001:10001`**) with a **read-only root filesystem**.
* **Trivy Vulnerability Scanning**: Automated container vulnerability scanning in CI/CD blocking `HIGH` and `CRITICAL` CVEs before registry upload.
* **Supply Chain Provenance (SBOM)**: Generates standardized Software Bill of Materials in SPDX JSON format (`syft`) for every build.
* **Cosign Cryptographic Signing**: Container images are digitally signed with Sigstore Cosign (`cosign sign`) and verified against public keys (`cosign verify`) with immutable transparency logging.
* **Kubernetes Pod Security**: Pods run with dropped capabilities (`capabilities.drop: ["ALL"]`), `allowPrivilegeEscalation: false`, and `privileged: false`.
* **Network Isolation (NetworkPolicy)**: Ingress restricted strictly to application port `8000`; egress restricted to CoreDNS (port 53) to prevent unauthorized lateral movement.
* **Admission Control (Kyverno)**: Cluster policies enforcing non-root execution, resource limits, and disallowing mutable `:latest` image tags.

---

## 3. CI/CD & Deployment Flow

Every commit to GitHub triggers an automated 10-stage declarative pipeline in Jenkins:

```text
GitHub (Push to main)
   ↓
Jenkins Pipeline Trigger
   ↓
1. Lint & SAST Check (Black, Flake8, Bandit)
   ↓
2. Unit Tests & Code Coverage (Pytest --cov-fail-under=90)
   ↓
3. Terraform Validation & Security Scan (Checkov)
   ↓
4. Docker Multi-Stage Build (Alpine 3.11)
   ↓
5. Container Security Scan (Trivy CVE Scanner)
   ↓
6. SBOM Generation (Syft SPDX JSON)
   ↓
7. Push Immutable Tag to Amazon ECR
   ↓
8. Cosign Cryptographic Sign & Verify
   ↓
9. Deploy to Amazon EKS (kubectl set image & rollout status)
   ↓
10. Live HTTP Smoke Tests (curl /healthz & /api/v1/reverse)
```

---

## 4. Infrastructure Provisioning Flow

Infrastructure lifecycle is managed declaratively through Terraform:

```text
Terraform (terraform/main.tf)
   ↓
AWS Multi-AZ VPC (10.0.0.0/16)
   ├── 2 Public Subnets + Internet Gateway + NAT Gateway
   ├── 2 Private Subnets + Route Tables
   └── Default Security Group Lockdown (Checkov CKV_AWS_260)
   ↓
AWS Identity & Security
   ├── IAM Cluster & Node Execution Roles
   ├── AWS KMS Customer-Managed Envelope Encryption Key
   └── Amazon ECR Repository (IMMUTABLE Tags, AES256, Scan-on-Push)
   ↓
Amazon EKS Cluster v1.30 (Control Plane with CloudWatch Logging)
   └── Managed Node Group (Amazon Linux 2023, VPC CNI Prefix Delegation)
   ↓
Kubernetes Workload Manifests (k8s/)
   ├── Namespace & Restricted SecurityContext Deployment
   ├── NetworkPolicy (Port 8000 Ingress Isolation)
   ├── Kyverno Admission Control Policies
   └── AWS Elastic Load Balancer (ELB Service)
```

---

## 5. Deployment Verification

Run these essential commands to verify the health and live status of the deployment:

### 1. Verify EKS Nodes & Cluster
```powershell
kubectl get nodes -o wide
```

### 2. Verify Pods & Security Context
```powershell
kubectl get pods -n number-reverser -o wide
kubectl describe deployment number-reverser -n number-reverser
```

### 3. Verify Kubernetes Service & Public Load Balancer
```powershell
kubectl get svc -n number-reverser
```

### 4. Verify Live Application Endpoints
```powershell
# Health Check Endpoint
curl -i http://<LOAD_BALANCER_DNS>/healthz

# Interactive API Swagger Documentation
# Open in browser: http://<LOAD_BALANCER_DNS>/docs

# Live Reverse API Transaction
curl -i -X POST http://<LOAD_BALANCER_DNS>/api/v1/reverse `
  -H "Content-Type: application/json" `
  -d '{"number": 123456789}'
```
