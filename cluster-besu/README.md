# AWS - Real Digital with EKS and Terraform

Deploy Hyperledge Besu cluster using Hashicorp Terraform (IaC) and some AWS Services: [Amazon EKS](https://aws.amazon.com/eks/), [Amazon EC2](https://aws.amazon.com/ec2/), [Amazon EBS](https://aws.amazon.com/ebs/), [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/). To improve the auto-scaling experience we are using [Karpenter](https://karpenter.sh/).

## Table of Contents

- [AWS - Real Digital with EKS and Terraform](#aws---real-digital-with-eks-and-terraform)
  - [Table of Contents](#table-of-contents)
  - [How to deploy Infrastructure and Besu Cluster](#how-to-deploy-infrastructure-and-besu-cluster)
    - [Pre-reqs](#pre-reqs)
    - [Validate and check EKS](#validate-and-check-eks)
    - [Ingress Services](#ingress-services)
      - [Monitoring Ingress controller LoadBalancer](#monitoring-ingress-controller-loadbalancer)
      - [Grafana default credentials](#grafana-default-credentials)
      - [Configuring Index Pattern in Kibana](#configuring-index-pattern-in-kibana)
      - [Acessing Prometheus](#acessing-prometheus)
    - [Testing Cluster Besu](#testing-cluster-besu)
  - [Stop and Start Besu Services](#stop-and-start-besu-services)
    - [Installing Chainlens - Optional](#installing-chainlens---optional)
    - [Using blockscout - Optional](#using-blockscout---optional)
  - [Troubleshooting](#troubleshooting)
  - [How to destroy infrastructure](#how-to-destroy-infrastructure)

## How to deploy Infrastructure and Besu Cluster

### Pre-reqs

- terraform 1.5.0
- AWS CLI >= 2.3.1
- jq 1.6

```bash
git clone https://github.com/aws-samples/aws-besu-realdigital.git
cd aws-besu-realdigital/cluster-besu

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
patch -p1 < ../patch/ingress/ingress-rules-besu.patch
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
terraform apply -target helm_release.validator-6 -auto-approve && \
terraform apply -target helm_release.member-2 -auto-approve && \
terraform apply -auto-approve
```

### Validate and check EKS

Run `update-kubeconfig` command:

```bash
export AWS_REGION=<region_name us-east-1>
export CLUSTER_NAME=<eks_cluster_name cluster-besu>
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes
```

### Ingress Services

#### Monitoring Ingress controller LoadBalancer

```bash
ELB_MONITOR=$(kubectl get -n besu service monitoring-ingress-nginx-controller -o json | jq -r '.status.loadBalancer.ingress[].hostname')
echo "Grafana URL - http://${ELB_MONITOR}"
echo "Kibana URL - http://${ELB_MONITOR}/kibana"
echo "Explorer URL - http://${ELB_MONITOR}/explorer"
```

#### Grafana default credentials

- Username: admin, password: prom-operator, modify after first logging.

#### Configuring Index Pattern in Kibana

```bash
curl -X POST http://${ELB_MONITOR}/kibana/api/index_patterns/index_pattern -H "kbn-xsrf: true" -H "Content-Type: application/json" -d '{
  "index_pattern": {
    "title": "filebeat-*",
    "timeFieldName": "@timestamp"
  }
}'
```

#### Acessing Prometheus

```bash
kubectl port-forward service/monitoring-kube-prometheus-prometheus 8080:9090 -n besu
open browser http://localhost:8080
```

### Testing Cluster Besu

```bash
ELB_BESU=$(kubectl get -n besu service besu-ingress-nginx-controller -o json | jq -r '.status.loadBalancer.ingress[].hostname')
curl -v -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://${ELB_BESU}/rpc"
echo "http://${ELB_BESU}/rpc"
```

## Stop and Start Besu Services

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

### Installing Chainlens - Optional

```bash
git clone https://github.com/web3labs/sirato-free.git
cd sirato-free/k8s
./chainlens-launch.sh http://besu-node-rpc-1.besu.svc.cluster.local:8545

#Getting LoadBalancer URL
kubectl get service/chainlens-proxy -n chainlens-explorer -ojsonpath='External: http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

### Using blockscout - Optional

See [Blockscout sample](../samples/blockscout/README.md)

## Troubleshooting

```bash
kubectl run mycurlpod --rm --image=curlimages/curl -i --tty -- sh
```

## How to destroy infrastructure

```bash
kubectl delete namespace chainlens-explorer
terraform destroy -target helm_release.genesis -auto-approve && \
terraform destroy -target helm_release.monitoring -auto-approve && \
terraform destroy -target kubectl_manifest.karpenter_node_template -auto-approve && \
terraform destroy -target module.eks_blueprints_addons -auto-approve && \
terraform destroy -target module.eks -auto-approve && \
terraform destroy -auto-approve
chmod +x deleteBesuSecrets.sh
export AWS_PAGER=""
./deleteBesuSecrets.sh
```
