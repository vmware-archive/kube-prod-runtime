# Troubleshooting Guide

## Index

- [Troubleshooting AKS cluster creation](#troubleshooting-aks-cluster-creation)
    + [Service principal clientID not found](#service-principal-clientid-not-found)

## Troubleshooting AKS cluster creation

### Service principal clientID not found

If you notice the following error message from `az aks create`, it could indicate the Azure authentication token has expired.

    ```
    Operation failed with status: 'Bad Request'. Details: Service principal clientID: <REDACTED>
    not found in Active Directory tenant <REDACTED>, Please see https://aka.ms/acs-sp-help for more details.
    ```

Please clear your Azure profile directory with `rm -rf ~/.azure` and retry after logging in again.
