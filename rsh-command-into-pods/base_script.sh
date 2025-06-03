#!/bin/bash

# OpenShift Common Commands Script
#
# Make sure you have the OpenShift CLI (oc) installed and configured.
#
# Usage:
# 1. Make the script executable: chmod +x openshift_script.sh
# 2. Run the script: ./openshift_script.sh
#
# IMPORTANT:
# - Replace placeholder values (like <YOUR_OPENSHIFT_API_URL>, <YOUR_TOKEN>, etc.)
#   with your actual OpenShift cluster details and application specifics.
# - Some commands that perform deletions are commented out by default for safety.
#   Uncomment them with caution.


# --- Configuration Variables ---
COMMAND_TO_EXECUTE_IN_POD="date" # Define the command to be executed in pods

# --- Timestamp and Log File Setup for Helper Functions ---
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
# Sanitize COMMAND_TO_EXECUTE_IN_POD for use in a filename
# Replace spaces and slashes with underscores, remove other non-alnum characters (except _-), squeeze underscores
SANITIZED_COMMAND_NAME=$(echo "${COMMAND_TO_EXECUTE_IN_POD}" | tr '[:space:]/' '_' | tr -cs '[:alnum:]_-' '_' | sed 's/__*/_/g' | sed 's/^_//g' | sed 's/_$//g')
if [ -z "${SANITIZED_COMMAND_NAME}" ]; then
    SANITIZED_COMMAND_NAME="unknown_command"
fi
HELPER_LOG_FILE="oc-rsh-${SANITIZED_COMMAND_NAME}_${TIMESTAMP}.log"

# --- CSV File Setup ---
# Changed CSV_FILE name as per user request
CSV_FILE="Result_${SANITIZED_COMMAND_NAME}_${TIMESTAMP}.csv"

# --- Helper Functions ---
log_info() {
    local message="[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "${message}"                 # Print to console stdout
    echo "${message}" >> "${HELPER_LOG_FILE}" # Append to helper log file
}

log_error() {
    local message="[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "${message}" >&2              # Print to console stderr
    echo "${message}" >> "${HELPER_LOG_FILE}" # Append to helper log file
}

log_warning() {
    local message="[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "${message}" >&2              # Print to console stderr
    echo "${message}" >> "${HELPER_LOG_FILE}" # Append to helper log file
}

# --- Script Start ---
log_info "Starting OpenShift operations script..."
log_info "Command to execute in each pod: '${COMMAND_TO_EXECUTE_IN_POD}'"
log_info "Helper function logs will be saved to: ${HELPER_LOG_FILE}"
log_info "Output CSV file for command results will be: ${CSV_FILE}" # Log the new CSV file name

# Create CSV file and write header.
echo "Namespace,ResourceType,ResourceName,PodName,CommandOutput" > "${CSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Failed to create or write header to CSV file: ${CSV_FILE}"
    # Also log to helper log file already handled by log_error
    exit 1
fi

# 1. Obtain a list of namespaces that contain "prd" and do not contain "kube" or "openshift"
log_info "Fetching and filtering namespaces..."
list_ns=$(oc get projects -o custom-columns=NAME:.metadata.name --no-headers=true | grep -vE 'kube|openshift' || true)

if [ -z "$list_ns" ]; then
    log_info "No namespaces found matching the criteria (contains 'prd', does not contain 'kube' or 'openshift')."
