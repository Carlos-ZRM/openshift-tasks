Check  privileges of `admin` user for get pods in namespace `bar-demo`. 

~~~ bash
% oc get pod -n bar-demo --as admin  
Error from server (Forbidden): pods is forbidden: User "admin" cannot list resource "pods" in API group "" in the namespace "bar-demo"
~~~

Create cluster role `custom-viewer` from file.

~~~ bash
% oc apply -f clusterrole-view.yaml  
clusterrole.rbac.authorization.k8s.io/custom-viewer created
~~~

Add cluster role policy to user admin into namespace bar-demo

~~~ bash
% oc adm policy add-cluster-role-to-user custom-viewer admin -n bar-demo
clusterrole.rbac.authorization.k8s.io/custom-viewer added: "admin"
~~~


% oc get pod -n bar-demo --as admin                                     
NAME                       READY   STATUS    RESTARTS   AGE
bar-app-54fdcf857c-5ddz8   1/1     Running   0          97m
bar-app-54fdcf857c-wvxsr   1/1     Running   0          89m
baz-app-848fcf7bc7-p54gh   1/1     Running   0          97m
% oc oc port-forward pod/bar-app-54fdcf857c-5ddz8 5000:5000
error: unknown command "oc" for "oc"

Did you mean this?
        cp
%  oc port-forward pod/bar-app-54fdcf857c-5ddz8 5000:5000 --as admin

Forwarding from 127.0.0.1:5000 -> 5000
Forwarding from [::1]:5000 -> 5000
