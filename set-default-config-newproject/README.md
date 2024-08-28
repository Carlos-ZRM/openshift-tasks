## 1 create file template

~~~ 
oc adm create-bootstrap-project-template -o yaml > templateex.yaml
~~~

## Modify templates

~~~ yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  creationTimestamp: null
  name: project-request
namespace: openshift-config

objects:
- apiVersion: project.openshift.io/v1
  kind: Project
- apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-same-namespace
  spec:
    podSelector: {}
    ingress:
    - from:
      - podSelector: {}
- apiVersion: v1
  kind: ResourceQuota
  metadata:
    name: core-object-counts
  spec:
    hard:
      configmaps: "10" 
      persistentvolumeclaims: "4" 
      replicationcontrollers: "20" 
      secrets: "10" 
      services: "10" 
      services.loadbalancers: "2"
~~~

## 2 apply template

~~~ bash
oc apply -f template.yaml  -n openshift-config
~~~

## 3. Set template into project config for a cluster
~~~ bash
oc edit project.config.openshift.io/cluster
~~~

~~~ Yaml
spec:
  projectRequestTemplate:
    name: project-request
~~~

## Create new project 

~~~ bash
oc new-project aanew 
oc label namespace  aanew xpk=true
~~~