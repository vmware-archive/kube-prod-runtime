// Force using our pod
def label = UUID.randomUUID().toString()

podTemplate(label: label,
containers: [
  containerTemplate(name: 'go1-10', image: 'golang:1.10.0', ttyEnabled: true, command: 'cat'),
  containerTemplate(name: 'debian', image: 'debian:stretch', ttyEnabled: true, command: 'cat'),
]) {

  env.http_proxy = 'http://proxy.webcache'

  node(label) {
    withEnv(["GOPATH+WS=${env.WORKSPACE}:/go"]) {
      dir('src/github.com/bitnami/kube-prod-runtime') {
        checkout scm

        dir('installer') {
          stage('Test installer') {
            container('go1-10') {
              sh 'go version'
              sh 'make all vet test'
            }
          }

          stage('Build installer release') {
            container('go1-10') {
              sh 'make release VERSION=$BUILD_TAG'
              stash includes: 'release/installer', name: 'installer'
            }
          }
        }
      }
    }
  }
}
