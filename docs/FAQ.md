# Bitnami Production Runtime for Kubernetes FAQ

## Frequently Asked Questions

#### Q: Does BKPR support support Helm?
A: Yes, indeed. BKPR only adds functionality to an existing Kubernetes cluster while keeping compatibility with other frameworks like Helm.

#### Q: How does Kubeprod differ from me deploying the needed components via e.g. Helm, where I can choose which components and configs to use ?
A: BKPR is an out-of-the-box, fully-tested, maintained, integrated framework from Bitnami. All components, and their configurations, have been tested exhaustively to work on several Kubernetes platforms, like Azure AKS, Google GKE, etc. Bitnami also follows these upstream components closely to delive in-time security and bug fixes, freeing you from this burden.

#### Q: What’s the community behind BKPR?
A: BKPR is an open-source project which means that not only Bitnami, but anyone can contribute.

#### Q: What guarantees I’ll not become locked-in with Bitnami? [ LICENSE, F/OSS, etc ]
A: BKPR is an open-source project. Please read the LICENSE.md to fully understand how neither Bitnami nor any other entity can get you locked-in.

#### Q: Why does BKPR use Bitnami-built Docker images instead of upstream ones from each project?
A: Bitnami-built Docker images follow upstream closely, but they add an additional effort on integration and testing, additional security best-practices (e.g. non-root containers), and a predictable release and support cycle.

#### Q: What will break if I uninstall BKPR?
A: It is advisable to be extremely cautios when uninstall BKPR, specially if there are any workloads that depend on features enabled by BKPR, like automatic DNS registration and TLS certificate generation for HTTP-based Kubernetes ingress. Other features implemented by BKPR are not in the serving path, like Elasticsearch, Kibana or Prometheus.

#### Q: Is there locally-saved state used by the CLI?
A: Yes. `kubeprod` supports several Kubernetes platforms, like AKS and GKE. The first time `kubeprod` is ran to install BKPR on any of these platforms, a JSON configuration file is generated which contains these platform-specific parameters, like the DNS domain/suffix used for automatic DNS management of ingress, identifiers and secrets. Where this JSON configuration file is stored, and whether it is shared or not, lies outside the scope of BKPR at the moment. This JSON file is auto-generated the first time `kubeprod` is ran and never changed, which eases the process of sharing or distributing it.

#### Q: How do I upgrade BKPR?
A: Please refer to the BKPR upgrades and support document.

#### Q: Does BKPR have an LTS model?
A: Please refer to the BKPR upgrades and support document.

#### Q: What is the expected SLA for critical updates, like security issues, etc.?
A: Please refer to the BKPR upgrades and support document.

#### Q: Where can I subscribe to an update feed, specially for security-updates?
A: Subscribe to the GitHub repository.

#### Q: I found a bug /  I want XYZ component to be added,
A: When there are any issues or comments you want to report, please do report them by creating an issue in GitHub.