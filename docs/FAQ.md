# FAQ

#### Q: What is BKPR?
A: The Bitnami Kubernetes Production Runtime ([BKPR](https://kubeprod.io)) is a collection of services that make it easy to run production workloads in Kubernetes. The services are ready-to-run, and pre-integrated with each other so they work out of the box. They are based on best-of-breed popular projects such as Prometheus and Kibana, and cover logging, monitoring, DNS, certificate management and other common infrastructure needs.

#### Q: What Kubernetes platforms does BKPR support?
At the time of writing, BKPR supports [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-us/services/kubernetes-service/) and [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/). Other Kubernetes platforms will be supported in future.

#### Q: What is the difference between BKPR and `kubeprod`?
A: BKPR consists of a collection of Kubernetes manifests written in *jsonnet* plus the accompanying `kubeprod` binary which deals with all the platform-specific details, evaluates the *jsonnet* manifests, and applies them to the existing Kubernetes cluster.

#### Q: Does BKPR support support Helm?
A: Yes. BKPR only adds functionality to an existing Kubernetes cluster while keeping compatibility with other frameworks like Helm.

#### Q: How does BKPR differ from me deploying the needed components via e.g. Helm, where I can choose which components and configurations to use?
A: BKPR is an out-of-the-box, fully-tested, maintained, and integrated framework from Bitnami. All components, and their configurations, have been tested exhaustively to work on several Kubernetes platforms, such as Azure Kubernetes Service and Google Kubernetes Engine. Bitnami also follows these upstream components closely to deliver in-time security and bug fixes, freeing you from this burden.

#### Q: What is the community behind BKPR?
A: BKPR is an open-source project, which also means that all contributions are welcome, either via code, documentation or by filing issues.

#### Q: What guarantees I’ll not become locked-in with Bitnami?
A: BKPR is an open-source project. Please read the [LICENSE](../LICENSE) for additional information.

#### Q: Why does BKPR use Bitnami-built Docker images instead of upstream ones from each project?
A: Bitnami-built Docker images follow upstream closely, with added continuous integration and testing, additional security best-practices (e.g. non-root containers), and a predictable release and support cycle.

#### Q: What will break if I uninstall BKPR?
A: It is advisable to be extremely cautious when uninstalling BKPR, especially if there are any workloads that depend on features enabled by BKPR. Examples of such services are automatic DNS registration and TLS certificate generation for HTTP-based Kubernetes Ingress resources.

Other features implemented by BKPR are not in the service path, like Elasticsearch, Kibana or Prometheus. Uninstalling these will impact the logging and monitoring services provided by BKPR. The underlying data storage for these services uses [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes) and uninstalling BKPR will not destroy them (they are preserved). If you later decide to re-install BKPR, the data will still be accessible.

#### Q: Is there locally-saved state used by the CLI?
A: Yes. `kubeprod` supports several Kubernetes platforms, like AKS and GKE. The first time `kubeprod` is run to install BKPR on any of these platforms, a JSON configuration file is generated which contains these platform-specific parameters, like the DNS domain/suffix used for automatic DNS management of Ingress resources, identifiers and secrets. This JSON configuration file is stored locally, in the current working directory as a file named `kubeprod-autogen.json`, and is required for subsequent runs of `kubeprod`.

#### Q: How do I upgrade BKPR?
A: Please refer to the BKPR upgrades and support document.

#### Q: What is the expected SLA for critical updates, like security issues, etc.?
A: Please refer to the BKPR upgrades and support document.

#### Q: Where can I subscribe to an update feed, specially for security-updates?
A: Follow the [releases section in the GitHub project](https://github.com/bitnami/kube-prod-runtime/releases). The *changelog* for every release describes the bug fixes, security updates and new features. 

#### Q: I found a bug /  I want XYZ component to be added, etc.
A: When there are any issues or comments you want to report, please do report them by [creating an issue in GitHub](https://github.com/bitnami/kube-prod-runtime/issues).
