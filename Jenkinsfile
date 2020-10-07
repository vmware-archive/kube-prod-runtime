#!groovy

// Assumed jenkins plugins:
// - custom-tools-plugin
// - pipeline-utility-steps (readJSON)
// - kubernetes
// - azure-credentials
// - aws-credentials

import groovy.json.JsonOutput
import org.jenkinsci.plugins.pipeline.modeldefinition.Utils

// Workaround https://issues.jenkins-ci.org/browse/JENKINS-41929 (which forces
// a 2nd job run to get them loaded[1], this 2nd run can be triggered by
// adding a PR comment with a `bors try` line): override buildRelDefaults if
// corresponding parameter is set.
// [1] see: https://issues.jenkins-ci.org/browse/JENKINS-41929

// NOTE: need update below map at jenkins/cloud-custodian/Jenkinsfile
// (until we create a common file for shared Jenkins code/data)
def buildRelDefaults = [
  'AKS_REL': '1.16,1.17',
  'EKS_REL': '1.16,1.17',
  'GKE_REL': '1.16,1.17',
  'GEN_REL': '1.17', // generic is tested on GKE, wait for 1.17 on the stable channel to change it
]

properties([
  // See releasesFromStr() function below on how we parse the _REL string
  parameters([
    stringParam(name: 'AKS_REL', defaultValue: '', description: "Override AKS releases to test"),
    stringParam(name: 'EKS_REL', defaultValue: '', description: "Override EKS releases to test"),
    stringParam(name: 'GKE_REL', defaultValue: '', description: "Override GKE releases to test"),
    stringParam(name: 'GEN_REL', defaultValue: '', description: "Override Generic-cloud releases to test"),
  ])
])

// Final map with releases to build, merging `buildRelDefaults` map with `params` (if not ''):
def buildRel = buildRelDefaults.collectEntries {
    key, value -> [(key): (params[key] != ""? params[key] : value)]
}

def parentZone = 'tests.bkpr.run'
def parentZoneResourceGroup = 'jenkins-bkpr-rg'

// Force using our pod
def label = env.BUILD_TAG.replaceAll(/[^a-zA-Z0-9-]/, '-').toLowerCase()

// Get array of releases (\d.\d+) from comma separated string in the form of e.g.
// - "1.15,1.16"     -> [[rel: "1.15", pre: false], [rel: "1.16", pre: false]
// - "1.15,1.16-pre" -> [[rel: "1.15", pre: false], [rel: "1.16", pre: true]
// Using `collect` to transform them thru regex, `findAll` to filter-in non-nulls
@NonCPS
def releasesFromStr(strRel) {
  strRel.split(",").collect{ def m = (it =~ /(\d\.\d+)(-pre)?/); if (m) [rel: m[0][1], pre: m[0][2] != null] }.findAll{ it }
}

def scmCheckout() {
    // PR builds are handled using the github-integration plugin to
    // control builds from github comments and labels
    if(env.GITHUB_PR_HEAD_SHA) {
        def repo_url = env.GITHUB_REPO_GIT_URL
        def sha = env.GITHUB_PR_HEAD_SHA
        sh """
        git init --quiet
        git remote add origin ${repo_url}
        git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
        git fetch origin --quiet
        git checkout ${sha} --quiet
        """
    } else {
        checkout scm
    }
    sh 'git submodule update --init'
}

def scmPostCommitStatus(String state) {
    // PR builds are handled using the github-integration plugin to
    // control builds from github comments and labels
    if(env.GITHUB_PR_HEAD_SHA) {
        def target_url = env.BUILD_URL + 'display/redirect'
        def sha = env.GITHUB_PR_HEAD_SHA
        def context = 'continuous-integration/jenkins/pr-merge'
        def params = (env.GITHUB_PR_URL).replaceAll('https://github.com/', '').split('/')
        def repo = params[0] + '/' + params[1]
        def desc = ''

        switch(state) {
            case 'success':
                desc = 'This commit looks good'
                break
            case 'error':
            case 'failure':
                desc = 'This commit cannot be built'
                break
            case 'pending':
                desc = 'Waiting for status to be reported'
                break
            default:
                return
        }

        withCredentials([usernamePassword(credentialsId: 'github-bitnami-bot', passwordVariable: 'GITHUB_TOKEN', usernameVariable: '')]) {
            sh """
            curl -sSf \"https://api.github.com/repos/${repo}/statuses/${sha}\" \
                -H \"Authorization: token ${GITHUB_TOKEN}\" \
                -H \"Content-Type: application/json\" \
                -X POST -o /dev/null \
                -d \"{\\\"state\\\": \\\"${state}\\\",\\\"context\\\": \\\"${context}\\\", \\\"description\\\": \\\"${desc}\\\", \\\"target_url\\\": \\\"${target_url}\\\"}\"
            """
        }
    }
}

