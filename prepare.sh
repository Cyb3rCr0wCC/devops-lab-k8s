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


#echo "[INFO]: Setting CNPG-system"
#kubectl apply --server-side --force-conflicts -f \
#  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.27/releases/cnpg-1.27.0.yaml
#
#if [ $? -ne 0 ]; then
#  echo -e "${RED}Error: cnpg system deployment failed failed!${NC}"
#else
#  echo -e "${GREEN}Success: cpng-system installition successfully completed!${NC}"
#fi

echo "[INFO]: Preparing k8s infrastructure"
kubectl apply -f k8s

echo "[INFO]: Installing nginx ingress controller"
helm install my-release oci://ghcr.io/nginx/charts/nginx-ingress --version 2.3.0 --namespace ingress-nginx

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
cd ../ && kubectl apply -n devops-tools -f argocd/

if [ $? -eq 0 ]; then
  echo -e "${GREEN}[INFO]: Argocd deployed successfully.${NC}"
else
  echo -e "${RED}[ERROR]: Failed to deploy agrocd.${NC}"
fi

echo "Creating argocd application for deployment"
cd argocd && kubectl apply -f application.yaml && cd ..

if [ $? -eq 0 ]; then
  echo -e "${GREEN}[INFO]: Argocd application deployed successfully.${NC}"
else
  echo -e "${RED}[ERROR]: Failed to deploy agrocd application.${NC}"
fi