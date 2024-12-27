#!/bin/bash

set -euo pipefail  # Enable strict error handling

prefix="besu"
MAX_PARALLEL=5     # Maximum number of parallel deletions

# Function to check AWS CLI and credentials
check_prerequisites() {
    if ! command -v aws &>/dev/null; then
        echo "Error: AWS CLI is not installed or not in PATH"
        exit 1
    fi

    if ! aws sts get-caller-identity &>/dev/null; then
        echo "Error: AWS credentials not configured or invalid"
        exit 1
    fi
}

# Function to delete a single secret
delete_secret() {
    local secret_name="$1"
    echo "Deleting secret: $secret_name"
    if aws secretsmanager delete-secret \
        --secret-id "$secret_name" \
        --force-delete-without-recovery \
        --output json &>/dev/null; then
        echo "Successfully deleted: $secret_name"
    else
        echo "Failed to delete: $secret_name"
        return 1
    fi
}

# Main execution
main() {
    check_prerequisites

    echo "Fetching secrets with prefix '$prefix'..."
    
    # Get all secret names in one call and process them
    local secret_names
    secret_names=$(aws secretsmanager list-secrets \
        --query "SecretList[?starts_with(Name, '${prefix}')].Name" \
        --output text)

    if [ -z "$secret_names" ]; then
        echo "No secrets found with prefix '$prefix'"
        exit 0
    fi

    # Count total secrets
    total_secrets=$(echo "$secret_names" | wc -w)
    echo "Found $total_secrets secrets to delete"

    # Process secrets in parallel using background processes
    local pids=()
    for secret in $secret_names; do
        delete_secret "$secret" &
        pids+=($!)
        
        # Control number of parallel processes
        if [ ${#pids[@]} -ge $MAX_PARALLEL ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done

    # Wait for remaining processes
    wait

    echo "Secret deletion process completed"
}

# Execute main function
main
