#!/bin/bash

# Loop through every namespace
for ns in $(oc get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    echo "=========================================================="
    echo " NAMESPACE: $ns"
    echo "=========================================================="
    
    # Run your specific formatter
    oc get pods -n "$ns" -o jsonpath='{range .items[*]}{"\n"}POD: {.metadata.name}{range .spec.containers[*]}{"\n"}  - CONTAINER: {.name}{"\n"}    IMAGE:     {.image}{end}{"\n"}{end}'
    
    echo -e "\n" # Adds extra spacing between namespaces
done
