# Getting Started

The Bitnami Production Runtime for Kubernetes builds on a default
"empty" kubernetes cluster.

1. First, download the `installer` tool and place it somewhere in `$PATH`

   ```sh
   wget -O installer https://github.com/kube-prod-runtime/releases/download/v0.0.1/installer-linux-amd64
   chmod +x installer
   ```

1. Find the prod-runtime "platform" that corresponds to your target
   environment.  See `installer list-platforms` for supported
   targets.

   If your environment is not in this list, you can try a similar but
   not identical platform.  It might work, but this combination has
   not been tested and is not supported by Bitnami.  Please file
   requests using github issues if you have other platforms you would
   like to see supported in the future.

1. Run `installer`, with the target platform, and with the default
   `kubectl` context configured with an admin account for your
   cluster.

   For example, to install onto GKE-1.9.x, use:
   ```sh
   installer install --platform gke-1.9
   ```

   The installer may require some additional platform-specific
   information or credentials.

1. It can take a few minutes for the new containers to download and
   start.  After this, you should have a functional Production Runtime
   environment!

## Hello world

*[TODO]*

After install, you should have a number of additional pieces of
infrastructure available in your cluster.  To demonstrate them, we'll
install a simple example application.

```
kubecfg update \
  --namespace=default \
  --gc-tag=prod-runtime-example \
  https://github.com/bitnami/kube-prod-runtime/releases/v1.0.0/example.jsonnet
```

Note that this application has been able to take advantage of Ingress,
TLS, managed-database, logging, monitoring.

[FIXME: walk through getting to each of those dashboards, and poking
at the HTTPS endpoint of the app]
