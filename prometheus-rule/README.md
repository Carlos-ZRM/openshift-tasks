# Create alerts for users projects

## 1. Install

### Prerequisitos

#### Enable used defined monitoring

![https://docs.redhat.com/en/documentation/openshift_container_platform/4.15/html/monitoring/configuring-user-workload-monitoring#enabling-monitoring-for-user-defined-projects_preparing-to-configure-the-monitoring-stack-uwm](https://docs.redhat.com/en/documentation/openshift_container_platform/4.15/html/monitoring/configuring-user-workload-monitoring#enabling-monitoring-for-user-defined-projects_preparing-to-configure-the-monitoring-stack-uwm)


*validate if is enabled and running*

~~~ bash
oc -n openshift-monitoring get configmap cluster-monitoring-config -o yaml | grep enableUserWorkload

oc -n openshift-user-workload-monitoring get pod

~~~

*Patch enableUserWorkload to true*

~~~ bash
oc -n openshift-monitoring patch configmap cluster-monitoring-config --type=merge -p '{"data":{"config.yaml":"enableUserWorkload: true"}}'
~~~


*Validate if monitoring for user defined projects is running

~~~ bash
oc -n openshift-user-workload-monitoring get pod
~~~

*Create a custom alerts for user defined projects*

~~~ bash
oc -n openshift-user-workload-monitoring patch configmap user-workload-monitoring-config --type=merge -p '{
  "data": {
    "config.yaml": "alertmanager:\n  enabled: true\n  enableAlertmanagerConfig: true\n"
  }
}'

oc -n openshift-user-workload-monitoring get alertmanager
~~~
#### Enable monitoring for a namespace

~~~ bash
oc label namespace xpk 'openshift.io/user-monitoring=true'
~~~

## Example

[https://developers.redhat.com/articles/2023/10/03/how-configure-openshift-application-monitoring-and-alerts](https://developers.redhat.com/articles/2023/10/03/how-configure-openshift-application-monitoring-and-alerts)

~~~ bash
oc apply -f 1-example-app.yaml
oc apply -f 2-ServiceMonitor.yaml
oc apply -f 3-Prometheusrule.yaml
~~~

*Get url*

~~~ bash
ROUTE_HOST=$(oc get route route-mixed-clam -n monitoringdemo -o jsonpath='{.spec.host}')
~~~

*Test*

~~~ bash
while true; do curl -I https://$ROUTE_HOST  ; done;
~~~