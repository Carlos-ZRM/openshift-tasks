#!/bin/bash

# Loop through every namespace
for ns in $(oc get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    echo "==========================================================" >> output.log
    echo " NAMESPACE: $ns"
    echo " NAMESPACE: $ns" >>  output.log
    echo "=========================================================="
    
    # Run your specific formatter
    oc get pods -n "$ns" -o jsonpath='{range .items[*]}{"\n"}POD: {.metadata.name}{range .spec.containers[*]}{"\n"}  - CONTAINER: {.name}{"\n"}    IMAGE:     {.image}{end}{"\n"}{end}' >>  output.log
    
    echo -e "\n" >>  output.log # Adds extra spacing between namespaces 
done
