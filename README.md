# AWS - Real Digital with EKS and Terraform

## Pre-reqs

- terraform 1.5.0
- AWS CLI >= 2.3.1
- jq 1.6

## How to deploy

```bash
git clone https://github.com/aws-samples/aws-besu-realdigital.git
cd aws-besu-realdigital

git clone https://github.com/Consensys/quorum-kubernetes.git quorum-kubernetes
cd quorum-kubernetes
git checkout 7bbac65

#Helm Chart patch
patch -p1 < ../patch/helm/charts/besu-genesis.patch
patch -p1 < ../patch/helm/charts/besu-node.patch

#Helm Values patch
patch -p1 < ../patch/helm/values/values.patch

#Ingress Rules patch
patch -p1 < ../patch/ingress/ingress-rules-monitoring.patch
```

```bash
# Creating EKS and all infra needed to deploy Besu
cd ..
terraform init && \
terraform apply -target module.vpc -auto-approve && \
terraform apply -target module.eks -auto-approve && \
terraform apply -target module.eks_blueprints_addons -auto-approve

#Deploy Besu
terraform apply -target helm_release.bootnode-2 -auto-approve && \
terraform apply -target helm_release.validator-4 -auto-approve && \
terraform apply -target helm_release.member-2 -auto-approve && \
terraform apply -auto-approve
```

## Validate

Run `update-kubeconfig` command:

```bash
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
```

### Ingress Services


Monitoring Ingress controller LoadBalancer
```bash
ELB=$(kubectl get -n besu service quorum-monitoring-ingress-ingress-nginx-controller -o json | jq -r '.status.loadBalancer.ingress[].hostname')
echo "http://${ELB}"
```

- Grafana URL http://${ELB}/
- Kibana URL http://${ELB}/kibana
  - Username: admin, password: password
- Explorer URL http://${ELB}/explorer
- BlockScout URL http://${ELB}/blockscout


Configuring Index Pattern in Kibana
```bash
curl -X POST http://${ELB}/kibana/api/index_patterns/index_pattern -H "kbn-xsrf: true" -H "Content-Type: application/json" -d '{
  "index_pattern": {
    "title": "filebeat-*",
    "timeFieldName": "@timestamp"
  }
}' 
```


Acessing Prometheus
```bash
kubectl port-forward service/monitoring-kube-prometheus-prometheus 8080:9090 -n besu
open browser http://localhost:8080
```

### Testing Cluster Besu

```bash
curl -v -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://${ELB}/rpc"
```

## Stop and Start Besu

STOP

```bash
kubectl scale statefulset/besu-node-member-1 --replicas 0 -n besu
kubectl scale statefulset/besu-node-member-2 --replicas 0 -n besu
kubectl scale statefulset/besu-node-rpc-1 --replicas 0 -n besu
sleep 45
kubectl scale statefulset/besu-node-validator-1 --replicas 0 -n besu
kubectl scale statefulset/besu-node-validator-2 --replicas 0 -n besu
kubectl scale statefulset/besu-node-validator-3 --replicas 0 -n besu
kubectl scale statefulset/besu-node-validator-4 --replicas 0 -n besu
sleep 45
kubectl scale statefulset/besu-node-bootnode-1 --replicas 0 -n besu
kubectl scale statefulset/besu-node-bootnode-2 --replicas 0 -n besu
```

START

```bash
kubectl scale statefulset/besu-node-bootnode-1 --replicas 1 -n besu
kubectl scale statefulset/besu-node-bootnode-2 --replicas 1 -n besu
sleep 45
kubectl scale statefulset/besu-node-validator-1 --replicas 1 -n besu
kubectl scale statefulset/besu-node-validator-2 --replicas 1 -n besu
kubectl scale statefulset/besu-node-validator-3 --replicas 1 -n besu
kubectl scale statefulset/besu-node-validator-4 --replicas 1 -n besu
sleep 45
kubectl scale statefulset/besu-node-rpc-1 --replicas 1 -n besu
kubectl scale statefulset/besu-node-member-1 --replicas 1 -n besu
kubectl scale statefulset/besu-node-member-2 --replicas 1 -n besu
```

## Installing Sirato - Optional

```bash
git clone https://github.com/web3labs/sirato-free.git
cd sirato-free/k8s
./sirato-launch.sh http://besu-node-rpc-1.besu.svc.cluster.local:8545

#Getting LoadBalancer URL
kubectl get service/sirato-proxy -n sirato-explorer -ojsonpath='External: http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

## Troubleshooting

```bash
kubectl run mycurlpod --rm --image=curlimages/curl -i --tty -- sh
```

## How to destroy

```bash
kubectl delete namespace sirato-explorer
terraform destroy -target helm_release.genesis -auto-approve && \
terraform destroy -target helm_release.monitoring -auto-approve && \
terraform destroy -target kubectl_manifest.karpenter_node_template -auto-approve && \
terraform destroy -target module.eks_blueprints_addons -auto-approve && \
terraform destroy -target module.eks -auto-approve && \
terraform destroy -auto-approve
chmod +x deleteBesuSecrets.sh
./deleteBesuSecrets.sh
```