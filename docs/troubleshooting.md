# Troubleshooting Guide

## Index

- [Troubleshooting AKS cluster creation](#troubleshooting-aks-cluster-creation)
    + [Service principal clientID not found](#service-principal-clientid-not-found)
- [Troubleshooting BKPR installation](#troubleshooting-bkpr-installation)
    + [Object with the same value for property exists](#object-with-the-same-value-for-property-exists)
- [Troubleshooting BKPR Ingress](#troubleshooting-bkpr-ingress)
    + [Let's Encrypt](#lets-encrypt)
- [Troubleshooting DNS](#troubleshooting-dns)
    + [Unable to resolve DNS addresses](#unable-to-resolve-dns-addresses)
    + [ExternalDNS pods are not starting](#externaldns-pods-are-not-starting)
    + [ExternalDNS is not updating DNS zone records](#externaldns-is-not-updating-dns-zone-records)
    + [DNS glue records are not configured](#dns-glue-records-are-not-configured)
    + [DNS propagation has not completed](#dns-propagation-has-not-completed)

## Troubleshooting AKS cluster creation

### Service principal clientID not found

If you notice the following error message from `az aks create`, it could indicate the Azure authentication token has expired.

```
Operation failed with status: 'Bad Request'. Details: Service principal clientID: <REDACTED>
not found in Active Directory tenant <REDACTED>, Please see https://aka.ms/acs-sp-help for more details.
```

__Troubleshooting__:

Please clear your Azure profile directory with `rm -rf ~/.azure` and retry after logging in again.

## Troubleshooting BKPR installation

### Object with the same value for property exists

__[Reported in issue #242](https://github.com/bitnami/kube-prod-runtime/issues/242)__

While installing BKPR on an AKS cluster, if you notice the following error message from `kubeprod install`, it indicates that another Azure service principal with the same value exists.

```
ERROR Error: graphrbac.ApplicationsClient#Create: Failure responding to request: StatusCode=400 -- Original Error: autorest/azure: Service returned an error. Status=400 Code="Unknown" Message="Unknown service error" Details=[{"odata.error":{"code":"Request_BadRequest","date":"2018-11-29T00:31:52","message":{"lang":"en","value":"Another object with the same value for property identifierUris already exists."},"requestId":"3c6f59e9-ad05-42fb-8ab2-3a9745eb9f68","values":[{"item":"PropertyName","value":"identifierUris"},{"item":"PropertyErrorCode","value":"ObjectConflict"}]}}]
```

__Troubleshooting__:

This is typically encountered when you attempt to install BKPR with a DNS zone (`--dns-zone`) that was used in an earlier installation on BKPR. Login to the [Azure Portal](https://portal.azure.com) and navigate to __Azure Active Directory > App registrations__ and filter the result with the keyword `kubeprod`. From the filtered results remove the entries that have the BKPR DNS zone in its name and retry the BKPR installation.

![Azure SP Conflict](images/azure-sp-conflict.png)

## Troubleshooting DNS

### Unable to resolve DNS addresses

You have installed BKPR to your Kubernetes cluster, but are unable to access any of the Ingress endpoints due to DNS resolution errors.

```bash
ping prometheus.my-domain.com
ping: prometheus.my-domain.com: Name or service not known
```

__Troubleshooting__:

DNS address resolution could be a result of configuration issues. For a working DNS setup, you need to ensure all of the following conditions are met.

- [ExternalDNS Pods are running](#externaldns-pods-are-not-starting)
- [ExternalDNS is updating DNS zone records](#externaldns-is-not-updating-dns-zone-records)
- [DNS glue records are configured](#dns-glue-records-are-not-configured)
- [DNS propagation has completed](#dns-propagation-has-not-completed)

### ExternalDNS Pods are not starting

Use the following command to check the status of the `external-dns` deployment:

```bash
kubectl -n kubeprod get deployments external-dns
NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
external-dns   1         1         1            0           5m
```

The `AVAILABLE` column indicates the number of Pods that have started successfully.

__Troubleshooting__:

A Pod goes through various [lifecycle phases](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) before it enters the `Running` phase. You can use the following command to watch the rollout status of the `external-dns` Deployment:

```bash
kubectl -n kubeprod rollout status deployments external-dns
Waiting for deployment "external-dns" rollout to finish: 0 of 1 updated replicas are available...
Waiting for deployment "external-dns" rollout to finish: 1 of 1 updated replicas are available...
```

The command will return with the message `deployment "external-dns" successfully rolled out` after all the Pods in the `external-dns` Deployment have started successfully. Please note it could take a few minutes for the `external-dns` Deployment to complete.

If it takes an abnormally long time (>5m) for the `external-dns` Pods to enter the `Running` phase, they may have encountered an error condition.

Check the status of the `external-dns` Pods with the command:

```bash
kubectl -n kubeprod get $(kubectl -n kubeprod get pods -l name=external-dns -o name)
NAME                            READY   STATUS              RESTARTS   AGE
external-dns-7bfbf596dd-55ngz   0/1     CrashLoopBackOff    3          10m
```

The `STATUS` column indicates the state the Pod is currently in and the `RESTARTS` column indicates the number of times the Pod has been restarted.

In the sample output you can see that the `external-dns` Pod is in the `CrashLoopBackOff` state and has been restarted very frequently indicating it has been encountering some error condition. In such situations you should inspect the details of the pod with the command:

```bash
kubectl -n kubeprod describe $(kubectl -n kubeprod get pods -l name=external-dns -o name)
```

Additionally, the container logs may contain useful information about the error condition. Inspect the container logs using the following command:

```bash
kubectl -n kubeprod logs $(kubectl -n kubeprod get pods -l name=external-dns -o name)
```

If you are unable to determine the cause of the error, [create a support request](https://github.com/bitnami/kube-prod-runtime/issues/new) describing your environment and remember to attach the output of the last two commands to the support request.

### ExternalDNS is not updating DNS zone records

The DNS host records (__A__) can be listed using the following command:

On Google Cloud Platform:

```bash
gcloud dns record-sets list --zone $(gcloud dns managed-zones list --filter dnsName:${BKPR_DNS_ZONE} --format='value(name)') --filter type=A
```

On Microsoft Azure:

```bash
az network dns record-set list --resource-group ${AZURE_RESOURCE_GROUP} --zone-name ${BKPR_DNS_ZONE} --query "[?arecords!=null]" --output table
```

BKPR, by default, creates host records for Prometheus, Grafana and Kibana dashboards. These records should be listed in the output of the above command.

__Troubleshooting__:

ExternalDNS automatically manages host records for Ingress resources in the cluster. When an Ingress resource is created, it could take a few minutes for it to be seen by ExternalDNS.

If the records are not updated a few minutes after the Ingress resource is created, use the following command to inspect the container logs of the `external-dns` Pod to discover any error conditions that may have been encountered.

```bash
kubectl -n kubeprod logs $(kubectl -n kubeprod get pods -l name=external-dns -o name)
```

### DNS glue records are not configured

The DNS glue record setup is the most basic requirement for the DNS address resolution to work correctly. The glue records are typically configured at the DNS domain registrar.

Use the following command to query the glue record configuration for your domain:

```bash
dig ${BKPR_DNS_ZONE} NS +noall +answer
```

The command should list one or more Nameserver (__NS__) records configured for your domain.

__Troubleshooting__:

If the above listed command does not return any __NS__ records, it indicates that the DNS glue records have not been configured at your domain registrar. At the same time, it is also possible the glue records are configured with wrong values.

First, use the following command to query the values of the NS records that should be set up as glue records.

On Google Cloud Platform:

```bash
gcloud dns managed-zones describe \
  $(gcloud dns managed-zones list --filter dnsName:${BKPR_DNS_ZONE} --format='value(name)')
```

On Microsoft Azure:

```bash
az network dns zone show \
  --name ${BKPR_DNS_ZONE} \
  --resource-group ${AZURE_RESOURCE_GROUP} \
  --query nameServers \
  --output table
```

Next, use your domain registrar's portal to add __NS__ records for your domain with the values displayed in the output of the previous command.

### DNS propagation has not completed

Nameserver changes typically take 0 to 24 hours to take effect, but they may also take as long as 48 hours.

__Troubleshooting__:

If [ExternalDNS is updating DNS zone records](#externaldns-is-not-updating-dns-zone-records) and the [DNS glue records are configured](#dns-glue-records-are-not-configured) correctly, you need to wait for the DNS propagation to complete.

[whatsmydns.net](https://www.whatsmydns.net) is a DNS propagation checker that can give you a rough idea of the DNS propagation status of your DNS records.

## Troubleshooting BKPR Ingress

### Let's Encrypt

The inability to access a Kubernetes Ingress resource over HTTP/S is likely caused by one of the following scenarios:

1. Ingress resource lacks the necessary annotations
1. Domain self-check fails
1. Let's Encrypt rate-limiting
1. Invalid email address (MX records for email domain did not exist)

In the next sections we will describe the troubleshooting steps required to identify the underlying problem and how to fix it.

__Accessing `cert-manager` logs__:

`cert-manager` logs can be retrieved directly from the pod.

The first step for troubleshooting self-signed certificates consists of checking the logs in `cert-manager`. `cert-manager` logs can be queried directly from Kibana. Or if you are unable to access Kibana, the most recent logs from `cert-manager` can be retrieved directly from the running pod by performing the following steps:

```
$ kubectl --namespace=kubeprod get pods --selector=name=cert-manager
NAME                            READY   STATUS    RESTARTS   AGE
cert-manager-75668b9d76-t5659   1/1     Running   0          10m
```

The following command retrieves the most recent set of logs from the `cert-manager` pod named as shown above:

```
$ kubectl --namespace=kubeprod logs cert-manager-75668b9d76-t5659
```

__Troubleshooting__:

#### Ingress resource lacks the necessary annotations

A Kubernetes Ingress resource is designated as TLS-terminated at the NGINX controller when the following annotations are present:

```
Annotations:
  kubernetes.io/ingress.class:                        nginx
  kubernetes.io/tls-acme:                             true
```

Make sure the Ingress resource you are trying to reach over HTTP/S has these annotations. For example:

```bash
$ kubectl --namespace=kubeprod describe ingress grafana
Name:             grafana
Namespace:        kubeprod
Address:          35.241.253.114
Default backend:  default-http-backend:80 (10.48.1.8:8080)
TLS:
  grafana-tls terminates grafana.example.com
Rules:
  Host                  Path      Backends
  ----                  ----      --------
  grafana.example.com
                        /oauth2   oauth2-proxy:4180 (<none>)
  grafana.example.com
                        /         grafana:3000 (<none>)
Annotations:
  kubecfg.ksonnet.io/garbage-collect-tag:             kube_prod_runtime
  kubernetes.io/ingress.class:                        nginx
  kubernetes.io/tls-acme:                             true
  nginx.ingress.kubernetes.io/auth-response-headers:  X-Auth-Request-User, X-Auth-Request-Email
  nginx.ingress.kubernetes.io/auth-signin:            https://grafana.example.com/oauth2/start
  nginx.ingress.kubernetes.io/auth-url:               https://grafana.example.com/oauth2/auth
```

If this is not the case, ensure that at least `"kubernetes.io/ingress.class": true` and `"kubernetes.io/tls-acme": true` are present.

### Domain self-check failure

This condition is usually signaled by `cert-manager` with log messages like the following:

```
E1217 16:12:27.728123       1 controller.go:180] certificates controller: Re-queuing item "kubeprod/grafana-tls" due to error processing: http-01 self-check failed for domain "grafana.example.com"
```

This usually means that the DNS domain name `grafana.example.com` does not resolve or the ACME protocol is not working as expected. Let's Encrypt is unable to probe that you (your Kubernetes cluster) is actually in control of the DNS domain name and refuses to issue a signed certificate.

To troubleshoot this issue, first determine the IPv4 address that `grafana` is using:

```
$ kubectl --namespace=kubeprod get ing
NAME                        HOSTS                                           ADDRESS          PORTS     AGE
cm-acme-http-solver-px56z   grafana.example.com                             35.241.253.114   80        1m
cm-acme-http-solver-rdxkg   kibana.example.com                              35.241.253.114   80        1m
cm-acme-http-solver-sdgdc   prometheus.example.com                          35.241.253.114   80        1m
grafana                     grafana.example.com,grafana.example.com         35.241.253.114   80, 443   1m
kibana-logging              kibana.example.com,kibana.example.com           35.241.253.114   80, 443   1m
prometheus                  prometheus.example.com,prometheus.example.com   35.241.253.114   80, 443   1m
```

In this example, `grafana.example.com` should resolve to `35.241.253.114`. In this example, this is not the case:

```
$ nslookup grafana.example.com 8.8.8.8
Server:         8.8.8.8
Address:        8.8.8.8#53

** server can't find grafana.example.com: NXDOMAIN
```

This typically means that DNS glue records for `example.com` are not properly configured. Please check the section named [Unable to resolve DNS addresses](#unable-to-resolve-dns-addresses) above.

If the DNS glue records are properly configured but still the DNS name for your Ingress resource does not resolve, it could mean that the NGINX Ingress controller is not getting an IPv4 address.

It could also mean that NGINX Ingress controller hasn't got a public IPv4 address:

```bash
$ kubectl --namespace=kubeprod get ing
NAME             HOSTS                                           ADDRESS   PORTS     AGE
grafana          grafana.example.com,grafana.example.com                   80, 443   49s
kibana-logging   kibana.example.com,kibana.example.com                     80, 443   47s
prometheus       prometheus.example.com,prometheus.example.com             80, 443   44s
```

Please wait a few minutes and check back again. If this is still the case, there must be some error condition that prevents tbe NGINX Ingress controller from getting a public IPv4 address. The conditions that can trigger this situation depend greatly on the underlying computing platform for Kubernetes. For example, Kubernetes on AKS or GKE depend on the public cloud infrastructure to provide a routable IPv4 address which is usually tied to some form of load-balancing resource.

However, if the NGINX Ingress controller is able to get a public IPv4 address, `grafana.example.com` must resolve to that same IPv4 address. For example:

```
$ kubectl --namespace=kubeprod get ing grafana
NAME      HOSTS                                     ADDRESS          PORTS     AGE
grafana   grafana.example.com,grafana.example.com   35.241.253.114   80, 443   6m
```

The `grafana.example.com` DNS name should resolve to `35.231.253.114`. However, in this example this is not the case as seen below:

```bash
$ nslookup grafana.example.com 8.8.8.8
Server:         8.8.8.8
Address:        8.8.8.8#53

Non-authoritative answer:
Name:   grafana.example.com
Address: 35.241.251.76
```

As the reader will notice in this example, `grafana.example.com` does not resolve to the IPv4 address stated in the corresponding Kubernetes Ingress resource. This could be caused by DNS caching and propagation issues (e.g. the TTL for the DNS record has not expired yet and Google DNS servers are not re-querying from the authoritative name server). Again, wait a few minutes and check back whether `grafana.example.com` resolves to the same the IPv4 address as seen in the Ingress resource (in this example, `35.241.253.114`).

As long as `grafana.example.com` does not resolve to the IPv4 address stated in the Ingress resource, Let's Encrypt will refuse to issue the certificate. Let's Encrypt uses the ACME HTTP-01 protocol and as long as the ACME protocol is running you will notice some transient Ingress resources named like `cm-acme-http-solver-*`:

```bash
$ kubectl --namespace=kubeprod get ing
NAME                        HOSTS                                           ADDRESS          PORTS     AGE
cm-acme-http-solver-px56z   grafana.example.com                             35.241.253.114   80        1m
cm-acme-http-solver-rdxkg   kibana.example.com                              35.241.253.114   80        1m
cm-acme-http-solver-sdgdc   prometheus.example.com                          35.241.253.114   80        1m
grafana                     grafana.exampl.ecom,grafana.example.com         35.241.253.114   80, 443   1m
kibana-logging              kibana.example.com,kibana.example.com           35.241.253.114   80, 443   1m
prometheus                  prometheus.example.com,prometheus.example.com   35.241.253.114   80, 443   1m
```

Once `grafana.example.com` resolves properly to the IPv4 address of the Ingress resource, the certificate will be eventually issued and installed:

```bash
$ kubectl --namespace=kubeprod describe cert grafana-tls
Name:         grafana-tls
Namespace:    kubeprod
...
Events:
  Type     Reason          Age                From          Message
  ----     ------          ----               ----          -------
  Warning  IssuerNotReady  32m                cert-manager  Issuer letsencrypt-prod not ready
  Normal   CreateOrder     30m (x2 over 32m)  cert-manager  Created new ACME order, attempting validation...
  Normal   DomainVerified  28m                cert-manager  Domain "grafana.example.com" verified with "http-01" validation
  Normal   IssueCert       28m                cert-manager  Issuing certificate...
  Normal   CertObtained    28m                cert-manager  Obtained certificate from ACME server
  Normal   CertIssued      28m                cert-manager  Certificate issued successfully
  ```

At this point check that you can access the Kubernetes Ingress resource correctly over HTTP/S.

### Rate-limit issues

This condition is usually signaled by `cert-manager` with log messages like the following:

```
E1217 22:24:31.237112       1 controller.go:180] certificates controller: Re-queuing item "kubeprod/grafana-tls" due to error processing: error getting certificate from acme server: acme: urn:ietf:params:acme:error:rateLimited: Error finalizing order :: too many certificates already issued for exact set of domains: grafana.example.com: see https://letsencrypt.org/docs/rate-limits/
```

This means that `cert-manager` has requested too many certificates and has exceeded the [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/). This situation can happen when you install and uninstall BKPR too many times or when a particular DNS domain is shared among several BKPR clusters.

BKPR defaults to the production environment offered by Let's Encrypt. However, for a non-production use of BKPR you can switch to using the staging environment that Let's Encrypt provides. You can find more information on how to switch to [using the staging environment](components.md#lets-encrypt-environments) in the BKPR documentation.

### Invalid email address (MX records for email domain did not exist)

This condition is usually signaled by `cert-manager` with log messages like the following:

```
I1218 17:06:03.204699       1 controller.go:171] certificates controller: syncing item 'kubeprod/prometheus-tls'
I1218 17:06:03.204812       1 sync.go:120] Issuer letsencrypt-prod not ready
E1218 17:06:03.204903       1 controller.go:180] certificates controller: Re-queuing item "kubeprod/prometheus-tls" due to error processing: Issuer letsencrypt-prod not ready
```

If the e-mail address used when installing BKPR uses an invalid domain or an e-mail domain that can't be resolved properly (missing MX DNS record), Let's Encrypt will refuse to accept requests from `cert-manager`. The actual error can be inspected by looking at the ClusterIssuer object in Kubernetes:

```bash
$ kubectl --namespace=kubeprod describe clusterissuer letsencrypt-prod
Name:         letsencrypt-prod
Namespace:
Labels:       kubecfg.ksonnet.io/garbage-collect-tag=kube_prod_runtime
              name=letsencrypt-prod
Annotations:  kubecfg.ksonnet.io/garbage-collect-tag: kube_prod_runtime
API Version:  certmanager.k8s.io/v1alpha1
Kind:         ClusterIssuer
...
Events:
  Type     Reason                Age   From          Message
  ----     ------                ----  ----          -------
  Warning  ErrVerifyACMEAccount  13m   cert-manager  Failed to verify ACME account: acme: urn:ietf:params:acme:error:invalidEmail: Error creating new account :: invalid contact domain. Contact emails @example.com are forbidden
```

To fix the issue make sure the domain part for the e-mail address used when installing BKPR has a corresponding MX DNS record. For example:

```bash
$ nslookup -tMX bitnami.com
*** Invalid option: tMX
Server:         192.168.0.1
Address:        192.168.0.1#53

Non-authoritative answer:
Name:   bitnami.com
Address: 50.17.235.25
```
