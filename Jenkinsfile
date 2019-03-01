#!groovy

// Assumed jenkins plugins:
// - ansicolor
// - custom-tools-plugin
// - pipeline-utility-steps (readJSON)
// - kubernetes
// - jobcacher
// - azure-credentials
// - aws-credentials

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

def insertGlueRecords(String name, java.util.List nameServers, String ttl, String zone, String resourceGroup) {
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

def runIntegrationTest(String description, String kubeprodArgs, String ginkgoArgs, Closure clusterSetup, Closure dnsSetup, Closure dnsDestroy, Closure bkprDestroy, Closure clusterDestroy) {
    timeout(120) {
        dir('src/github.com/bitnami/kube-prod-runtime') {
            // Regex of tests that are temporarily skipped.  Empty-string
            // to run everything.  Include pointers to tracking issues.
            def skip = ''

            withEnv([
                "KUBECONFIG=${env.WORKSPACE}/.kubeconf",
                "PATH+KTOOL=${tool 'kubectl'}",
                "PATH+KUBECFG=${tool 'kubecfg'}",
            ]) {
                try {
                    clusterSetup()

                    sh "kubectl version; kubectl cluster-info"

                    waitForRollout("kube-system", 30)

                    unstash 'binary'
                    unstash 'manifests'
                    unstash 'tests'

                    sh "kubectl --namespace kube-system get po,deploy,svc,ing"

                    // HACK: wait for k8s api to stabilize
                    retry(3) {
                        try {
                            sh "kubectl api-versions"
                        } catch(error) {
                            sleep 60
                            throw error
                        }
                    }

                    try {
                        sh "./bin/kubeprod -v=1 install ${kubeprodArgs} --manifests=manifests"
                        try {
                            // DNS set up must run after `kubeprod` install because in some platforms,
                            // like EKS, it's `kubeprod` which creates the DNS hosted zone in the
                            // underlying cloud platform, and dnsSetup() closure needs to wait until
                            // the DNS hosted zone has been created.
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
                        } finally {
                            dnsDestroy()
                        }
                    } finally {
                        bkprDestroy()
                    }
                } finally {
                    clusterDestroy()
                }
            }
        }
    }
}


podTemplate(cloud: 'kubernetes-cluster', label: label, idleMinutes: 1,  yaml: """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: 'go'
    image: 'golang:1.10.1-stretch'
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
  - name: 'gcloud'
    image: 'google/cloud-sdk:218.0.0'
    tty: true
    command:
    - 'cat'
  - name: 'az'
    image: 'microsoft/azure-cli:2.0.45'
    tty: true
    command:
    - 'cat'
  - name: 'eksctl'
    image: 'weaveworks/eksctl:093ee46b-dirty-d45cade'
    tty: true
    command:
    - 'cat'
  - name: 'aws'
    image: 'mesosphere/aws-cli:1.14.5'
    tty: true
    command:
    - 'cat'
  - name: 'kaniko'
    image: 'gcr.io/kaniko-project/executor:debug-v0.8.0'
    tty: true
    command:
    - '/busybox/cat'
    volumeMounts:
    - name: docker-config
      mountPath: /root
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
                                dir('manifests') {
                                    withEnv(["PATH+KUBECFG=${tool 'kubecfg'}"]) {
                                        sh 'make validate KUBECFG="kubecfg -v"'
                                    }
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
    //  gcloud container get-server-config
    def gkeKversions = ["1.11"]
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
                                def project = 'bkprtesting'
                                def zone = 'us-east1-b'
                                def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                                def adminEmail = "${clusterName}@${parentZone}"
                                def dnsZone = "${clusterName}.${parentZone}"

                                runIntegrationTest(platform, "gke --config=${clusterName}-autogen.json --project=${project} --dns-zone=${dnsZone} --email=${adminEmail} --authz-domain=\"*\"", "--dns-suffix ${dnsZone}")
                                // Cluster setup
                                {
                                    container('gcloud') {
                                        sh "gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}"
                                        sh "gcloud container clusters create ${clusterName} --cluster-version ${kversion} --project ${project} --machine-type n1-standard-2 --num-nodes 3 --zone ${zone} --preemptible --labels 'platform=${gcpLabel(platform)},branch=${gcpLabel(BRANCH_NAME)},build=${gcpLabel(BUILD_TAG)}'"
                                        sh "gcloud container clusters get-credentials ${clusterName} --zone ${zone} --project ${project}"
                                        sh "kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=\$(gcloud info --format='value(config.account)')"
                                    }

                                    // Reuse this service principal for externalDNS and oauth2.  A real (paranoid) production setup would use separate minimal service principals here.
                                    def saCreds = JsonOutput.toJson(readFile(env.GOOGLE_APPLICATION_CREDENTIALS))

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
                                        """])

                                    writeFile([file: 'kubeprod-manifest.jsonnet', text: """
                                        (import "manifests/platforms/gke.jsonnet") {
                                        config:: import "${clusterName}-autogen.json",
                                        letsencrypt_environment: "staging",
                                        prometheus+: import "tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                        }
                                        """])
                                }
                                // DNS setup
                                {
                                    // update glue records in parent zone
                                    container('gcloud') {
                                        withEnv(["PATH+JQ=${tool 'jq'}"]) {
                                            def output = sh(returnStdout: true, script: "gcloud dns managed-zones describe \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --format=json | jq -r .nameServers")
                                            def nameServers = readJSON(text: output)
                                            insertGlueRecords(clusterName, nameServers, "60", parentZone, parentZoneResourceGroup)
                                        }
                                    }
                                }
                                // DNS destroy
                                {
                                    deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                }
                                // BKPR destroy
                                {
                                }
                                // Cluster destroy
                                {
                                    container('gcloud') {
                                        def disksFilter = "${clusterName}".take(18).replaceAll(/-$/, '')
                                        sh "gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}"
                                        sh "gcloud container clusters delete ${clusterName} --zone ${zone} --project ${project} --quiet || :"
                                        sh "gcloud compute disks delete \$(gcloud compute disks list --project ${project} --filter name:${disksFilter} --format='value(name)') --project ${project} --zone ${zone} --quiet || :"
                                        sh "gcloud dns record-sets import /dev/null --zone=\$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} --delete-all-existing"
                                        sh "gcloud dns managed-zones delete \$(gcloud dns managed-zones list --filter dnsName:${dnsZone} --format='value(name)' --project ${project}) --project ${project} || :"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // See:
    //  az aks get-versions -l centralus
    //    --query 'sort(orchestrators[?orchestratorType==`Kubernetes`].orchestratorVersion)'
    def aksKversions = ["1.10", "1.11"]
    for (x in aksKversions) {
        def kversion = x  // local bind required because closures
        def platform = "aks-" + kversion
        platforms[platform] = {
            stage(platform) {
                node(label) {
                    withGo() {
                        // NB: `kubeprod` also uses az cli credentials and
                        // $AZURE_SUBSCRIPTION_ID, $AZURE_TENANT_ID.
                        withCredentials([azureServicePrincipal('jenkins-bkpr-owner-sp')]) {
                            def resourceGroup = 'jenkins-bkpr-rg'
                            def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9-]/, '-').replaceAll(/--/, '-').toLowerCase()
                            def dnsZone = "${clusterName}.${parentZone}"
                            def adminEmail = "${clusterName}@${parentZone}"
                            def location = "eastus"
                            def availableK8sVersions = ""
                            def kversion_full = ""

                            runIntegrationTest(platform, "aks --config=${clusterName}-autogen.json --dns-resource-group=${resourceGroup} --dns-zone=${dnsZone} --email=${adminEmail}", "--dns-suffix ${dnsZone}")
                            // Cluster setup
                            {
                                container('az') {
                                    sh '''
                                        az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET -t $AZURE_TENANT_ID
                                        az account set -s $AZURE_SUBSCRIPTION_ID
                                    '''
                                    availableK8sVersions = sh(returnStdout: true, script: "az aks get-versions --location ${location} --query \"orchestrators[?contains(orchestratorVersion,'${kversion}')].orchestratorVersion\" -o tsv")
                                }

                                // sort utility from the `az` container does not support the `-V` flag
                                // therefore we're running this command outside the az container
                                kversion_full = sh(returnStdout: true, script: "echo \"${availableK8sVersions}\" | sort -Vr | head -n1 | tr -d '\n'")

                                container('az') {
                                    // Usually, `az aks create` creates a new service
                                    // principal, which is not removed by `az aks
                                    // delete`. We reuse an existing principal here to
                                    // a) avoid this leak b) avoid having to give the
                                    // "outer" principal (above) the power to create
                                    // new service principals.
                                    withCredentials([azureServicePrincipal('jenkins-bkpr-contributor-sp')]) {
                                        sh "az aks create --verbose --resource-group ${resourceGroup} --name ${clusterName} --node-count 3 --node-vm-size Standard_DS2_v2 --location ${location} --kubernetes-version ${kversion_full} --generate-ssh-keys --service-principal \$AZURE_CLIENT_ID --client-secret \$AZURE_CLIENT_SECRET --tags 'platform=${platform}' 'branch=${BRANCH_NAME}' 'build=${BUILD_URL}'"
                                    }
                                    sh "az aks get-credentials --name ${clusterName} --resource-group ${resourceGroup} --admin --file \$KUBECONFIG"
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
                                        """])

                                    writeFile([file: 'kubeprod-manifest.jsonnet', text: """
                                        (import "manifests/platforms/aks.jsonnet") {
                                            config:: import "${clusterName}-autogen.json",
                                            letsencrypt_environment: "staging",
                                            prometheus+: import "tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                        }
                                        """])
                                }
                            }
                            // DNS setup
                            {
                                // update glue records in parent zone
                                container('az') {
                                    def output = sh(returnStdout: true, script: "az network dns zone show --name ${dnsZone} --resource-group ${resourceGroup} --query nameServers")
                                    def nameServers = readJSON(text: output)
                                    insertGlueRecords(clusterName, nameServers, "60", parentZone, parentZoneResourceGroup)
                                }
                            }
                            // DNS destroy
                            {
                                deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                            }
                            // BKPR destroy
                            {
                            }
                            // Cluster destroy
                            {
                                container('az') {
                                    sh "az login --service-principal -u \$AZURE_CLIENT_ID -p \$AZURE_CLIENT_SECRET -t \$AZURE_TENANT_ID"
                                    sh "az account set -s \$AZURE_SUBSCRIPTION_ID"
                                    sh "az network dns zone delete --yes --name ${dnsZone} --resource-group ${resourceGroup} || :"
                                    sh "az aks delete --yes --name ${clusterName} --resource-group ${resourceGroup} --no-wait || :"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    def eksVersions = ["1.10", "1.11"]
    for (x in eksVersions) {
        def kversion = x // local bind required because closures
        def platform = "eks-${kversion}"
        def awsRegion = "us-east-1"
        def awsZones = ["us-east-1b", "us-east-1f"]
        platforms[platform] = {
            stage(platform) {
                node(label) {
                    withCredentials([[
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-eks-kubeprod-jenkins',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
                    ]]) {
                        withGo() {
                            withEnv([
                                "AWS_DEFAULT_REGION=${awsRegion}",
                                // https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
                                "PATH+AWSIAMAUTHENTICATOR=${tool 'aws-iam-authenticator'}"
                            ]) {
                                def awsUserPoolId = "${awsRegion}_zkRzdsjxA"
                                def clusterName = ("${env.BRANCH_NAME}".take(8) + "-${env.BUILD_NUMBER}-" + UUID.randomUUID().toString().take(5) + "-${platform}").replaceAll(/[^a-zA-Z0-9]+/, '-').toLowerCase()
                                def adminEmail = "${clusterName}@${parentZone}"
                                def dnsZone = "${clusterName}.${parentZone}"

                                runIntegrationTest(platform, "eks --user-pool-id=${awsUserPoolId} --config=${clusterName}-autogen.json --dns-zone=${dnsZone} --email=${adminEmail}", "--dns-suffix ${dnsZone}")
                                // Cluster setup
                                {
                                    // Create EKS cluster: requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment
                                    // variables to reference a user in AWS with the correct privileges to create an EKS
                                    // cluster: https://github.com/weaveworks/eksctl/issues/204#issuecomment-450280786
                                    container('eksctl') {
                                        sh "eksctl create cluster --name ${clusterName} --region ${awsRegion} --zones ${awsZones.join(',')} --version ${kversion} --node-type m5.large --nodes 3 --kubeconfig \$KUBECONFIG --tags 'platform=${platform},branch=${BRANCH_NAME},build=${BUILD_URL}'"
                                    }

                                    writeFile([file: 'kubeprod-manifest.jsonnet', text: """
                                        (import "manifests/platforms/eks.jsonnet") {
                                            config:: import "${clusterName}-autogen.json",
                                            letsencrypt_environment: "staging",
                                            prometheus+: import "tests/testdata/prometheus-crashloop-alerts.jsonnet",
                                        }
                                        """])
                                }
                                // DNS setup
                                {
                                    // update glue records in parent zone
                                    def nameServers = []
                                    container('aws') {
                                        def output = sh(returnStdout: true, script: """
                                            id=\$(aws route53 list-hosted-zones-by-name --dns-name "${dnsZone}" --max-items 1 --query 'HostedZones[0].Id' --output text)
                                            aws route53 get-hosted-zone --id "\$id" --query DelegationSet.NameServers
                                        """)
                                        nameServers = readJSON(text: output)
                                    }
                                    insertGlueRecords(clusterName, nameServers, "60", parentZone, parentZoneResourceGroup)
                                }
                                // DNS destroy
                                {
                                    deleteGlueRecords(clusterName, parentZone, parentZoneResourceGroup)
                                }
                                // BKPR destroy
                                {
                                    // Uninstall BKPR
                                    // This is required for AWS in order to release/destroy ELB network interfaces.
                                    sh """
                                        set +e
                                        kubecfg -v delete --kubeconfig \$KUBECONFIG kubeprod-manifest.jsonnet
                                        kubectl wait --for=delete ns/kubeprod --timeout=600s
                                        :
                                    """

                                    // Destroy AWS objects
                                    container('aws') {
                                        withEnv([
                                            "PATH+JQ=${tool 'jq'}",
                                            "HOME=${env.WORKSPACE}",
                                        ]) {
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

                                                aws route53 change-resource-record-sets \
                                                            --cli-input-json file://changes \
                                                            --hosted-zone-id \${DNS_ZONE_ID} \
                                                            --query 'ChangeInfo.Id' \
                                                            --output text

                                                aws route53 delete-hosted-zone \
                                                            --id \${DNS_ZONE_ID} \
                                                            --query 'ChangeInfo.Id' \
                                                            --output text

                                                :
                                            """
                                        }
                                    }
                                }
                                // Cluster destroy
                                {
                                    // Delete the EKS cluster
                                    container('eksctl') {
                                        sh "eksctl delete cluster --name ${clusterName}"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    parallel platforms

    stage('Release') {
        node(label) {
            if (env.TAG_NAME) {
                timeout(time: 30) {
                    dir('src/github.com/bitnami/kube-prod-runtime') {
                        unstash 'src'
                        withGo() {
                            unstash 'release-notes'

                            sh "make dist VERSION=${TAG_NAME}"

                            withCredentials([
                                usernamePassword(credentialsId: 'github-bitnami-bot', passwordVariable: 'GITHUB_TOKEN', usernameVariable: ''),
                                // AWS credentials used to publish Docker images to an AWS S3 bucket
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

                        container(name: 'kaniko', shell: '/busybox/sh') {
                            withEnv(['PATH+KANIKO=/busybox:/kaniko']) {
                                sh """#!/busybox/sh
                                /kaniko/executor --dockerfile `pwd`/Dockerfile --build-arg BKPR_VERSION=${TAG_NAME} --context `pwd` --destination kubeprod/kubeprod:${TAG_NAME}
                                """
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
