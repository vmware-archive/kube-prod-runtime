local etcd = import "../components/etcd.jsonnet";
local svc_cat = import "../components/svc-cat.jsonnet";
local cert_manager = import "../components/cert-manager.jsonnet";

{
  /*
  etcd: etcd {
    p: "svc-cat-",
    etcd+: {
      spec+: {
        replicas: 1,
      },
    },
  },
*/
  //svc_cat: svc_cat {
  //  etcd+: {
  //    svc:: $.etcd.svc,
  //  },
  //},

  cert_manager: cert_manager {
    letsencrypt_contact_email:: $.letsencrypt_contact_email,
  },


  // prometheus
  // pagekite-ingress
}
