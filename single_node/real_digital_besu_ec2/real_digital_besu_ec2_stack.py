from constructs import Construct
from aws_cdk import (
    Stack, CfnParameter,
    aws_ec2 as ec2,
    aws_iam as iam
)

class RealDigitalBesuEc2Stack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # VPC # 
        vpc = ec2.Vpc(self, "Vpc",
            ip_addresses=ec2.IpAddresses.cidr(self.node.try_get_context('VpcCIDR'))
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
            peer=ec2.Peer.ipv4(self.node.try_get_context('BesuCIDR')), 
            description='Besu cluster',
            connection=ec2.Port.tcp_range(30000, 30009)
        )

        sec_grp.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.node.try_get_context('BesuCIDR')), 
            description='Besu Cluster', 
            connection=ec2.Port.tcp(30303)
        )
        
        # EC2 Instance #
        
        instance = ec2.Instance(
            self
            , "Instance"
            , instance_type=ec2.InstanceType(self.node.try_get_context('InstanceType'))
            , machine_image=ec2.MachineImage.latest_amazon_linux(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            )
            , vpc=vpc
            # To launch the EC2 into a public subnet, uncomment the 2 lines below: 
            #, vpc_subnets=ec2.SubnetSelection(
            #                    subnet_type=ec2.SubnetType.PUBLIC)
            , role=role
            , security_group=sec_grp
        )

        instance.instance.add_property_override("BlockDeviceMappings", [{
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": "100",
                "VolumeType": "gp3",
                "DeleteOnTermination": "true"
            }
        },
        ])
        BootNodeAddress = self.node.try_get_context('BootNodes')
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

wget https://hyperledger.jfrog.io/hyperledger/besu-binaries/besu/23.4.1/besu-23.4.1.tar.gz / sha256: 49d3a7a069cae307497093d834f873ce7804a46dd59207d5e8321459532d318e

tar -xvzf besu-23.4.1.tar.gz

cd besu-23.4.1/

bin/besu --help

echo "## DOWNLOAD CONFIG FILES"
wget https://raw.githubusercontent.com/bacen/pilotord-kit-onboarding/main/genesis.json -P /etc/genesis
wget https://raw.githubusercontent.com/bacen/pilotord-kit-onboarding/main/config.toml -P /usr/lib/besu/besu-23.4.1

echo "## EDITING CONFIG"

sed -i 's;"/caminho/para/o/arquivo/genesis.json";"/etc/genesis/genesis.json";g' /usr/lib/besu/besu-23.4.1/config.toml

echo "## CONFIG BESU ON INIT ##"

sudo touch /usr/lib/systemd/system/besu.service

sudo cat <<EOF >/usr/lib/systemd/system/besu.service
[Unit]
Description=Besu Enterprise Ethereum java client

[Service]
User=root
Type=oneshot
WorkingDirectory=/usr/lib/besu/besu-23.4.1
ExecStart= /bin/bash -c "cd /usr/lib/besu/besu-23.4.1 && bin/besu --config-file=config.toml --min-gas-price=0 --bootnodes=enode$BOOTNODE_ADDRESS"
SuccessExitStatus=143


[Install]
WantedBy=multi-user.target
EOF


echo "## START BESU ##"
echo "# Create and start service besu #"

systemctl enable besu
systemctl daemon-reload
systemctl start besu
systemctl status besu
'''
        commands = commands.replace("BOOTNODE_ADDRESS", BootNodeAddress)
        instance.user_data.add_commands(commands)

