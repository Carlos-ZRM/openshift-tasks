
## Get must gather

~~~yaml
oc adm must-gather --image=$(oc get csv compliance-operator.v1.6.0 -o=jsonpath='{.spec.relatedImages[?(@.name=="must-gather")].image}')

~~~

## Compliance filters
~~~ yaml
oc get profile.compliance -n openshift-compliance
~~~

## Create profile

~~~ yaml
oc apply -f 0-my-scansetting.yaml

oc create -f  1-my-scan-binding.yaml
~~~


### view progress

~~~  yaml

oc get compliancescan -w -n openshift-compliance

~~~

## Re run scan

~~~ yaml
oc -n openshift-compliance \
annotate compliancescans/ocp4-cis compliance.openshift.io/rescan=

oc get compliancescan -w -n openshift-compliance
~~~


## Troubleshoting

~~~  yaml

oc get pods -l workload=scanner --show-labels -w 

oc -n openshift-compliance get cm \
-l compliance.openshift.io/scan-name=ocp4-cis,complianceoperator.openshift.io/scan-script=

oc get cronjobs

~~~


