

oc create namespace recovery
 
oc create serviceaccount recovery-adm -n recovery

oc create clusterrolebinding recovery-adm-cluster-admin-binding  --clusterrole=cluster-admin  --serviceaccount=recovery:recovery-adm

oc create token recovery-adm -n recovery --duration=720h

CLUSTER_SERVER=$(oc whoami --show-server)

TOKEN=$(oc create token recovery-adm -n recovery --duration=720h)


oc login --server=$CLUSTER_SERVER --token=$TOKEN --kubeconfig=./kubeconfig-recovery --insecure-skip-tls-verify=true



oc --kubeconfig=kubeconfig-recovery whoami

oc --kubeconfig=kubeconfig-recovery auth can-i create resourcequotas -n recovery