def withGo(Closure body) {
    container('go') {
        withEnv([
            "GOPATH+WS=${env.WORKSPACE}",
            "PATH+GOBIN=${env.WORKSPACE}/bin",
            "HOME=${env.WORKSPACE}",
        ]) {
            body()
        }
    }
}

def waitForRollout(String namespace, int rolloutTimeout, int postRollOutSleep) {
    timeout(time: rolloutTimeout, unit: 'SECONDS') {
        container('kubectl') {
            try {
                sh """
                set +x
                for deploy in \$(kubectl --namespace ${namespace} get deploy,sts --output name)
                do
                  echo -n "\nWaiting for rollout of '\${deploy}' in '${namespace}' namespace"
                  while ! \$(kubectl --namespace ${namespace} rollout status \${deploy} --watch=false | grep -q -E 'successfully rolled out|rollout status is only available for|rolling update complete|partitioned roll out complete')
                  do
                    echo -n "."
                    sleep 3
                  done
                done
                """
            } catch (error) {
                sh "kubectl --namespace ${namespace} get po,deploy,svc,ing"
                sh """
                  echo -n "\nFurther debugging info for Pods not-Running in '${namespace}' namespace:"
                  kubectl --namespace ${namespace} get pod --no-headers | grep -v Running | awk '{ print \$1 }' | xargs -tI@ sh -xc 'kubectl --namespace ${namespace} describe pod @ | tail -10; kubectl --namespace ${namespace} logs @'
                """
                throw error
            }
        }
    }
    if (postRollOutSleep) {
        sleep postRollOutSleep
    }
}

def insertGlueRecords(String name, java.util.List nameServers, String ttl, String zone, String resourceGroup) {
    container('az') {
        for (ns in nameServers) {
            sh "az network dns record-set ns add-record --resource-group ${resourceGroup} --zone-name ${zone} --record-set-name ${name} --nsdname ${ns}"
        }
        sh "az network dns record-set ns update --resource-group ${resourceGroup} --zone-name ${zone} --name ${name} --set ttl=${ttl}"
    }
}

def deleteGlueRecords(String name, String zone, String resourceGroup) {
    container('az') {
        sh "az network dns record-set ns delete --yes --resource-group ${resourceGroup} --zone-name ${zone} --name ${name} || true"
    }
}

// Clean a string, suitable for use in a GCP "label".
// "It must only contain lowercase letters ([a-z]), numeric characters ([0-9]), underscores (_) and dashes (-). International characters are allowed."
// .. and "must be less than 63 bytes"
@NonCPS
String gcpLabel(String s) {
    s.replaceAll(/[^a-zA-Z0-9_-]+/, '-').toLowerCase().take(62)
}

def runIntegrationTest(String description, String kubeprodArgs, String ginkgoArgs, boolean pauseForDebugging, Closure clusterSetup, Closure clusterDestroy, Closure dnsSetup, Closure dnsDestroy) {
    // Regex of tests that are temporarily skipped.  Empty-string
    // to run everything.  Include pointers to tracking issues.
    def skip = ''

    try {
        clusterSetup()

        // HACK: We have been experiencing the following error while executing "kubeprod install"
        //       "Error: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1: the server is currently unable to handle the request"
        //       To workaround this issue a 60 sec sleep is added to allow the api server to become READY before performing the installation.
        waitForRollout("kube-system", 1800, 60)

        container('kubectl') {
            sh "kubectl version --short"
            sh "kubectl cluster-info"
        }

        try {
            sh "kubeprod install ${kubeprodArgs} --manifests=${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests"
            try {
                // DNS set up must run after `kubeprod` install because `kubeprod`
                // creates the DNS hosted zone in the underlying cloud platform
                dnsSetup()

                waitForRollout("kubeprod", 1800, 120)

                withGo() {
                    dir("${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/tests") {
                        // NOTE: ginkgo version pinned to the one used in tests/
                        sh 'env GO111MODULE=on go get github.com/onsi/ginkgo/ginkgo@v1.12.0'
                        try {
                            sh """
                            ginkgo -v \
                                --tags integration -r       \
                                --randomizeAllSpecs         \
                                --randomizeSuites           \
                                --failOnPending             \
                                --trace                     \
                                --progress                  \
                                --slowSpecThreshold=300     \
                                --compilers=2               \
                                --nodes=8                   \
                                --skip '${skip}'            \
                                -- --junit junit --description '${description}' --kubeconfig ${KUBECONFIG} ${ginkgoArgs}
                            rc=\${?}
                            [ \${rc} -eq 0 ] && RESULT=PASS || RESULT=FAIL
                            echo "INTEGRATION TEST for platform='${description}' RESULT=\${RESULT}"
                            exit \${rc}
                            """
                        } catch (error) {
                            if(pauseForDebugging) {
                                timeout(time: 15, unit: 'MINUTES') {
                                    input 'Paused for manual debugging'
                                }
                            }
                            throw error
                        } finally {
                            if(pauseForDebugging) {
                                junit 'junit/*.xml'
                            }
                        }
                    }
                }
            } finally {
                dnsDestroy()
            }
        } finally {
            container('kubectl') {
                sh "kubectl get po,deploy,svc,ing --all-namespaces || true"
            }
            // Below cert-manager cleanup is needed if certs issuing has failed
            container('kubectl') {
                sh """
                  timeout 60 kubectl get -n kubeprod challenges.acme.cert-manager.io -oname | \
                    timeout 60 xargs -rtI{} kubectl patch -n kubeprod {} \
                      --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' || true
                """
            }
            withEnv(["PATH+KUBECFG=${tool 'kubecfg'}"]) {
                sh "kubecfg delete kubeprod-manifest.jsonnet || true"
            }
            container('kubectl') {
                sh "kubectl wait --for=delete ns/kubeprod --timeout=300s || true"
            }
        }
    } finally {
        clusterDestroy()
    }
}

