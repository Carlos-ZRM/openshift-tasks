

#!/bin/bash

# Obtén la lista de namespaces, excluyendo los que contienen 'openshift' o 'kube'
my_date=$(date +%s)

namespaces=$(oc get namespaces --no-headers -o=custom-columns=':.metadata.name' | egrep -v 'openshift|kube')
my_dir="/tmp/api-resource"
mkdir -p ${my_dir}

echo Date $my_date
# Recorre cada namespace
for namespace in $namespaces; do
  
  echo "$my_date imprimiendo $namespace"
  oc get "$(oc api-resources --namespaced=true --verbs=list -o name | awk '{printf "%s%s",sep,$0;sep=","}')"  --ignore-not-found -n "$namespace" -o=custom-columns=KIND:.kind,API:apiVersion,NAME:.metadata.name,NAMESPACE:.metadata.namespace --sort-by='kind' >> "${my_dir}/"$namespace"_resources_"$my_date".csv"
done