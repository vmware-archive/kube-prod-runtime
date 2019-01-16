/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2019 Bitnami
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

// Test EKS

(import "../platforms/eks.jsonnet") {
  "letsencrypt_contact_email": "noone@nowhere.com",
  config: {
    dnsZone: "test.example.com",
    externalDns: {
      aws_access_key_id: "sekret_key_id",
      aws_secret_access_key: "sekret_access_key",
    },
    oauthProxy: {
      client_id: "myclientid",
      client_secret: "mysecret",
      cookie_secret: "cookiesecret",
      aws_region: "us-east-1",
      aws_user_pool_id: "us-east-1_userpool",
    },
  },
}
