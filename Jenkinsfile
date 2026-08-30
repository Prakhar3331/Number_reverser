pipeline {
    agent any

    environment {
        AWS_REGION         = 'ap-south-1'
        APP_NAME           = 'number-reverser'
        CLUSTER_NAME       = 'number-reverser-cluster'
        
        // ECR & Registry Credentials (Amazon ECR plugin format: ecr:<region>:<credentials-id>)
        registryCredential = 'ecr:ap-south-1:aws-credentials'
        appRegistry        = '374857852848.dkr.ecr.ap-south-1.amazonaws.com/number-reverser'
        ecrRegistry        = 'https://374857852848.dkr.ecr.ap-south-1.amazonaws.com'
    }

    stages {
        stage('Lint & Security Check') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --quiet -r requirements-dev.txt
                    black --check app/
                    flake8 app/ --max-line-length=100
                    bandit -r app/ -ll -ii
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    . .venv/bin/activate
                    pytest -v --cov=app --cov-fail-under=90
                '''
            }
        }

        stage('Terraform Validation & Checkov') {
            steps {
                sh '''
                    terraform -chdir=terraform init -backend=false
                    terraform -chdir=terraform validate
                    . .venv/bin/activate
                    checkov -d terraform/ --framework terraform --soft-fail
                '''
            }
        }

        stage('Docker Build') {
            steps {
                script {
                    dockerImage = docker.build("${appRegistry}:${env.BUILD_NUMBER}", "--no-cache .")
                }
            }
        }

        stage('Trivy Security Scan') {
            steps {
                sh "trivy image --cache-dir .trivy-cache --severity CRITICAL,HIGH --ignore-unfixed --exit-code 0 ${appRegistry}:${env.BUILD_NUMBER}"
            }
        }

        stage('Generate SBOM (Syft)') {
            steps {
                sh "syft ${appRegistry}:${env.BUILD_NUMBER} -o spdx-json=sbom.spdx.json"
                archiveArtifacts artifacts: 'sbom.spdx.json', allowEmptyArchive: true
            }
        }

        stage('Upload App Image') {
            steps {
                script {
                    docker.withRegistry(ecrRegistry, registryCredential) {
                        dockerImage.push("${env.BUILD_NUMBER}")
                        dockerImage.push('latest')
                    }
                }
            }
        }

        stage('Cosign Sign & Verify') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY'),
                                file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
                    sh '''
                        set -ex
                        IMAGE_URI="${appRegistry}:${BUILD_NUMBER}"
                        cosign sign --key "${COSIGN_KEY}" --yes "${IMAGE_URI}"
                        cosign verify --key cosign.pub "${IMAGE_URI}"
                    '''
                }
            }
        }

        stage('Deploy to EKS & Verify') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        set -ex
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        export AWS_REGION="${AWS_REGION}"
                        
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
                        
                        # Apply Kyverno policies, NetworkPolicy, and Deployment
                        kubectl apply -f k8s/kyverno.yaml
                        kubectl apply -f k8s/networkpolicy.yaml
                        kubectl apply -f k8s/deployment.yaml
                        
                        # Set to deployed image tag
                        kubectl set image deployment/number-reverser number-reverser=${appRegistry}:${BUILD_NUMBER} -n number-reverser
                        kubectl rollout status deployment/number-reverser -n number-reverser --timeout=120s
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    kubectl port-forward svc/number-reverser 8000:80 -n number-reverser &
                    PF_PID=$!
                    sleep 3

                    # Verify health and reverse endpoint
                    curl -sf http://127.0.0.1:8000/healthz
                    curl -sf -X POST http://127.0.0.1:8000/api/v1/reverse -H "Content-Type: application/json" -d '{"number": 12345}' | grep 54321

                    kill $PF_PID
                    echo "Smoke tests passed!"
                '''
            }
        }
    }
}
