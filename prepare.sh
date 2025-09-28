#!/bin/bash

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color / reset

ARGOCD_SECRET=argocd-secret.yaml
ARGOCD_DOMAIN=""
JENKINS_DOMAIN=""
INGRESS_FILE="ingress.yaml"
while getopts "a:j:" opt; do
  case $opt in
    a)
      ARGOCD_DOMAIN="$OPTARG"
      ;;
    j)
      JENKINS_DOMAIN="$OPTARG"
      ;;
    *)
      echo "Usage: $0 -a ARGOCD_DOMAIN -j JENKINS_DOMAIN"
      exit 1
      ;;
  esac
done



echo "[INFO]: Installing cnpg-system"
kubectl apply -f cnpg/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: Cnpg-system successfully deployed ${NC}"
else
    echo -e "${RED}[ERROR]: Failed to Deploy cnpg system ${NC}"
fi

echo "[INFO]: Installing metallb-system"
kubectl apply -f metallb-native.yaml
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: Metallb-system successfully deployed ${NC}"
else
    echo -e "${RED}[ERROR]: Failed to Deploy metallb system ${NC}"
    exit 1
fi

# ✅ Wait until all pods in metallb-system are Ready
echo "[INFO]: Waiting for metallb-system pods to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=Ready pod \
  --all \
  --timeout=10m
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: All metallb-system pods are ready${NC}"
else
    echo -e "${RED}[ERROR]: metallb-system pods did not become ready in time${NC}"
    exit 1
fi

echo "[INFO]: Preparing volumes"
kubectl apply -f volumes.yml
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: Volumes successfully created${NC}"
else
    echo -e "${RED}[ERROR]: Failed to create volumes ${NC}"
    exit 1
fi

echo "[INFO]: Preparing k8s resources"
kubectl apply -f k8s/namespace.yml

echo "[INFO]: Applying all k8s manifests"
kubectl apply -f k8s/
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: Resources created successfully. ${NC}"
else
    echo -e "${RED}[ERROR]: Failed to create resources ${NC}"
fi

echo "[INFO]: Installing nginx ingress controller"
helm install nginx-release oci://ghcr.io/nginx/charts/nginx-ingress \
  --version 2.3.0 \
  --namespace ingress-nginx \
  --create-namespace

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: Nginx ingress controller successfully deployed.${NC}"
else
    echo -e "${RED}[ERROR]: Failed to deploy nginx ingress controller ${NC}"
    exit 1
fi

# ✅ Wait for NGINX ingress controller pods to be Ready
echo "[INFO]: Waiting for NGINX ingress controller pods to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --all \
  --timeout=10m

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: All NGINX ingress controller pods are ready.${NC}"
else
    echo -e "${RED}[ERROR]: NGINX ingress controller pods did not become ready in time.${NC}"
    exit 1
fi

echo "[INFO]: Generating self-signed cert for argocd"
cd argocd && bash certgen.sh

if [ ! -f "$ARGOCD_SECRET" ]; then
    echo -e "${RED}Error: $ARGOCD_SECRET not found!${NC}"
    exit 1
fi

# Base64 encode the certificate
TLS_CRT_BASE64=$(cat tls.crt | base64 -w0)

# Replace the existing tls.crt line in ingress.yaml
# This assumes the line starts with "  tls.crt:" (indented with 2 spaces)
sed -i "s|^\s*tls\.crt:.*$|  tls.crt: $TLS_CRT_BASE64|" "$ARGOCD_SECRET"

# Check if the command succeeded
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: tls.crt in $ARGOCD_SECRET successfully updated.${NC}"
else
    echo
fi
TLS_KEY_BASE64=$(cat tls.key | base64 -w0)

# Replace tls.crt
sed -i "s|^\s*tls\.crt:.*$|  tls.crt: $TLS_CRT_BASE64|" "$ARGOCD_SECRET"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: tls.crt successfully updated in $ARGOCD_SECRET.${NC}"
else
    echo -e "${RED}[ERROR]: Failed to update tls.crt in $INGRARGOCD_SECRETESS_FILE.${NC}"
fi

# Replace tls.key
sed -i "s|^\s*tls\.key:.*$|  tls.key: $TLS_KEY_BASE64|" "$ARGOCD_SECRET"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: tls.key successfully updated in $ARGOCD_SECRET.${NC}"
else
    echo -e "${RED}[ERROR]: Failed to update tls.key in $ARGOCD_SECRET.${NC}"
fi


# Replace the host under rules
sed -i 's/^\(\s*-\s*host:\s*\).*/\1'$ARGOCD_DOMAIN'/' $INGRESS_FILE
# Replace the host under tls
sed -i 's/^\(\s*-\s*hosts: \s*\).*/\1'$ARGOCD_DOMAIN'/' $INGRESS_FILE

if [ $? -eq 0 ]; then
  echo -e "${GREEN}[INFO]: Updated ingress hosts to $ARGOCD_DOMAIN in $INGRESS_FILE.${NC}"
else
  echo -e "${RED}[ERROR]: Failed to update ingress hosts in $INGRESS_FILE.${NC}"
fi

echo "[INFO]: Deploying argocd"

cd ../
kubectl apply -n devops-tools -f argocd/deployment.yaml

# ✅ Wait until all ArgoCD pods are Ready
echo "[INFO]: Waiting for ArgoCD pods to be ready..."
kubectl wait --namespace devops-tools \
  --for=condition=Ready pod \
  --all \
  --timeout=10m

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]: All ArgoCD pods are ready.${NC}"
else
    echo -e "${RED}[ERROR]: ArgoCD pods did not become ready in time.${NC}"
    echo "[INFO]: Showing pod statuses for debugging:"
    kubectl get pods -n devops-tools
    exit 1
fi

kubectl apply -n devops-tools -f argocd/
kubectl rollout restart deployment argocd-server -n devops-tools
kubectl apply -n devops-tools -f argocd/configmap.yml
kubectl rollout restart deployment argocd-server -n devops-tools

if [ $? -eq 0 ]; then
  echo -e "${GREEN}[INFO]: Argocd deployed successfully.${NC}"
else
  echo -e "${RED}[ERROR]: Failed to deploy agrocd.${NC}"
fi