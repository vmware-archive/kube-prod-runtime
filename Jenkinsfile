#!groovy

// Assumed jenkins plugins:
// - ansicolor
// - custom-tools-plugin
// - pipeline-utility-steps (readJSON)
// - kubernetes
// - jobcacher
// - azure-credentials

import groovy.json.JsonOutput
import org.jenkinsci.plugins.pipeline.modeldefinition.Utils

def parentZone = 'tests.bkpr.run'
def parentZoneResourceGroup = 'jenkins-bkpr-rg'

// Force using our pod
def label = env.BUILD_TAG.replaceAll(/[^a-zA-Z0-9-]/, '-').toLowerCase()

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

def waitForRollout(String namespace, int minutes) {
    withEnv(["PATH+KTOOL=${tool 'kubectl'}"]) {
        try {
            timeout(time: minutes, unit: 'MINUTES') {
                sh """
set +x
for deploy in \$(kubectl --namespace ${namespace} get deploy,sts --output name)
do
  echo -n "\nWaiting for rollout of \${deploy} in ${namespace} namespace"
  while ! \$(kubectl --namespace ${namespace} rollout status \${deploy} --watch=false | grep -q -E 'successfully rolled out|rollout status is only available for|rolling update complete|partitioned roll out complete')
  do
    echo -n "."
    sleep 3
  done
done
"""
            }
        } catch (error) {
            sh "kubectl --namespace ${namespace} get po,deploy,svc,ing"
            throw error
        }
    }
}

def insertGlueRecords(String name, java.util.ArrayList nameServers, String ttl, String zone, String resourceGroup) {
    withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
        container('az') {
            sh "az login --service-principal -u \$AZURE_CLIENT_ID -p \$AZURE_CLIENT_SECRET -t \$AZURE_TENANT_ID"
            sh "az account set -s \$AZURE_SUBSCRIPTION_ID"
            for (ns in nameServers) {
                sh "az network dns record-set ns add-record --resource-group ${resourceGroup} --zone-name ${zone} --record-set-name ${name} --nsdname ${ns}"
            }
            sh "az network dns record-set ns update --resource-group ${resourceGroup} --zone-name ${zone} --name ${name} --set ttl=${ttl}"
        }
    }
}

def deleteGlueRecords(String name, String zone, String resourceGroup) {
    withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
        container('az') {
            sh "az login --service-principal -u \$AZURE_CLIENT_ID -p \$AZURE_CLIENT_SECRET -t \$AZURE_TENANT_ID"
            sh "az account set -s \$AZURE_SUBSCRIPTION_ID"
            sh "az network dns record-set ns delete --yes --resource-group ${resourceGroup} --zone-name ${zone} --name ${name} || :"
        }
    }
}

// Clean a string, suitable for use in a GCP "label".
// "It must only contain lowercase letters ([a-z]), numeric characters ([0-9]), underscores (_) and dashes (-). International characters are allowed."
// .. and "must be less than 63 bytes"
@NonCPS
String gcpLabel(String s) {
    s.replaceAll(/[^a-zA-Z0-9_-]+/, '-').toLowerCase().take(62)
}

def runIntegrationTest(String description, String kubeprodArgs, String ginkgoArgs, Closure clusterSetup, Closure dnsSetup) {
    timeout(120) {
        // Regex of tests that are temporarily skipped.  Empty-string
        // to run everything.  Include pointers to tracking issues.
        def skip = ''

        withEnv(["KUBECONFIG=${env.WORKSPACE}/.kubeconf"]) {
            clusterSetup()

            withEnv(["PATH+KTOOL=${tool 'kubectl'}"]) {
                sh "kubectl version; kubectl cluster-info"

                unstash 'binary'
                unstash 'manifests'
                unstash 'tests'

                sh "kubectl --namespace kube-system get po,deploy,svc,ing"

                sh "./bin/kubeprod -v=1 install ${kubeprodArgs} --manifests=manifests"

                dnsSetup()

                waitForRollout("kubeprod", 30)

                sh 'go get github.com/onsi/ginkgo/ginkgo'
                dir('tests') {
                    try {
                        ansiColor('xterm') {
                            sh "ginkgo -v --tags integration -r --randomizeAllSpecs --randomizeSuites --failOnPending --trace --progress --slowSpecThreshold=300 --compilers=2 --nodes=8 --skip '${skip}' -- --junit junit --description '${description}' --kubeconfig ${KUBECONFIG} ${ginkgoArgs}"
                        }
                    } catch (error) {
                        sh "kubectl --namespace kubeprod get po,deploy,svc,ing"
                        input 'Paused for manual debugging'
                            throw error
                    } finally {
                        junit 'junit/*.xml'
                    }
                }
            }
        }
    }
}