else
    log_info "Found the following namespaces to process:"
    # Log the list of namespaces to the helper log file as well
    echo "$list_ns" >> "${HELPER_LOG_FILE}" # Direct append for multi-line content
    echo "$list_ns" # And to console

    echo # Newline for better readability on console

    # Store all found deployment/dc names here (optional, as primary output is now CSV)
    ALL_DEPLOYMENT_NAMES=""

    # 2. Iterate the list list_ns
    while IFS= read -r ns_name; do
        if [ -z "$ns_name" ]; then # Skip empty lines if any
            continue
        fi
        log_info "Processing namespace: ${ns_name}"

        # Process Deployments
        log_info "  Fetching deployments in ${ns_name}..."
        # Get deployment names. Using custom-columns for just the name.
        oc get deployments -n "${ns_name}" -o custom-columns=NAME:.metadata.name --no-headers=true 2>/dev/null | while IFS= read -r dep_name; do
            if [ -z "$dep_name" ]; then continue; fi # Skip empty lines
            log_info "    - Found Deployment: ${dep_name}"
            ALL_DEPLOYMENT_NAMES+="${ns_name}/Deployment/${dep_name}\n"

            # Get pods for this deployment
            log_info "      Fetching pods for Deployment ${dep_name}..."
            SELECTOR_JSON=$(oc get deployment "${dep_name}" -n "${ns_name}" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
            if [ -n "$SELECTOR_JSON" ] && [ "$SELECTOR_JSON" != "{}" ]; then
                SELECTOR=$(echo "$SELECTOR_JSON" | sed 's/[{}]//g; s/"//g; s/:/=/g')
            else
                log_warning "      Could not determine selector for Deployment ${dep_name} from .spec.selector.matchLabels. Trying default app label."
                SELECTOR="app=${dep_name}"
            fi
            log_info "        Using selector: ${SELECTOR}"

            oc get pods -n "${ns_name}" -l "${SELECTOR}" -o custom-columns=NAME:.metadata.name --no-headers=true 2>/dev/null | while IFS= read -r pod_name; do
                if [ -z "$pod_name" ]; then continue; fi # Skip empty lines
                log_info "        - Found Pod: ${pod_name} for Deployment ${dep_name}"

                # Execute the defined command in the pod
                log_info "          Executing '${COMMAND_TO_EXECUTE_IN_POD}' in pod ${pod_name}..."
                # Note: Using $COMMAND_TO_EXECUTE_IN_POD directly. If it has spaces or special chars, it might need careful handling (e.g. eval or splitting into array)
                # For simple commands like 'date' or 'ls -l /tmp', this should be fine.
                command_result=$(oc exec "${pod_name}" -n "${ns_name}" -- bash -c "${COMMAND_TO_EXECUTE_IN_POD}" 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$command_result" ]; then
                    log_info "          Output from pod ${pod_name}: ${command_result}"
                    # Write to CSV: Namespace,ResourceType,ResourceName,PodName,CommandOutput
                    echo "${ns_name},Deployment,${dep_name},${pod_name},\"${command_result}\"" >> "${CSV_FILE}"
                else
                    log_warning "          Failed to execute '${COMMAND_TO_EXECUTE_IN_POD}' or got empty result from pod ${pod_name}."
                    echo "${ns_name},Deployment,${dep_name},${pod_name},ERROR_EXECUTING_COMMAND" >> "${CSV_FILE}"
                fi
            done
        done || log_info "  No deployments found or processed in ${ns_name}."


        # Process DeploymentConfigs
        log_info "  Fetching deployment configs in ${ns_name}..."
        # Get deployment config names
        oc get dc -n "${ns_name}" -o custom-columns=NAME:.metadata.name --no-headers=true 2>/dev/null | while IFS= read -r dc_name; do
            if [ -z "$dc_name" ]; then continue; fi # Skip empty lines
            log_info "    - Found DeploymentConfig: ${dc_name}"
            ALL_DEPLOYMENT_NAMES+="${ns_name}/DeploymentConfig/${dc_name}\n"

            # Get pods for this deployment config
            log_info "      Fetching pods for DeploymentConfig ${dc_name}..."
            SELECTOR_JSON=$(oc get dc "${dc_name}" -n "${ns_name}" -o jsonpath='{.spec.selector}' 2>/dev/null)
             if [ -n "$SELECTOR_JSON" ] && [ "$SELECTOR_JSON" != "{}" ]; then
                SELECTOR=$(echo "$SELECTOR_JSON" | sed 's/[{}]//g; s/"//g; s/:/=/g')
            else
                log_warning "      Could not determine selector for DC ${dc_name} from .spec.selector. Trying default 'deploymentconfig' label."
                SELECTOR="deploymentconfig=${dc_name}" # Common label for DCs
            fi
            log_info "        Using selector: ${SELECTOR}"

            oc get pods -n "${ns_name}" -l "${SELECTOR}" -o custom-columns=NAME:.metadata.name --no-headers=true 2>/dev/null | while IFS= read -r pod_name; do
                if [ -z "$pod_name" ]; then continue; fi # Skip empty lines
                log_info "        - Found Pod: ${pod_name} for DeploymentConfig ${dc_name}"

                # Execute the defined command in the pod
                log_info "          Executing '${COMMAND_TO_EXECUTE_IN_POD}' in pod ${pod_name}..."
                command_result=$(oc exec "${pod_name}" -n "${ns_name}" -- bash -c "${COMMAND_TO_EXECUTE_IN_POD}" 2>/dev/null)

                if [ $? -eq 0 ] && [ -n "$command_result" ]; then
                    log_info "          Output from pod ${pod_name}: ${command_result}"
                    # Write to CSV: Namespace,ResourceType,ResourceName,PodName,CommandOutput
                    echo "${ns_name},DeploymentConfig,${dc_name},${pod_name},\"${command_result}\"" >> "${CSV_FILE}"
                else
                    log_warning "          Failed to execute '${COMMAND_TO_EXECUTE_IN_POD}' or got empty result from pod ${pod_name}."
                    echo "${ns_name},DeploymentConfig,${dc_name},${pod_name},ERROR_EXECUTING_COMMAND" >> "${CSV_FILE}"
                fi
            done
        done || log_info "  No deployment configs found or processed in ${ns_name}."
        echo # Newline for better readability between namespaces on console
    done <<< "$list_ns"

    log_info "All collected deployment and deploymentConfig names (namespace/type/name) for logging (also in helper log):"
    if [ -n "$ALL_DEPLOYMENT_NAMES" ]; then
        printf "%b" "${ALL_DEPLOYMENT_NAMES}" # To console
        printf "%b" "${ALL_DEPLOYMENT_NAMES}" >> "${HELPER_LOG_FILE}" # To helper log
    else
        log_info "No deployments or deploymentConfigs found across the processed namespaces."
    fi
    log_info "CSV data with command outputs written to ${CSV_FILE}"
fi
log_info "Finished searching for deployments and deploymentconfigs."
echo # Extra newline for separation on console



# --- Script End ---
log_info "OpenShift operations script finished."
exit 0
