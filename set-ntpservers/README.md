butane 99-worker-zone1-chrony.bu -o 99-worker-zone1-chrony.yaml
butane 99-worker-zone2-chrony.bu -o 99-worker-zone2-chrony.yaml

oc label node ip-10-0-24-139.us-east-2.compute.internal node-role.kubernetes.io/zone1=
oc label node ip-10-0-27-111.us-east-2.compute.internal node-role.kubernetes.io/zone2=

~~~ bash
NAME                                        STATUS   ROLES                  AGE   VERSION
ip-10-0-16-180.us-east-2.compute.internal   Ready    control-plane,master   25h   v1.29.11+ef2a55c
ip-10-0-24-139.us-east-2.compute.internal   Ready    worker,zone1           25h   v1.29.11+ef2a55c
ip-10-0-27-111.us-east-2.compute.internal   Ready    worker,zone2           25h   v1.29.11+ef2a55c
ip-10-0-41-192.us-east-2.compute.internal   Ready    control-plane,master   25h   v1.29.11+ef2a55c
ip-10-0-43-143.us-east-2.compute.internal   Ready    control-plane,master   25h   v1.29.11+ef2a55c
ip-10-0-46-164.us-east-2.compute.internal   Ready    worker                 25h   v1.29.11+ef2a55c
~~~
watch "oc get mcp; oc get nodes"