podTemplate(cloud: 'kubernetes-cluster', label: label, yaml: """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: 'go'
    image: 'golang:1.14.2-stretch'
    tty: true
    command:
    - 'cat'
    resources:
      limits:
        cpu: '2000m'
        memory: '2Gi'
      requests:
        cpu: '10m'
        memory: '1Gi'
    volumeMounts:
    - name: workspace-volume
      mountPath: '/home/jenkins'
  - name: 'gcloud'
    image: 'google/cloud-sdk:289.0.0'
    tty: true
    command:
    - 'cat'
    env:
    - name: 'CLOUDSDK_CORE_DISABLE_PROMPTS'
      value: '1'
    volumeMounts:
    - name: workspace-volume
      mountPath: '/home/jenkins'
  - name: 'az'
    image: 'mcr.microsoft.com/azure-cli:2.0.79'
    tty: true
    command:
    - 'cat'
    volumeMounts:
    - name: workspace-volume
      mountPath: '/home/jenkins'
  - name: 'aws'
    image: 'mesosphere/aws-cli:1.14.5'
    tty: true
    command:
    - 'cat'
    volumeMounts:
    - name: workspace-volume
      mountPath: '/home/jenkins'
  - name: 'kubectl'
    image: 'lachlanevenson/k8s-kubectl:v1.16.4'
    tty: true
    command:
    - 'cat'
    securityContext:
      runAsUser: 0
      fsGroup: 0
    volumeMounts:
    - name: workspace-volume
      mountPath: '/home/jenkins'
  - name: 'kaniko'
    image: 'gcr.io/kaniko-project/executor:debug-v0.9.0'
    tty: true
    env:
    - name: 'DOCKER_CONFIG'
      value: '/root/.docker'
    command:
    - '/busybox/cat'
    volumeMounts:
    - name: docker-config
      mountPath: /root
    - name: workspace-volume
      mountPath: '/home/jenkins'
    securityContext:
      runAsUser: 0
      fsGroup: 0
  securityContext:
    runAsUser: 1000
    fsGroup: 1000
  volumes:
  - name: docker-config
    projected:
      sources:
      - secret:
          name: dockerhub-bitnamibot
          items:
            - key: text
              path: .docker/config.json
"""
) {
    env.http_proxy = 'http://proxy.webcache:80/'  // Note curl/libcurl needs explicit :80 !
    env.PATH = "/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    env.GOPATH = "/go"

    node(label) {
        timeout(time: 150, unit: 'MINUTES') {
            withEnv([
                "HOME=${env.WORKSPACE}",
                "PATH+KUBEPROD=${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/kubeprod/bin",
            ]) {
                try {
                    scmPostCommitStatus("pending")

                    stage('Checkout') {
                        dir("${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime") {
                            scmCheckout()
                        }
                    }

                    stage('Bootstrap') {
                        withCredentials([file(credentialsId: 'gke-kubeprod-jenkins', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                            container('gcloud') {
                                sh "gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}"
                            }
                        }

                        withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
                            container('az') {
                                sh "az login --service-principal -u \$AZURE_CLIENT_ID -p \$AZURE_CLIENT_SECRET -t \$AZURE_TENANT_ID"
                                sh "az account set -s \$AZURE_SUBSCRIPTION_ID"
                            }
                        }
                    }

                    parallel(
                        installer: {
                            stage('Build') {
                                withGo() {
                                    dir("${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/kubeprod") {
                                        sh 'go version'
                                        sh "make all"
                                        sh "make test"
                                        sh "make vet"

                                        sh "kubeprod --help"
                                    }
                                }
                            }
                        },
                        manifests: {
                            stage('Manifests') {
                                withGo() {
                                    dir("${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests") {
                                        withEnv([
                                            "PATH+KUBECFG=${tool 'kubecfg'}",
                                            "PATH+JSONNET=${tool 'jsonnet'}",
                                        ]) {
                                            sh 'make fmttest validate KUBECFG="kubecfg -v"'
                                        }
                                    }
                                }
                            }
                        }, failFast: true
                    )

                    def maxRetries = 2
                    def platforms = [:]

                    // See:
                    //  gcloud container get-server-config
                    def gkeKversions = releasesFromStr(buildRel.GKE_REL)
                    for (x in gkeKversions) {
                        def kversion = x.rel  // local bind required because closures
                        // Overload CLI if for release previews:
                        // Unfortunately GKE doesn't allow choosing the Kubernetes release in the rapid channel,
                        // effectively making specified kversion a no-op values
                        def beta = x.pre? "beta" : ""
                        def cluster_version = x.pre? "--release-channel rapid" : "--cluster-version ${kversion} --no-enable-autoupgrade"
                        def project = 'bkprtesting'
                        def zone = 'us-east1-b'
                        def platform = "gke-" + (x.pre? "(" + kversion + ")-rapid" : kversion)

                        platforms[platform] = {
                            // single concurrent build per platform ("gke-<version>"), to avoid hitting cloud quota issues
                            lock(platform) { stage(platform) {
                                def retryNum = 0

                                retry(maxRetries) {
                                    def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                    def adminEmail = "${clusterName}@${parentZone}"
                                    def dnsZone = "${clusterName}.${parentZone}"

                                    retryNum++
                                    dir("${env.WORKSPACE}/${clusterName}") {
                                        withEnv(["KUBECONFIG=${env.WORKSPACE}/.kubecfg-${clusterName}"]) {
                                            // kubeprod requires `GOOGLE_APPLICATION_CREDENTIALS`
                                            withCredentials([file(credentialsId: 'gke-kubeprod-jenkins', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                                                runIntegrationTest(platform, "gke --config=${clusterName}-autogen.json --project=${project} --dns-zone=${dnsZone} --email=${adminEmail} --authz-domain=\"*\"", "--dns-suffix ${dnsZone}", (retryNum == maxRetries))
                                                // clusterSetup
                                                {
                                                    container('gcloud') {
                                                        sh """
                                                        gcloud ${beta} container clusters create ${clusterName} \
                                                            --project ${project}                        \
                                                            ${cluster_version}                          \
                                                            --machine-type n1-standard-2                \
                                                            --num-nodes 3                               \
                                                            --zone ${zone}                              \
                                                            --enable-ip-alias                           \
                                                            --preemptible                               \
                                                            --labels 'platform=${gcpLabel(platform)},branch=${gcpLabel(BRANCH_NAME)},build=${gcpLabel(BUILD_TAG)},team=bkpr,created_by=jenkins-bkpr'
                                                        """
                                                        sh "gcloud container clusters get-credentials ${clusterName} --zone ${zone} --project ${project}"
                                                        sh "kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud info --format='value(config.account)')"
                                                    }

                                                    withCredentials([usernamePassword(credentialsId: 'gke-oauthproxy-client', usernameVariable: 'OAUTH_CLIENT_ID', passwordVariable: 'OAUTH_CLIENT_SECRET')]) {
                                                        def saCreds = JsonOutput.toJson(readFile(env.GOOGLE_APPLICATION_CREDENTIALS))
                                                        writeFile([file: "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json", text: """
                                                            {
                                                                "dnsZone": "${dnsZone}",
                                                                "externalDns": { "credentials": ${saCreds} },
                                                                "oauthProxy": { "client_id": "${OAUTH_CLIENT_ID}", "client_secret": "${OAUTH_CLIENT_SECRET}" }
                                                            }
                                                            """]
                                                        )
                                                    }

                                                    writeFile([file: "${env.WORKSPACE}/${clusterName}/kubeprod-manifest.jsonnet", text: """
                                                        (import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/gke.jsonnet") {
                                                            config:: import "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json",
                                                            letsencrypt_environment: "staging",
                                                            prometheus+: import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                                        }
                                                        """]
                                                    )
                                                }
                                                // clusterDestroy
                                                {
                                                    container('gcloud') {
                                                        sh "gcloud container clusters delete ${clusterName} --zone ${zone} --project ${project} --async --quiet || true"
                                                        sh "gcloud dns record-sets import /dev/null --zone=\$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --delete-all-existing || true"
                                                        sh "gcloud dns managed-zones delete \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} || true"
                                                    }
                                                }
                                                // dnsSetup
                                                {
                                                    container('gcloud') {
                                                        withEnv(["PATH+JQ=${tool 'jq'}"]) {
                                                            def output = sh(returnStdout: true, script: "gcloud dns managed-zones describe \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --format=json | jq -r .nameServers")
                                                            insertGlueRecords(clusterName, readJSON(text: output), "60", parentZone, parentZoneResourceGroup)
                                                        }
                                                    }
                                                }
                                                // dnsDestroy
                                                {
                                                    deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                                }
                                            }
                                        }
                                    }
                                }
                            }}
                        }
                    }

                    // See:
                    //  az aks get-versions -l centralus --query 'sort(orchestrators[?orchestratorType==`Kubernetes`].orchestratorVersion)'
                    def aksKversions = releasesFromStr(buildRel.AKS_REL)
                    for (x in aksKversions) {
                        def kversion = x.rel  // local bind required because closures
                        def resourceGroup = 'jenkins-bkpr-rg'
                        def location = "eastus"
                        def platform = "aks-" + kversion

                        platforms[platform] = {
                            // single concurrent build per platform ("aks-<version>"), to avoid hitting cloud quota issues
                            lock(platform) { stage(platform) {
                                def retryNum = 0
                                retry(maxRetries) {
                                    def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                    def adminEmail = "${clusterName}@${parentZone}"
                                    def dnsZone = "${clusterName}.${parentZone}"

                                    retryNum++
                                    dir("${env.WORKSPACE}/${clusterName}") {
                                        withEnv(["KUBECONFIG=${env.WORKSPACE}/.kubecfg-${clusterName}"]) {
                                            // NB: `kubeprod` also uses az cli credentials and $AZURE_SUBSCRIPTION_ID, $AZURE_TENANT_ID.
                                            withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
                                                runIntegrationTest(platform, "aks --config=${clusterName}-autogen.json --dns-resource-group=${resourceGroup} --dns-zone=${dnsZone} --email=${adminEmail}", "--dns-suffix ${dnsZone}", (retryNum == maxRetries))
                                                // clusterSetup
                                                {
                                                    def availableK8sVersions = ""
                                                    def kversion_full = ""

                                                    container('az') {
                                                        availableK8sVersions = sh(returnStdout: true, script: "az aks get-versions --location ${location} --query \"orchestrators[?contains(orchestratorVersion,'${kversion}')].orchestratorVersion\" -o tsv")
                                                    }

                                                    // sort utility from the `az` container does not support the `-V` flag therefore we're running this command outside the az container
                                                    kversion_full = sh(returnStdout: true, script: "echo \"${availableK8sVersions}\" | sort -Vr | head -n1 | tr -d '\n'")

                                                    container('az') {
                                                        // Usually, `az aks create` creates a new service // principal, which is not removed by `az aks
                                                        // delete`. We reuse an existing principal here to
                                                        //      a) avoid this leak
                                                        //      b) avoid having to give the "outer" principal (above) the power to create new service principals.
                                                        withCredentials([azureServicePrincipal('jenkins-bkpr-contributor-sp')]) {
                                                            sh """
                                                            az aks create                               \
                                                                --verbose                               \
                                                                --resource-group ${resourceGroup}       \
                                                                --name ${clusterName}                   \
                                                                --node-count 3                          \
                                                                --node-vm-size Standard_DS2_v2          \
                                                                --location ${location}                  \
                                                                --kubernetes-version ${kversion_full}   \
                                                                --generate-ssh-keys                     \
                                                                --service-principal \$AZURE_CLIENT_ID   \
                                                                --client-secret \$AZURE_CLIENT_SECRET   \
                                                                --tags 'platform=${platform}' 'branch=${BRANCH_NAME}' 'build=${BUILD_URL}' 'team=bkpr' 'created_by=jenkins-bkpr'
                                                            """
                                                        }
                                                        sh "az aks get-credentials --name ${clusterName} --resource-group ${resourceGroup} --admin --file \${KUBECONFIG}"
                                                    }

                                                    // Reuse this service principal for externalDNS and oauth2.  A real (paranoid) production setup would use separate minimal service principals here.
                                                    withCredentials([azureServicePrincipal('jenkins-bkpr-contributor-sp')]) {
                                                        // NB: writeJSON doesn't work without approvals(?)
                                                        // See https://issues.jenkins-ci.org/browse/JENKINS-44587
                                                        writeFile([file: "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json", text: """
                                                            {
                                                              "dnsZone": "${dnsZone}",
                                                              "contactEmail": "${adminEmail}",
                                                              "externalDns": {
                                                                "tenantId": "${AZURE_TENANT_ID}",
                                                                "subscriptionId": "${AZURE_SUBSCRIPTION_ID}",
                                                                "aadClientId": "${AZURE_CLIENT_ID}",
                                                                "aadClientSecret": "${AZURE_CLIENT_SECRET}",
                                                                "resourceGroup": "${resourceGroup}"
                                                              },
                                                              "oauthProxy": {
                                                                "client_id": "${AZURE_CLIENT_ID}",
                                                                "client_secret": "${AZURE_CLIENT_SECRET}",
                                                                "azure_tenant": "${AZURE_TENANT_ID}"
                                                              }
                                                            }
                                                            """]
                                                        )

                                                        writeFile([file: "${env.WORKSPACE}/${clusterName}/kubeprod-manifest.jsonnet", text: """
                                                            (import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks.jsonnet") {
                                                                config:: import "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json",
                                                                letsencrypt_environment: "staging",
                                                                prometheus+: import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                                            }
                                                            """]
                                                        )
                                                    }
                                                }
                                                // clusterDestroy
                                                {
                                                    container('az') {
                                                        sh "az network dns zone delete --yes --name ${dnsZone} --resource-group ${resourceGroup} || true"
                                                        sh "az aks delete --yes --name ${clusterName} --resource-group ${resourceGroup} --no-wait || true"
                                                    }
                                                }
                                                // dnsSetup
                                                {
                                                    container('az') {
                                                        def output = sh(returnStdout: true, script: "az network dns zone show --name ${dnsZone} --resource-group ${resourceGroup} --query nameServers")
                                                        insertGlueRecords(clusterName, readJSON(text: output), "60", parentZone, parentZoneResourceGroup)
                                                        sh "az network dns record-set soa update --resource-group ${resourceGroup} --zone-name ${dnsZone} --expire-time 60 --minimum-ttl 60 --refresh-time 60 --retry-time 60"
                                                    }
                                                }
                                                // dnsDestroy
                                                {
                                                    deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                                }
                                            }
                                        }
                                    }
                                }
                            }}
                        }
                    }

                    def eksKversions = releasesFromStr(buildRel.EKS_REL)
                    for (x in eksKversions) {
                        def kversion = x.rel  // local bind required because closures
                        def awsRegion = "us-east-1"
                        def awsUserPoolId = "${awsRegion}_QkFNHuI5g"
                        def awsZones = ["us-east-1b", "us-east-1f"]
                        def platform = "eks-" + kversion

                        platforms[platform] = {
                            // single concurrent build per platform ("eks-<version>"), to avoid hitting cloud quota issues
                            lock(platform) { stage(platform) {
                                def retryNum = 0
                                retry(maxRetries) {
                                    def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                    def adminEmail = "${clusterName}@${parentZone}"
                                    def dnsZone = "${clusterName}.${parentZone}"

                                    retryNum++
                                    dir("${env.WORKSPACE}/${clusterName}") {
                                        withEnv([
                                            "KUBECONFIG=${env.WORKSPACE}/.kubecfg-${clusterName}",
                                            "AWS_DEFAULT_REGION=${awsRegion}",
                                            "PATH+AWSIAMAUTHENTICATOR=${tool 'aws-iam-authenticator'}",
                                            "PATH+EKSCTL=${tool 'eksctl'}",
                                        ]) {
                                            // kubeprod requires `GOOGLE_APPLICATION_CREDENTIALS`
                                            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-kubeprod-jenkins', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                                                runIntegrationTest(platform, "eks --user-pool-id=${awsUserPoolId} --config=${clusterName}-autogen.json --dns-zone=${dnsZone} --email=${adminEmail}", "--dns-suffix ${dnsZone}", (retryNum == maxRetries))
                                                // clusterSetup
                                                {
                                                    // Create EKS cluster: requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment
                                                    // variables to reference a user in AWS with the correct privileges to create an EKS
                                                    // cluster: https://github.com/weaveworks/eksctl/issues/204#issuecomment-450280786
                                                    sh """
                                                    eksctl create cluster \
                                                        --name ${clusterName} \
                                                        --region ${awsRegion} \
                                                        --zones ${awsZones.join(',')} \
                                                        --version ${kversion} \
                                                        --node-type m5.large \
                                                        --nodes 3 \
                                                        --tags 'platform=${platform},branch=${BRANCH_NAME},build=${BUILD_URL},team=bkpr,created_by=jenkins-bkpr'
                                                    """

                                                    writeFile([file: "${env.WORKSPACE}/${clusterName}/kubeprod-manifest.jsonnet", text: """
                                                        (import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/eks.jsonnet") {
                                                            config:: import "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json",
                                                            letsencrypt_environment: "staging",
                                                            prometheus+: import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                                        }
                                                        """]
                                                    )
                                                }
                                                // clusterDestroy
                                                {
                                                    // Destroy AWS objects
                                                    container('aws') {
                                                        withEnv(["PATH+JQ=${tool 'jq'}"]) {
                                                            sh """
                                                            set +e
                                                            CONFIG="${clusterName}-autogen.json"

                                                            ACCOUNT=\$(aws sts get-caller-identity --query Account --output text)
                                                            aws iam detach-user-policy --user-name "bkpr-${dnsZone}" --policy-arn "arn:aws:iam::\${ACCOUNT}:policy/bkpr-${dnsZone}"
                                                            aws iam delete-policy --policy-arn "arn:aws:iam::\${ACCOUNT}:policy/bkpr-${dnsZone}"

                                                            ACCESS_KEY_ID=\$(cat \${CONFIG} | jq -r .externalDns.aws_access_key_id)
                                                            aws iam delete-access-key --user-name "bkpr-${dnsZone}" --access-key-id "\${ACCESS_KEY_ID}"
                                                            aws iam delete-user --user-name "bkpr-${dnsZone}"

                                                            CLIENT_ID=\$(cat \${CONFIG} | jq -r .oauthProxy.client_id)
                                                            aws cognito-idp delete-user-pool-client --user-pool-id "${awsUserPoolId}" --client-id "\${CLIENT_ID}"

                                                            DNS_ZONE_ID=\$(aws route53 list-hosted-zones-by-name --dns-name "${dnsZone}" --max-items 1 --query 'HostedZones[0].Id' --output text)
                                                            aws route53 list-resource-record-sets \
                                                                        --hosted-zone-id \${DNS_ZONE_ID} \
                                                                        --query '{ChangeBatch:{Changes:ResourceRecordSets[?Type != `NS` && Type != `SOA`].{Action:`DELETE`,ResourceRecordSet:@}}}' \
                                                                        --output json > changes

                                                            aws route53 change-resource-record-sets         \
                                                                        --cli-input-json file://changes     \
                                                                        --hosted-zone-id \${DNS_ZONE_ID}    \
                                                                        --query 'ChangeInfo.Id'             \
                                                                        --output text

                                                            aws route53 delete-hosted-zone      \
                                                                        --id \${DNS_ZONE_ID}    \
                                                                        --query 'ChangeInfo.Id' \
                                                                        --output text
                                                            :
                                                            """
                                                        }
                                                    }
                                                    withEnv(["PATH+EKSCTL=${tool 'eksctl'}"]) {
                                                        sh "eksctl delete cluster --name ${clusterName} --timeout 10m0s || true"
                                                    }
                                                }
                                                // dnsSetup
                                                {
                                                    container('aws') {
                                                        def output = sh(returnStdout: true, script: "aws route53 get-hosted-zone --id \"\$(aws route53 list-hosted-zones-by-name --dns-name \"${dnsZone}\" --max-items 1 --query 'HostedZones[0].Id' --output text)\" --query DelegationSet.NameServers")
                                                        insertGlueRecords(clusterName, readJSON(text: output), "60", parentZone, parentZoneResourceGroup)
                                                    }
                                                }
                                                // dnsDestroy
                                                {
                                                    deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                                }
                                            }
                                        }
                                    }
                                }
                            }}
                        }
                    }

                    // we use GKE for testing the generic platform
                    def genericKversions = releasesFromStr(buildRel.GEN_REL)
                    for (x in genericKversions) {
                        def kversion = x.rel  // local bind required because closures
                        def project = 'bkprtesting'
                        def zone = 'us-east1-b'
                        def platform = "generic-" + kversion
                        def platform_lock = "gke-" + kversion

                        platforms[platform] = {
                            // single concurrent build per platform ("generic-<version>"), to avoid hitting cloud quota issues
                            lock(platform_lock) { stage(platform) {
                                def retryNum = 0

                                retry(maxRetries) {
                                    def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                    def adminEmail = "${clusterName}@${parentZone}"
                                    def dnsZone = "${clusterName}.${parentZone}"

                                    retryNum++
                                    dir("${env.WORKSPACE}/${clusterName}") {
                                        withEnv(["KUBECONFIG=${env.WORKSPACE}/.kubecfg-${clusterName}"]) {
                                            withCredentials([file(credentialsId: 'gke-kubeprod-jenkins', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                                                runIntegrationTest(platform, "generic --config=${clusterName}-autogen.json --dns-zone=${dnsZone} --email=${adminEmail} --authz-domain=\"*\" --keycloak-group=\"\" --keycloak-password=" + UUID.randomUUID().toString().take(8), "--dns-suffix ${dnsZone}", (retryNum == maxRetries))
                                                // clusterSetup
                                                {
                                                    container('gcloud') {
                                                        sh """
                                                        gcloud container clusters create ${clusterName} \
                                                            --cluster-version ${kversion}               \
                                                            --project ${project}                        \
                                                            --machine-type n1-standard-2                \
                                                            --num-nodes 3                               \
                                                            --zone ${zone}                              \
                                                            --no-enable-autoupgrade                     \
                                                            --enable-ip-alias                           \
                                                            --preemptible                               \
                                                            --labels 'platform=${gcpLabel(platform)},branch=${gcpLabel(BRANCH_NAME)},build=${gcpLabel(BUILD_TAG)},team=bkpr,created_by=jenkins-bkpr'
                                                        """
                                                        sh "gcloud container clusters get-credentials ${clusterName} --zone ${zone} --project ${project}"
                                                        sh "kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud info --format='value(config.account)')"
                                                    }

                                                    writeFile([file: "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json", text: """
                                                        {
                                                            "dnsZone": "${dnsZone}"
                                                        }
                                                        """]
                                                    )

                                                    writeFile([file: "${env.WORKSPACE}/${clusterName}/kubeprod-manifest.jsonnet", text: """
                                                        (import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/generic.jsonnet") {
                                                            config:: import "${env.WORKSPACE}/${clusterName}/${clusterName}-autogen.json",
                                                            letsencrypt_environment: "staging",
                                                            prometheus+: import "${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime/tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                                        }
                                                        """]
                                                    )
                                                }
                                                // clusterDestroy
                                                {
                                                    container('gcloud') {
                                                        sh "gcloud container clusters delete ${clusterName} --zone ${zone} --project ${project} --async --quiet || true"
                                                    }
                                                }
                                                // dnsSetup
                                                {
                                                    timeout(time: 300, unit: 'SECONDS') {
                                                        container('az') {
                                                            def ip = "";
                                                            container('kubectl') {
                                                                ip = sh(returnStdout: true, script: """set +x
                                                                    while [ true ]; do
                                                                        ip=\$(kubectl -n kubeprod get svc nginx-ingress-udp -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
                                                                        if [ -n "\${ip}" ]; then echo -n "\${ip}"; break; fi
                                                                        sleep 5
                                                                    done
                                                                """)
                                                            }
                                                            sh "az network dns record-set a add-record --resource-group ${parentZoneResourceGroup} --zone-name ${parentZone} --record-set-name ns-${clusterName} --ipv4-address ${ip} --ttl 60"
                                                            insertGlueRecords(clusterName, readJSON(text: "[ \"ns-${clusterName}.${parentZone}.\" ]"), "60", parentZone, parentZoneResourceGroup)
                                                        }
                                                    }
                                                }
                                                // dnsDestroy
                                                {
                                                    container('az') {
                                                        sh "az network dns record-set a delete --yes --resource-group ${parentZoneResourceGroup} --zone-name ${parentZone} --name ns-${clusterName} || true"
                                                        deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }}
                        }
                    }

                    parallel platforms

                    stage('Release') {
                        if(env.TAG_NAME) {
                            dir("${env.WORKSPACE}/src/github.com/bitnami/kube-prod-runtime") {
                                withGo() {
                                    withCredentials([
                                        usernamePassword(credentialsId: 'github-bitnami-bot', passwordVariable: 'GITHUB_TOKEN', usernameVariable: ''),
                                        [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'jenkins-bkpr-releases', accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']
                                    ]) {
                                        withEnv([
                                            "PATH+ARC=${tool 'arc'}",
                                            "PATH+JQ=${tool 'jq'}",
                                            "PATH+GITHUB_RELEASE=${tool 'github-release'}",
                                            "PATH+AWLESS=${tool 'awless'}",
                                            "GITHUB_USER=bitnami",
                                        ]) {
                                            sh "make dist VERSION=${TAG_NAME}"
                                            sh "make publish VERSION=${TAG_NAME}"
                                        }
                                    }
                                }

                                container(name: 'kaniko', shell: '/busybox/sh') {
                                    withEnv(['PATH+KANIKO=/busybox:/kaniko']) {
                                        sh """#!/busybox/sh
                                        /kaniko/executor --dockerfile `pwd`/Dockerfile --build-arg BKPR_VERSION=${TAG_NAME} --context `pwd` --destination kubeprod/kubeprod:${TAG_NAME}
                                        """
                                    }
                                }
                            }
                        } else {
                            Utils.markStageSkippedForConditional(STAGE_NAME)
                        }
                    }
                    scmPostCommitStatus("success")
                } catch (error) {
                    scmPostCommitStatus("failure")
                    throw error
                }
            }
        }
    }
}
