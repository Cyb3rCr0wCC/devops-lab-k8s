for ns in calico-apiserver calico-system tigera-operator; do
  kubectl get namespace $ns -o json | jq '.spec.finalizers=[]' > tmp.json
  kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f tmp.json
done

