# FAQ

#### Q: What is BKPR?
A: The Bitnami Kubernetes Production Runtime ([BKPR](https://kubeprod.io)) is a collection of services that make it easy to run production workloads in Kubernetes. The services are ready-to-run, and pre-integrated with each other so they work out of the box. They are based on best-of-breed popular projects such as Prometheus and Kibana and cover logging, monitoring, DNS, certificate management and other common infrastructure needs.

#### Q: What Kubernetes platforms does BKPR support?
At the time of this writing, BKPR supports [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/) and [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) but in the future other Kubernetes platforms will be supported.

#### Q: What is the difference between BKPR and `kubeprod`?
A: BKPR consists of a collection of Kubernetes manifests written in *jsonnet* plus the accompanying `kubeprod` binary which deals with all the platform-specific details, evaluates the *jsonnet* manifests and executes them.

#### Q: Does BKPR support support Helm?
A: Yes, indeed. BKPR only adds functionality to an existing Kubernetes cluster while keeping compatibility with other frameworks like Helm.

#### Q: How does BKPR differ from me deploying the needed components via e.g. Helm, where I can choose which components and configs to use?
A: BKPR is an out-of-the-box, fully-tested, maintained, integrated framework from Bitnami. All components, and their configurations, have been tested exhaustively to work on several Kubernetes platforms, like Azure AKS, Google GKE, etc. Bitnami also follows these upstream components closely to deliver in-time security and bug fixes, freeing you from this burden.

#### Q: What is the community behind BKPR?
A: BKPR is an open-source project, which also means that all contributions are much welcome, either via code, documentation or by filing issues.

#### Q: What guarantees I’ll not become locked-in with Bitnami?
A: BKPR is an open-source project. Please read the [LICENSE](../LICENSE) for additional information.

#### Q: Why does BKPR use Bitnami-built Docker images instead of upstream ones from each project?
A: Bitnami-built Docker images follow upstream closely, with added continuous integration and testing, additional security best-practices (e.g. non-root containers), and a predictable release and support cycle.

#### Q: What will break if I uninstall BKPR?
A: It is advisable to be extremely cautious when uninstall BKPR, specially if there are any workloads that depend on features enabled by BKPR, like automatic DNS registration and TLS certificate generation for HTTP-based Kubernetes ingress resources.

Other features implemented by BKPR are not in the serving path, like Elasticsearch, Kibana or Prometheus. Uninstalling these will impact logging and monitoring provided by BKPR. The underlying data storage for these services uses [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes) and uninstalling BKPR will not destroy them (they are preserved). If later on you decide to re-install BKPR, the data will still be accessible.

#### Q: Is there locally-saved state used by the CLI?
A: Yes. `kubeprod` supports several Kubernetes platforms, like AKS and GKE. The first time `kubeprod` is run to install BKPR on any of these platforms, a JSON configuration file is generated which contains these platform-specific parameters, like the DNS domain/suffix used for automatic DNS management of ingress resources, identifiers and secrets. This JSON configurarion file is stored locally, in the current working directory as a filed named `kubeprod-autogen.json`, and is required by subsequent runs of `kubeprod`.

#### Q: How do I upgrade BKPR?
A: Please refer to the BKPR upgrades and support document.

#### Q: What is the expected SLA for critical updates, like security issues, etc.?
A: Please refer to the BKPR upgrades and support document.

#### Q: Where can I subscribe to an update feed, specially for security-updates?
A: BKPR is released by the releases section in the GitHub project. The *changelog* for every release describes the bug fixes, security updates and new features. 

#### Q: I found a bug /  I want XYZ component to be added, etc.
A: When there are any issues or comments you want to report, please do report them by creating an issue in GitHub.