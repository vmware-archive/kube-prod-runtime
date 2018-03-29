// Force using our pod
def label = UUID.randomUUID().toString()

podTemplate(
label: label,
resourceLimitCpu: '2000m',
resourceLimitMemory: '1Gi',
containers: [
  containerTemplate(name: 'go1-10', image: 'golang:1.10.0', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'debian', image: 'bitnami/minideb:stretch', ttyEnabled: true, command: 'cat'),
]) {

  env.http_proxy = 'http://proxy.webcache'

  node(label) {
    timeout(time: 30) {
      dir('src/github.com/bitnami/kube-prod-runtime') {
        stage('Checkout') {
          checkout scm
        }

        parallel(
        installer: {
          dir('installer') {
            container('go1-10') {
              withEnv(["GOPATH+WS=${env.WORKSPACE}:/go"]) {
                stage('Test installer') {
                  sh 'go version'
                  sh 'make all'
                  sh 'make test'
                  sh 'make vet'
                }

                stage('Build installer release') {
                  sh 'make release VERSION=$BUILD_TAG'
                  dir('release') {
                    sh './installer --help'
                    stash includes: 'installer', name: 'installer'
                  }
                }
              }
            }
          }
          //stash includes: 'tests/**', name: 'tests'
        },
        manifests: {
          dir('manifests') {
            container('debian') {
              withEnv(["KUBECFG_JPATH+VALIDATE=${pwd()}/components:${pwd()}/lib",
                       "KUBECFG=${env.WORKSPACE}/kubecfg"]) {
                stage('Setup') {
                  sh 'apt-get -qy update'
                  sh 'apt-get -qy install wget ca-certificates make'
                  sh 'wget -O $KUBECFG https://github.com/ksonnet/kubecfg/releases/download/v0.7.2/kubecfg-linux-amd64 && chmod +x $KUBECFG'
                }

                stage('Validate') {
                  sh 'make validate KUBECFG="$KUBECFG -v"'
                  stash includes: '**', name: 'manifests'
                }

                stage('Generate') {
                  sh 'make all KUBECFG="$KUBECFG -v"'
                  stash includes: 'platforms/*.yaml', name: 'yaml'
                }
              }
            }
          }
        })
      }
    }
  }
}
