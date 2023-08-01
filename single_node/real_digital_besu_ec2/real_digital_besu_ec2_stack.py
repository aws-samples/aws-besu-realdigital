from constructs import Construct
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam
)

class RealDigitalBesuEc2Stack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # VPC # 
        vpc = ec2.Vpc(self, "Vpc",
            ip_addresses=ec2.IpAddresses.cidr("192.168.0.0/16")
        )
        
        # IAM Role # 
        role = iam.Role(
            self,
            "InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ],
        )
        
        # Security Group #
        sec_grp= ec2.SecurityGroup(self, 'ec2-sec-grp', vpc=vpc, allow_all_outbound=True)

        sec_grp.add_ingress_rule(
            peer=ec2.Peer.ipv4('172.16.0.0/24'), 
            description='inbound SSH', 
            connection=ec2.Port.tcp(22))

        # EC2 Instance #
        instance = ec2.Instance(
            self
            , "Instance"
            , instance_type=ec2.InstanceType("t2.micro")
            , machine_image=ec2.MachineImage.latest_amazon_linux(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            )
            , vpc=vpc
            , role=role
            , security_group =sec_grp
        )
        commands = '''
#!/bin/bash
echo " ##  INIT USER DATA ## "
sudo yum update -y 

# Install Java # 
echo " ##  INSTALL JAVA ## "
mkdir -p /usr/lib/jvm
cd /usr/lib/jvm
wget https://download.oracle.com/java/20/latest/jdk-20_linux-x64_bin.rpm
rpm -i jdk-20_linux-x64_bin.rpm 
export JAVA_HOME="/usr/lib/jvm/jdk-20-oracle-x64/"

# Install Besu #
echo " ##  INSTALL BESU ## "
mkdir -p /usr/lib/besu
cd /usr/lib/besu
touch besu.log
mkdir -p /data/besu
mkdir -p /etc/genesis
touch /etc/genesis/genesis.json

wget https://hyperledger.jfrog.io/hyperledger/besu-binaries/besu/23.4.1/besu-23.4.1.tar.gz / sha256: 49d3a7a069cae307497093d834f873ce7804a46dd59207d5e8321459532d318e

 tar -xvzf besu-23.4.1.tar.gz

cd besu-23.4.1/

bin/besu --help

echo "## CONFIG BESU ON INIT ##"
sudo touch /usr/lib/systemd/system/besu.service

sudo cat <<EOF >/usr/lib/systemd/system/besu.service
[Unit]
Description=Besu Enterprise Ethereum java client

[Service]
User=root
Type=oneshot
WorkingDirectory=/usr/lib/besu/besu-23.4.1
ExecStart= /bin/bash -c "cd /usr/lib/besu/besu-23.4.1 && bin/besu --config-file=config.toml --min-gas-price=0 --bootnodes=enode:x-x-x-x//@0.0.0.0:30303,enode:x-x-x-x//@0.0.0.0:30303"
SuccessExitStatus=143
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
echo "## START BESU ##"
# Create and start service besu # 
systemctl enable besu
systemctl daemon-reload
systemctl start besu
'''

        instance.user_data.add_commands(commands)

