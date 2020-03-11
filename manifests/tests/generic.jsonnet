/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2020 Bitnami
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

(import "../platforms/generic.jsonnet") {
  letsencrypt_contact_email: "noone@nowhere.com",
  config: {
    dnsZone: "test.example.com",
    powerDns: {
      api_key: "powerdns_api_key",
      db_password: "mydbpassword",
    },
    keycloak: {
      db_password: "mydbpassword",
      admin_password: "myadminpassword",
      client_id: "myclientid",
      client_secret: "mysecret",
      group: "",
    },
    oauthProxy: {
      cookie_secret: "cookiesecret",
      authz_domain: "test.invalid",
    },
    mariadbGalera: {
      root_password: "myrootpassword",
      mariabackup_password: "mymariabackuppassword",
    },
  },
}
