#!/bin/bash

# --- Configuration ---
# Replace with your actual hostnames or IP addresses
HOSTS=("master-0.xpk201.lab.upshift.rdu2.redhat.com" "master-1.xpk201.lab.upshift.rdu2.redhat.com" "master-2.xpk201.lab.upshift.rdu2.redhat.com")

# SSH connection details
SSH_USER="core"
SSH_KEY="~/.ssh/id_rsa"

# --- Define commands as an array ---
# This makes it easier to add, remove, or comment out commands
COMMANDS_ARRAY=(
    "echo '--- IP Address for tun0 ---'"
    "ip addr show tun0"
    "echo"
    "echo '--- Status of kubelet ---'"
    "systemctl --no-pager status kubelet" # --no-pager prevents interactive mode
    "echo"
    "echo '--- Status of kubectl (as requested) ---'"
    "systemctl --no-pager status kubectl"
)

# --- Join the array into a single command string separated by semicolons ---
COMMAND_STRING=$(printf "%s;" "${COMMANDS_ARRAY[@]}")

# --- Script Execution ---
# Ensure the SSH key has the correct permissions
chmod 600 "$SSH_KEY"

# Loop through each host and execute the commands
for HOST in "${HOSTS[@]}"; do
    echo "############################################################"
    echo "## Connecting to: $HOST"
    echo "############################################################"
    
    # Execute the single, combined command string
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${HOST}" "$COMMAND_STRING"
    
    echo "" # Add a blank line for better readability
done

echo "--- Script finished ---"
