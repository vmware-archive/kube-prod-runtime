# Troubleshooting Guide

## Index

- [Troubleshooting AKS cluster creation](#troubleshooting-aks-cluster-creation)
    + [Service principal clientID not found](#service-principal-clientid-not-found)
- [Troubleshooting BKPR installation](#troubleshooting-bkpr-installation)
    + [Object with the same value for property exists](#object-with-the-same-value-for-property-exists)
- [Troubleshooting BKPR ingress](#troubleshooting-bkpr-ingress)
    + [Let's Encrypt](#lets-encrypt)

## Troubleshooting AKS cluster creation

### Service principal clientID not found

If you notice the following error message from `az aks create`, it could indicate the Azure authentication token has expired.

```
Operation failed with status: 'Bad Request'. Details: Service principal clientID: <REDACTED>
not found in Active Directory tenant <REDACTED>, Please see https://aka.ms/acs-sp-help for more details.
```

__Resolution__:

Please clear your Azure profile directory with `rm -rf ~/.azure` and retry after logging in again.

## Troubleshooting BKPR installation

### Object with the same value for property exists

__[Reported in issue #242](https://github.com/bitnami/kube-prod-runtime/issues/242)__

If you notice the following error message from `kubeprod install`, it indicates that another Azure service principal with the same value exists.

```
ERROR Error: graphrbac.ApplicationsClient#Create: Failure responding to request: StatusCode=400 -- Original Error: autorest/azure: Service returned an error. Status=400 Code="Unknown" Message="Unknown service error" Details=[{"odata.error":{"code":"Request_BadRequest","date":"2018-11-29T00:31:52","message":{"lang":"en","value":"Another object with the same value for property identifierUris already exists."},"requestId":"3c6f59e9-ad05-42fb-8ab2-3a9745eb9f68","values":[{"item":"PropertyName","value":"identifierUris"},{"item":"PropertyErrorCode","value":"ObjectConflict"}]}}]
```

__Resolution__:

This is typically encountered when you attempt to install BKPR with a DNS zone (`--dns-zone`) that was used in a earlier installation on BKPR. Login to the [Azure Portal](https://portal.azure.com) and navigate to __Azure Active Directory > App registrations__ and filter the result with the keyword `kubeprod`. From the filtered results remove the entries that have the BKPR DNS zone in its name and retry the BKPR installation.

![Azure SP Conflict](images/azure-sp-conflict.png)

## Troubleshooting BKPR ingress

### Let's Encrypt

BKPR deploys [`cert-manager`](#components.md/cert-manager) Kubernetes add-on to automate the management and issuance of TLS certificates. `cert-manager` delegates on Let's Encrypt to retrieve valid X.509 certificates used to protect designated Kubernetes ingress resources with TLS encryption for HTTP traffic.

A Kubernetes ingress resource is designated to be TLS-terminated at the NGINX controller when the following annotations are present:

```
Annotations:
  kubernetes.io/ingress.class:                        nginx
  kubernetes.io/tls-acme:                             true
```

`cert-manager` watches for Kubernetes ingress resources. When an ingress resource with the `"kubernetes.io/tls-acme": true` annotation is seen for the first time, `cert-manager` tries to issue an [ACME certificate using HTTP-01 challenge](http://docs.cert-manager.io/en/latest/tutorials/acme/http-validation.html). This works by creating a temporary ingress resource name like `cm-acme-http-solver-${pod_id}` and then triggering the HTTP-01 challenge protocol. This requires that Let's Encrypt is able to resolve the DNS name associated with the Kubernetes ingress resource. On a Kubernetes cluster where BKPR is deployed, this requires that External DNS is functioning properly.

During the time while `cert-manager` negotiates the certificate issue with Let's Encrypt, NGNIX controller temporatily uses a self-signed certificate. This situation should be transient and when it lasts for more than a couple of minutes there is a problem that prevents the certificate from being issued. Please note that when using the staging environment for Let's Encrypt the certificates issued by it not be recognized as valid (the signing CA is not a recognized one). 

When everything works as expected, `cert-manager` will eventually install the certificate as seen next (example):

```
$ kubectl describe certificate example-com
Events:
  Type    Reason          Age      From          Message
  ----    ------          ----     ----          -------
  Normal  CreateOrder     57m      cert-manager  Created new ACME order, attempting validation...
  Normal  DomainVerified  55m      cert-manager  Domain "example.com" verified with "http-01" validation
  Normal  DomainVerified  55m      cert-manager  Domain "www.example.com" verified with "http-01" validation
  Normal  IssueCert       55m      cert-manager  Issuing certificate...
  Normal  CertObtained    55m      cert-manager  Obtained certificate from ACME server
  Normal  CertIssued      55m      cert-manager  Certificate issued successfully
```

If this is not the case, Let's Encrypt will refuse to issue the certificate. Besides having NGINX serve a self-signed certificate, this is typically signalled because there are temporary Kubernetes ingress resources named like `cm-acme-http-solver-${pod_id}` lingering around for a while. At some point, certificate generation will time-out, these temporary ingress resources will be destroyed and the Kubernetes certificate will be marked accordingly in its events section. Make sure that External DNS is working properly. Let's Encrypt requires that the DNS name (subject) of the X.509 certificate can resolve properly. Please read the section about troubleshooting DNS and External DNS in this document.