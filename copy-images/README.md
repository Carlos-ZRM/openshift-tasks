# Demo

| Origen | Destino |
|---|---|
| OCP A | OCP B |
| dmdbaego.eastus.aroapp.io | cluster-ggbkq.ggbkq.sandbox240.opentlc.com |


# 1. Congigure OCP A

## 1.1 Generate service account OCP A

~~~ bash

export HOST_OCPA=$(oc whoami --show-server)
export TOKEN_OCPA=$(oc create token -n default  copyimage-ocpa --duration=8760h)

oc create sa copyimage-ocpa -n default

oc adm policy add-cluster-role-to-user cluster-admin -z copyimage-ocpa -n default

oc login --server=$HOST_OCPA --token=$TOKEN_OCPA --kubeconfig=./kubeconfig-ocpa

~~~

## 1.2 Make public registry


~~~ bash

oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge --kubeconfig=./kubeconfig-ocpa

export REGISTRY_OCPA=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' --kubeconfig=./kubeconfig-ocpa)

~~~

[https://docs.openshift.com/container-platform/4.17/registry/securing-exposing-registry.html](https://docs.openshift.com/container-platform/4.17/registry/securing-exposing-registry.html)

## 1.3 Login skopeo 

~~~ bash

skopeo login -u copyimage-ocpa  -p $TOKEN_OCPA  $REGISTRY_OCPA

~~~



#  2. Generate service account OCP B

## 2.1 Generate service account OCP B

~~~ bash
export HOST_OCPB=$(oc whoami --show-server)
export TOKEN_OCPB=$(oc create token -n default  copyimage-ocpb --duration=8760h)

oc create sa copyimage-ocpb -n default

oc adm policy add-cluster-role-to-user cluster-admin -z copyimage-ocpb -n default



oc login --server=$HOST_OCPB --token=$TOKEN_OCPB --kubeconfig=./kubeconfig-ocpb

~~~

## 2.2 Make public registry


~~~ bash

oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge --kubeconfig=./kubeconfig-ocpb


export REGISTRY_OCPB=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' --kubeconfig=./kubeconfig-ocpb)

~~~

[https://docs.openshift.com/container-platform/4.17/registry/securing-exposing-registry.html](https://docs.openshift.com/container-platform/4.17/registry/securing-exposing-registry.html)

 ## 2.3 Login skopeo 

~~~ bash

skopeo login -u copyimage-ocpb  -p $TOKEN_OCPB  $REGISTRY_OCPB

~~~


## 3 Import registry app-ocpa into OCP B from OCP A

## 3.1 Get IS from OPC A

~~~ bash
oc get is -n source --kubeconfig=./kubeconfig-ocpa

export REPO_OCPA=default-route-openshift-image-registry.apps.dmdbaego.eastus.aroapp.io/source/app-ocpa:latest
~~~

## 3.2 Create IS in OCP B

~~~ bash
oc create is app-ocpa -n target --kubeconfig=./kubeconfig-ocpb

oc get is -n source --kubeconfig=./kubeconfig-ocpb

export REPO_OCPB=default-route-openshift-image-registry.apps.cluster-ggbkq.ggbkq.sandbox240.opentlc.com/target/app-ocpa:latest

skopeo copy --src-registry-token=$TOKEN_OCPA docker://<SRCOCR>/<PROJECT>/<IMAGE>:<TAG>  --dest-registry-token=$TOKEN_OCPB default-route-openshift-image-registry.apps.cluster-ggbkq.ggbkq.sandbox240.opentlc.com/target/app-ocpa:latest

skopeo copy --src-registry-token=$TOKEN_OCPA  --dest-registry-token=$TOKEN_OCPA docker://$REPO_OCPA docker://$REPO_OCPB

~~~

Skopeo
~~~ bash

export HOST_OCPA=$(oc whoami --show-server --kubeconfig=./kubeconfig-ocpa)
export TOKEN_OCPA=$(oc whoami --show-token --kubeconfig=./kubeconfig-ocpa)
export REGISTRY_OCPA=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' --kubeconfig=./kubeconfig-ocpa)

#oc login -u copyimage-ocpa $HOST_OCPA --token $TOKEN_OCPA
skopeo login -u copyimage-ocpa  -p $TOKEN_OCPA  $REGISTRY_OCPA
podman login -u copyimage-ocpa  -p $TOKEN_OCPA  $REGISTRY_OCPA

export HOST_OCPB=$(oc whoami --show-server --kubeconfig=./kubeconfig-ocpb)
export TOKEN_OCPB=$(oc whoami --show-token --kubeconfig=./kubeconfig-ocpb)
export REGISTRY_OCPB=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}' --kubeconfig=./kubeconfig-ocpb)

skopeo login -u copyimage-ocpb  -p $TOKEN_OCPB  $REGISTRY_OCPB

podman login -u copyimage-ocpb  -p $TOKEN_OCPB  $REGISTRY_OCPB

~~~

practica
~~~ bash

oc import-image ubi9/httpd-24:9.5-1737481813 --from=registry.redhat.io/ubi9/httpd-24:9.5-1737481813 --confirm -n source --kubeconfig=./kubeconfig-ocpa

oc get is -n source --kubeconfig=./kubeconfig-ocpa

oc create is httpd -n target --kubeconfig=./kubeconfig-ocpb
oc get is -n target --kubeconfig=./kubeconfig-ocpb

skopeo copy docker://registry.redhat.io/ubi9/httpd-24:9.5-1737481813 docker://default-route-openshift-image-registry.apps.cluster-ggbkq.ggbkq.sandbox240.opentlc.com/target/app-dest 


skopeo copy docker://default-route-openshift-image-registry.apps.dmdbaego.eastus.aroapp.io/source/httpd-24:9.5-1737481813 docker://default-route-openshift-image-registry.apps.cluster-ggbkq.ggbkq.sandbox240.opentlc.com/target/httpd
~~~