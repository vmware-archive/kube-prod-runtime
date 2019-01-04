/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2019 Bitnami
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Test GKE

(import "../platforms/gke.jsonnet") {
  "letsencrypt_contact_email": "noone@nowhere.com",
  config: {
    dnsZone: "test.example.com",
    externalDns: {
      credentials: "google credentials json contents",
      project: "dns_gcp_project",
    },
    oauthProxy: {
      client_id: "myclientid",
      client_secret: "mysecret",
      cookie_secret: "cookiesecret",
      authz_domain: "test.invalid",
      google_groups: [],
      google_admin_email: "admin@example.com",
      google_service_account_json: "<fake google credentials json contents>",
    },
  },
}
