
# Real Digital - Besu Single Node 

This repo intends to support the creation of a single node Besu Hyperledger running into Amazon EC2 in private Amazon VPC using AWS CDK.


## How to 

### 1. Configure Python and download CDK. 
```
$ python3 -m venv .venv
```

After the init process completes and the virtualenv is created, you can use the following
step to activate your virtualenv.

```
$ source .venv/bin/activate
```

If you are a Windows platform, you would activate the virtualenv like this:

```
% .venv\Scripts\activate.bat
```

Once the virtualenv is activated, you can install the required dependencies.

```
$ pip install -r requirements.txt
```

At this point you can now synthesize the CloudFormation template for this code.

```
$ cdk synth
```

###  CDK Helpfull commands

 * `cdk ls`          list all stacks in the app
 * `cdk synth`       emits the synthesized CloudFormation template
 * `cdk deploy`      deploy this stack to your default AWS account/region
 * `cdk diff`        compare deployed stack with current state
 * `cdk docs`        open CDK documentation

### 2. Get the Besu configuration files 

TBD 

### 3. Restart Besu with the new files

To start properly, you need to configure two files: `config.toml` and `genesis.json`. 

[BACEN files:](https://github.com/bacen/pilotord-kit-onboarding/blob/main/ingresso.md) 

### 4. Check if Besu is Working

To check if the Besu is connected to the chain: 

`curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8545`

To check the block sync: 

`curl -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' localhost:8545`

Enjoy!