podTemplate(
    cloud: 'kubernetes-cluster',
    label: label,
    idleMinutes: 1,  // Allow some best-effort reuse between successive stages
    containers: [
        containerTemplate(
            name: 'go',
            image: 'golang:1.10.1-stretch',
            ttyEnabled: true,
            command: 'cat',
            // Rely on burst CPU, but actually need RAM to avoid OOM killer
            resourceLmitCpu: '2000m',
            resourceLimitMemory: '2Gi',
            resourceRequestCpu: '10m',
            resourceRequestMemory: '1Gi',
        ),
        // Note nested podTemplate doesn't work, so use "fat slaves" for now :(
        // -> https://issues.jenkins-ci.org/browse/JENKINS-42184
        containerTemplate(
            name: 'gcloud',
            image: 'google/cloud-sdk:218.0.0',
            ttyEnabled: true,
            command: 'cat',
            resourceRequestCpu: '1m',
            resourceRequestMemory: '100Mi',
            resourceLimitCpu: '100m',
            resourceLimitMemory: '500Mi',
        ),
        containerTemplate(
            name: 'az',
            image: 'microsoft/azure-cli:2.0.45',
            ttyEnabled: true,
            command: 'cat',
            resourceRequestCpu: '1m',
            resourceRequestMemory: '100Mi',
            resourceLimitCpu: '100m',
            resourceLimitMemory: '500Mi',
        ),
    ],
    yaml: """
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsUser: 1000
    fsGroup: 1000
"""
) {

    env.http_proxy = 'http://proxy.webcache:80/'  // Note curl/libcurl needs explicit :80 !
    // Teach jenkins about the 'go' container env vars
    env.PATH = '/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    env.GOPATH = '/go'

    stage('Checkout') {
        node(label) {
            checkout scm

            // Ideally this should be done in the Release stage, but it seems to be quite a task to get
            // git metadata stash and unstashed properly (see: https://issues.jenkins-ci.org/browse/JENKINS-33126)
            if (env.TAG_NAME) {
                withGo() {
                    withEnv(["PATH+JQ=${tool 'jq'}"]) {
                        withCredentials([usernamePassword(credentialsId: 'github-bitnami-bot', passwordVariable: 'GITHUB_TOKEN', usernameVariable: '')]) {
                            sh "make release-notes VERSION=${TAG_NAME}"
                        }
                        stash includes: 'Release_Notes.md', name: 'release-notes'
                    }
                }
            }

            stash includes: '**', excludes: 'tests/**', name: 'src'
            stash includes: 'tests/**', name: 'tests'
        }
    }

    parallel(
        installer: {
            stage('Build') {
                node(label) {
                    withGo() {
                        dir('src/github.com/bitnami/kube-prod-runtime') {
                            timeout(time: 30) {
                                unstash 'src'

                                dir('kubeprod') {
                                    sh 'go version'
                                    sh 'make all'
                                    sh 'make test'
                                    sh 'make vet'

                                    sh './bin/kubeprod --help'
                                    stash includes: 'bin/**', name: 'binary'
                                }
                            }
                        }
                    }
                }
            }
        },

        manifests: {
            stage('Manifests') {
                node(label) {
                    withGo() {
                        dir('src/github.com/bitnami/kube-prod-runtime') {
                            timeout(time: 30) {
                                unstash 'src'

                                // TODO: use tool, once the next release is made
                                sh 'go get github.com/ksonnet/kubecfg'

                                dir('manifests') {
                                    sh 'make validate KUBECFG="kubecfg -v"'
                                }
                                stash includes: 'manifests/**', excludes: 'manifests/Makefile', name: 'manifests'
                            }
                        }
                    }
                }
            }
        }, failFast: true)

    def platforms = [:]

    // See:
    //  az aks get-versions -l centralus
    //    --query 'sort(orchestrators[?orchestratorType==`Kubernetes`].orchestratorVersion)'
    def aksKversions = ["1.9.11", "1.10.8"]
    for (x in aksKversions) {
        def kversion = x  // local bind required because closures
        def platform = "aks-" + kversion
        platforms[platform] = {
            stage(platform) {
                node(label) {
                    withGo() {
                        dir('src/github.com/bitnami/kube-prod-runtime') {
                            // NB: `kubeprod` also uses az cli credentials and
                            // $AZURE_SUBSCRIPTION_ID, $AZURE_TENANT_ID.
                            withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
                                def resourceGroup = 'jenkins-bkpr-rg'
                                def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                def dnsPrefix = "${clusterName}"
                                def dnsZone = "${dnsPrefix}.${parentZone}"
                                def adminEmail = "${clusterName}@${parentZone}"
                                def location = "eastus"

                                try {
                                    runIntegrationTest(platform, "aks --config=${clusterName}-autogen.json --dns-resource-group=${resourceGroup} --dns-zone=${dnsZone} --email=${adminEmail}", "--dns-suffix ${dnsZone}") {
                                        container('az') {
                                            sh '''
az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET -t $AZURE_TENANT_ID
az account set -s $AZURE_SUBSCRIPTION_ID
'''

                                            // Usually, `az aks create` creates a new service
                                            // principal, which is not removed by `az aks
                                            // delete`. We reuse an existing principal here to
                                            // a) avoid this leak b) avoid having to give the
                                            // "outer" principal (above) the power to create
                                            // new service principals.
                                            withCredentials([azureServicePrincipal('jenkins-bkpr-contributor-sp')]) {
                                                sh """
az aks create                      \
 --verbose                         \
 --resource-group ${resourceGroup} \
 --name ${clusterName}             \
 --node-count 3                    \
 --node-vm-size Standard_DS2_v2    \
 --location ${location}            \
 --kubernetes-version ${kversion}  \
 --generate-ssh-keys               \
 --service-principal \$AZURE_CLIENT_ID \
 --client-secret \$AZURE_CLIENT_SECRET \
 --tags 'platform=${platform}' 'branch=${BRANCH_NAME}' 'build=${BUILD_URL}'
"""
                                            }

                                            sh "az aks get-credentials --name ${clusterName} --resource-group ${resourceGroup} --admin --file \$KUBECONFIG"

                                            waitForRollout("kube-system", 30)
                                        }

                                        // Reuse this service principal for externalDNS and oauth2.  A real (paranoid) production setup would use separate minimal service principals here.
                                        withCredentials([azureServicePrincipal('jenkins-bkpr-contributor-sp')]) {
                                            // NB: writeJSON doesn't work without approvals(?)
                                            // See https://issues.jenkins-ci.org/browse/JENKINS-44587
                                            writeFile([file: "${clusterName}-autogen.json", text: """
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
"""
                                            ])

                                            writeFile([file: 'kubeprod-manifest.jsonnet', text: """
(import "manifests/platforms/aks.jsonnet") {
  config:: import "${clusterName}-autogen.json",
  letsencrypt_environment: "staging",
  prometheus+: import "tests/testdata/prometheus-crashloop-alerts.jsonnet",
}
"""
                                            ])
                                        }
                                    }{
                                        // update glue records in parent zone
                                        container('az') {
                                            def nameServers = []
                                            def output = sh(returnStdout: true, script: "az network dns zone show --name ${dnsZone} --resource-group ${resourceGroup} --query nameServers")
                                            for (ns in readJSON(text: output)) {
                                                nameServers << ns
                                            }
                                            insertGlueRecords(dnsPrefix, nameServers, "60", parentZone, parentZoneResourceGroup)
                                        }
                                    }
                                }
                                finally {
                                    container('az') {
                                        sh "az login --service-principal -u \$AZURE_CLIENT_ID -p \$AZURE_CLIENT_SECRET -t \$AZURE_TENANT_ID"
                                        sh "az account set -s \$AZURE_SUBSCRIPTION_ID"
                                        sh "az network dns zone delete --yes --name ${dnsZone} --resource-group ${resourceGroup} || :"
                                        sh "az aks delete --yes --name ${clusterName} --resource-group ${resourceGroup} --no-wait || :"
                                    }
                                    deleteGlueRecords(dnsPrefix, parentZone, parentZoneResourceGroup)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // See:
    //  gcloud container get-server-config
    def gkeKversions = ["1.9", "1.10"]
    for (x in gkeKversions) {
        def kversion = x  // local bind required because closures
        def platform = "gke-" + kversion
        platforms[platform] = {
            stage(platform) {
                node(label) {
                    withCredentials([
                        file(credentialsId: 'gke-kubeprod-jenkins', variable: 'GOOGLE_APPLICATION_CREDENTIALS'),
                        usernamePassword(credentialsId: 'gke-oauthproxy-client', usernameVariable: 'OAUTH_CLIENT_ID', passwordVariable: 'OAUTH_CLIENT_SECRET'),
                    ]) {
                        withEnv(["CLOUDSDK_CORE_DISABLE_PROMPTS=1"]) {
                            withGo() {
                                dir('src/github.com/bitnami/kube-prod-runtime') {
                                    def project = 'bkprtesting'
                                    def zone = 'us-east1-d'
                                    def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                    def dnsPrefix = "${clusterName}"
                                    def adminEmail = "${clusterName}@${parentZone}"
                                    def dnsZone = "${dnsPrefix}.${parentZone}"

                                    try {
                                        runIntegrationTest(platform, "gke --config=${clusterName}-autogen.json --project=${project} --dns-zone=${dnsZone} --email=${adminEmail} --authz-domain=\"*\"", "--dns-suffix ${dnsZone}") {
                                            container('gcloud') {
                                                sh "gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}"
                                                sh """
gcloud container clusters create ${clusterName} \
 --cluster-version ${kversion} \
 --project ${project} \
 --machine-type n1-standard-2 \
 --num-nodes 3 \
 --zone ${zone} \
 --labels 'platform=${gcpLabel(platform)},branch=${gcpLabel(BRANCH_NAME)},build=${gcpLabel(BUILD_TAG)}'
"""

                                                sh "gcloud container clusters get-credentials ${clusterName} --zone ${zone} --project ${project}"

                                                sh "kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud info --format='value(config.account)')"

                                                waitForRollout("kube-system", 30)
                                            }

                                            // Reuse this service principal for externalDNS and oauth2.  A real (paranoid) production setup would use separate minimal service principals here.
                                            def saCreds = JsonOutput.toJson(readFile(env.GOOGLE_APPLICATION_CREDENTIALS))

                                            // NB: writeJSON doesn't work without approvals(?)
                                            // See https://issues.jenkins-ci.org/browse/JENKINS-44587
                                            writeFile([file: "${clusterName}-autogen.json", text: """
{
  "dnsZone": "${dnsZone}",
  "externalDns": {
    "credentials": ${saCreds}
  },
  "oauthProxy": {
    "client_id": "${OAUTH_CLIENT_ID}",
    "client_secret": "${OAUTH_CLIENT_SECRET}"
  }
}
"""
                                            ])

                                            writeFile([file: 'kubeprod-manifest.jsonnet', text: """
(import "manifests/platforms/gke.jsonnet") {
  config:: import "${clusterName}-autogen.json",
  letsencrypt_environment: "staging",
  prometheus+: import "tests/testdata/prometheus-crashloop-alerts.jsonnet",
}
"""
                                            ])
                                        }{
                                            // update glue records in parent zone
                                            container('gcloud') {
                                                withEnv(["PATH+JQ=${tool 'jq'}"]) {
                                                    def nameServers = []
                                                    def output = sh(returnStdout: true, script: "gcloud dns managed-zones describe \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --format=json | jq -r .nameServers")
                                                    for (ns in readJSON(text: output)) {
                                                        nameServers << ns
                                                    }
                                                    insertGlueRecords(dnsPrefix, nameServers, "60", parentZone, parentZoneResourceGroup)
                                                }
                                            }
                                        }
                                    }
                                    finally {
                                        container('gcloud') {
                                            def disksFilter = "${clusterName}".take(18).replaceAll(/-$/, '')
                                            sh "gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}"
                                            sh "gcloud container clusters delete ${clusterName} --zone ${zone} --project ${project} --quiet || :"
                                            sh "gcloud compute disks delete \$(gcloud compute disks list --project ${project} --filter name:${disksFilter} --format='value(name)') --project ${project} --zone ${zone} --quiet || :"
                                            sh "gcloud dns record-sets import /dev/null --zone=\$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --delete-all-existing"
                                            sh "gcloud dns managed-zones delete \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} || :"
                                        }
                                        deleteGlueRecords(dnsPrefix, parentZone, parentZoneResourceGroup)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    platforms.failFast = true
    parallel platforms

    stage('Release') {
        node(label) {
            if (env.TAG_NAME) {
                withGo() {
                    dir('src/github.com/bitnami/kube-prod-runtime') {
                        timeout(time: 30) {
                            unstash 'src'
                            unstash 'release-notes'

                            sh "make dist VERSION=${TAG_NAME}"

                            withCredentials([
                                usernamePassword(credentialsId: 'github-bitnami-bot', passwordVariable: 'GITHUB_TOKEN', usernameVariable: ''),
                                [
                                $class: 'AmazonWebServicesCredentialsBinding',
                                credentialsId: 'jenkins-bkpr-releases',
                                accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
                                ]
                            ]) {
                                sh "make publish VERSION=${TAG_NAME}"
                            }
                        }
                    }
                }
            } else {
                Utils.markStageSkippedForConditional(STAGE_NAME)
            }
        }
    }
}
