# Generate private key
openssl genrsa -out tls.key 2048

# Generate self-signed certificate valid for 365 days
openssl req -x509 -new -nodes -key tls.key -subj "/CN=argocd.cybercrow.com/O=ArgoCD" -days 365 -out tls.crt


