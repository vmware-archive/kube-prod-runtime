# Troubleshooting Guide

## Index

- [Troubleshooting AKS cluster creation](#troubleshooting-aks-cluster-creation)
    + [Service principal clientID not found](#service-principal-clientid-not-found)
- [Troubleshooting BKPR installation](#troubleshooting-bkpr-installation)
    + [Object with the same value for property exists](#object-with-the-same-value-for-property-exists)
- [Troublehooting DNS](#troubleshooting-dns)
    + [ExternalDNS pods are not starting](#externaldns-pods-are-not-starting)

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

While installing BKPR on a AKS cluster, if you notice the following error message from `kubeprod install`, it indicates that another Azure service principal with the same value exists.

```
ERROR Error: graphrbac.ApplicationsClient#Create: Failure responding to request: StatusCode=400 -- Original Error: autorest/azure: Service returned an error. Status=400 Code="Unknown" Message="Unknown service error" Details=[{"odata.error":{"code":"Request_BadRequest","date":"2018-11-29T00:31:52","message":{"lang":"en","value":"Another object with the same value for property identifierUris already exists."},"requestId":"3c6f59e9-ad05-42fb-8ab2-3a9745eb9f68","values":[{"item":"PropertyName","value":"identifierUris"},{"item":"PropertyErrorCode","value":"ObjectConflict"}]}}]
```

__Troubleshooting__:

This is typically encountered when you attempt to install BKPR with a DNS zone (`--dns-zone`) that was used in a earlier installation on BKPR. Login to the [Azure Portal](https://portal.azure.com) and navigate to __Azure Active Directory > App registrations__ and filter the result with the keyword `kubeprod`. From the filtered results remove the entries that have the BKPR DNS zone in its name and retry the BKPR installation.

![Azure SP Conflict](images/azure-sp-conflict.png)

## Troublehooting DNS

### ExternalDNS Pods are not starting

Use the following command to check the status of the `external-dns` deployment:

```bash
kubectl -n kubeprod get deployments external-dns
NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
external-dns   1         1         1            0           5m
```

The `AVAILABLE` column indicates the number of Pods that have started successfully.

__Troubleshooting__:

A Pod goes through various [lifecyle phases](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) before it enters the `Running` phase. You can use the following command to watch the rollout status of the `external-dns` Deployment:

```bash
kubectl -n kubeprod rollout status deployments external-dns
Waiting for deployment "external-dns" rollout to finish: 0 of 1 updated replicas are available...
Waiting for deployment "external-dns" rollout to finish: 1 of 1 updated replicas are available...
```

The command will return with the message `deployment "external-dns" successfully rolled out` after all the Pods in the `external-dns` Deployment have started successfully. Please note it could take a few minutes for the `external-dns` Deployment to complete.

If it takes an abnormally long time (>5m) for the `external-dns` Pods to enter the `Running` phase, it indicates that it may have encountered an error condition.

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

If you are unable to determine the cause of the error, create a support request describing your environment and remember to attach the output of the last two commands to the support request.
