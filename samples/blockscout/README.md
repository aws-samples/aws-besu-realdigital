# Blockscout Sample

Version: 4.1.5-beta

## How to deploy

```bash
kubectl create ns blocksout

kubectl apply -f blockscout-deploy.yaml -f blockscoutpostgres-statefulset.yaml

#Getting LoadBalancer URL

kubectl get service/blockscout -n blockscout -ojsonpath='External: http://{.status.loadBalancer.ingress[0].hostname}{":26000\n"}'
````
