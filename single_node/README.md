
# Real Digital - Besu Single Node 

This repo intends to support the creation of a single node Besu Hyperledger running into Amazon EC2 in private Amazon VPC using AWS CDK.


### How to Install 

## 0. Pre-reqs

- Python 3.7++
- CDK v2 
- AWS Cli >= 2.3.1
- NodeJS 18.17++


## 1. Configure Python and download CDK. 
```
python3 -m venv .venv
```

After the init process completes and the virtualenv is created, you can use the following
step to activate your virtualenv.

```
source .venv/bin/activate
```

If you are a Windows platform, you would activate the virtualenv like this:

```
.venv\Scripts\activate.bat
```

Once the virtualenv is activated, you can install the required dependencies.

```
pip install -r requirements.txt
```

## 1.1 Parameters
We are using parameters to define Network CIDR blocks, Instance Type and Bootnodes address. 

### VPC CIDR
The network address for the VPC that you will create on the stack.

### Besu CIDR
The network address of the Cluster Besu.

### Instance Type
The instance type of the stack. Default is m5.xlarge.

### Bootnodes 
To understand what bootnodes means and to get the BACEN address, check [this link](https://github.com/bacen/pilotord-kit-onboarding/blob/main/ingresso.md#discovery-bootnode).

## 2. Synthesize the CDK 

At this point you can now synthesize the CloudFormation template for this code.

```
cdk synth -c "VpcCIDR=10.0.0.0/16" -c "BesuCIDR=192.168.10.10/32" -c "InstanceType=c5.large" -c "BootNodes=enode://c35c3ec90a8a51fd5703594c6303382f3ae6b2ecb99bab2c04b3794f2bc3fc2631dabb0c08af795787a6c004d8f532230ae6e9925cbbefb0b28b79295d615f@127.0.0.1:30303"
```

*this address and bootnodes are just examples*

### 2.1  CDK Helpfull commands

 * `cdk ls`          list all stacks in the app
 * `cdk synth`       emits the synthesized CloudFormation template
 * `cdk deploy`      deploy this stack to your default AWS account/region
 * `cdk diff`        compare deployed stack with current state
 * `cdk docs`        open CDK documentation


## 3. Deploy 

To deploy the stack, run: 

`cdk deploy -c "VpcCIDR=10.0.0.0/16" -c "BesuCIDR=192.168.10.10/32" -c "InstanceType=c5.large" -c "BootNodes=enode://YourBootNode@127.0.0.1:30303"` 

*Dont forget to check the [Parameters](#parameters) section*

## 4. EC2 SSH Connection

To access your ECS instance, use [EC2 Session Manager](https://repost.aws/knowledge-center/ec2-systems-manager-vpc-endpoints).


## 5. Besu Configuration

The hyperledger Besu uses 2 configuration files: config.toml and genesis.json. In the CDK we are using the Bacen files. You can check it [here](https://github.com/bacen/pilotord-kit-onboarding/blob/main/ingresso.md#configura%C3%A7%C3%A3o-do-n%C3%B3-do-participante)

*Note: If you are not using the Besu Hyperledger to connect into BACEN, you can change that in the file:/aws-besu-realdigital/single_node/real_digital_besu_ec2/real_digital_besu_ec2_stack.py and session: ## DOWNLOAD BACEN CONFIG FILES ##.*


### 5.1 Check if Besu is Working

To check if the Besu is connected to the chain: 

`curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8545`

To check the block sync: 

`curl -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' localhost:8545`

### 5.2 Troubleshooting

If you are getting the error: 
`bash[2901]: Unable to load genesis file. java.io.FileNotFoundException: /caminho/para/o/arquivo/genesis.json (No such file or directory)` 

Its because you should edit the config.toml downloaded from Bacen, and change the lines

data-path="/caminho/para/a/pasta/data"
genesis-file="/caminho/para/o/arquivo/genesis.json"

to the correctly path. 

Enjoy!

## 6. Clean Up

To delete the Besu Single Node, run: 

`cdk destroy`

And all the resources will be deleted. 

