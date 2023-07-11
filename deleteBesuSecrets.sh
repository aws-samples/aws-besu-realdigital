#!/bin/bash

prefix="besu"

# Get a list of secret names
secret_names=$(aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, '$prefix')].Name" --output text)

# Loop through each secret and force delete it
for secret_name in $secret_names; do
  echo "Deleting secret: $secret_name"
  aws secretsmanager delete-secret --secret-id "$secret_name" --force-delete-without-recovery
done
