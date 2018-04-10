#!groovy

// Assumed jenkins plugins:
// - ansicolor
// - custom-tools-plugin
// - pipeline-utility-steps (readJSON)
// - kubernetes
// - jobcacher
// - azure-credentials

// Force using our pod
def label = UUID.randomUUID().toString()

podTemplate(
label: "${label} linux x86",
resourceLimitCpu: '2000m',
resourceLimitMemory: '2Gi',
idleMinutes: 1,  // Allow some best-effort reuse between successive stages
containers: [
  containerTemplate(name: 'go', image: 'golang:1.10.1-stretch', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'az', image: 'microsoft/azure-cli:2.0.30', ttyEnabled: true, command: 'cat'),
]) {

  env.http_proxy = 'http://proxy.webcache:80/'  // Note curl/libcurl needs explicit :80 !
  // Teach jenkins about the 'go' container env vars
  env.PATH = '/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  env.GOPATH = '/go'

  node(label) {
    stage('Checkout') {
      checkout scm
      stash includes: '**', name: 'src'
    }
  }

  parallel(
  installer: {
    node(label) {
      container('go') {
        stage('installer') {
          timeout(time: 30) {
            cache(maxCacheSize: 1000, caches: [
                    [$class: 'ArbitraryFileCache', path: "${env.HOME}/.cache/go-build"],
                  ]) {
              withEnv(["GOPATH+WS=${env.WORKSPACE}", "PATH+GOBIN=${env.WORKSPACE}/bin"]) {
                dir('src/github.com/bitnami/kube-prod-runtime') {
                  unstash 'src'

                  dir('installer') {
                    sh 'go version'
                    sh 'make all'
                    sh 'make test'
                    sh 'make vet'

                    sh 'make release VERSION=$BUILD_TAG'
                    dir('release') {
                      sh './installer --help'
                      stash includes: 'installer', name: 'installer'
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  },

  manifests: {
    node(label) {
      container('go') {
        stage('manifests') {
          timeout(time: 30) {
            cache(maxCacheSize: 1000, caches: [
                    [$class: 'ArbitraryFileCache', path: "${env.HOME}/.cache/go-build"],
                  ]) {
              unstash 'src'

              sh 'apt-get -qy update && apt-get -qy install make'
              // TODO: use tool, once the next release is made
              sh 'go get github.com/ksonnet/kubecfg'

              dir('manifests') {
                sh 'make validate KUBECFG="kubecfg -v"'
              }
              stash includes: 'manifests/**', excludes: 'manifests/Makefile', name: 'manifests'

              dir('manifests') {
                sh 'make all KUBECFG="kubecfg -v"'
                stash includes: 'platforms/*.yaml', name: 'yaml'
              }
            }
          }
        }
      }
    }
  })

  def platforms = [:]

  def minikubeKversions = []  // fixme: disabled minikube for now ["v1.8.0", "v1.9.4"]
  for (x in minikubeKversions) {
    def kversion = x  // local bind required because closures
    def platform = "minikube-0.25+k8s-" + kversion[1..3]
    platforms[platform] = {
      timeout(60) {
        node(label) {
          container('go') {
            stage("${platform} setup") {
              withEnv(["PATH+TOOL=${tool 'minikube'}:${tool 'kubectl'}", "HOME=${env.WORKSPACE}"]) {
                cache(maxCacheSize: 1000, caches: [
                        [$class: 'ArbitraryFileCache', path: "${env.HOME}/.minikube/cache"],
                      ]) {
                  sh 'apt-get -qy update && apt-get install -qy qemu-kvm libvirt-clients libvirt-daemon-system virtualbox'
                  sh "minikube start --kubernetes-version=${kversion}"
                }
              }
            }

            stage("${platform} install") {
              unstash 'installer'
              unstash 'manifests'
              sh "./installer --platform=${platform} --manifests=manifests"
            }

            stage("${platform} test") {
              sh 'go get github.com/onsi/ginkgo/ginkgo'
              unstash 'src'
              dir('tests') {
                ansiColor('xterm') {
                  //sh 'ginkgo --tags integration -r --randomizeAllSpecs --randomizeSuites --failOnPending --trace --progress --compilers=2 --nodes=4'
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
  def aksKversions = ["1.8.7", "1.9.2"]
  for (x in aksKversions) {
    def kversion = x  // local bind required because closures
    def platform = "aks+k8s-" + kversion[0..2]
    platforms[platform] = {
      timeout(60) {
        withCredentials([azureServicePrincipal('azure-cli-2018-04-06-01-39-19')]) {
          def resourceGroup = 'prod-runtime-rg'
          node(label) {
            container('go') {
              def aks
              withEnv(["KUBECONFIG=${env.WORKSPACE}/.kubeconf", "HOME=${env.WORKSPACE}"]) {
                try {
                  stage("${platform} setup") {
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
                      withCredentials([azureServicePrincipal('azure-cli-2018-04-06-03-17-41')]) {
                        def name = "${env.BUILD_TAG}-${platform}".replaceAll(/[^a-zA-Z0-9-]/, '-')
                        aks = readJSON(text: sh(script: """
                         az aks create                        \
                            --resource-group ${resourceGroup} \
                            --name ${name}                    \
                            --node-count 3                    \
                            --kubernetes-version ${kversion}  \
                            --generate-ssh-keys                   \
                            --service-principal \$AZURE_CLIENT_ID \
                            --client-secret \$AZURE_CLIENT_SECRET \
                            --tags 'platform=${platform}' 'branch=${env.BRANCH_NAME}' 'build=${env.BUILD_URL}'
                        """, returnStdout: true))
                      }
                      sh "az aks get-credentials --name ${aks.name} --resource-group ${aks.resourceGroup} --admin --file ${env.KUBECONFIG}"
                    }
                  }

                  stage("${platform} install") {
                    dir('do-install') {
                      unstash 'installer'
                      unstash 'manifests'
                      sh "./installer install --platform=${platform} --manifests=manifests"
                    }
                  }

                  stage("${platform} test") {
                    sh 'go get github.com/onsi/ginkgo/ginkgo'
                    unstash 'src'
                    dir('tests') {
                      ansiColor('xterm') {
                        //sh 'ginkgo -r --randomizeAllSpecs --randomizeSuites --failOnPending --trace --progress --compilers=2 --nodes=4'
                      }
                    }
                  }
                }
                finally {
                  if (aks) {
                    container('az') {
                      sh "az aks delete --yes --name ${aks.name} --resource-group ${aks.resourceGroup} --no-wait"
                    }
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
}
