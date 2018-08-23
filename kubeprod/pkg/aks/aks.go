package aks

import (
	"fmt"
	"os"
	"strings"

	"github.com/Azure/go-autorest/autorest"
	"github.com/Azure/go-autorest/autorest/adal"
	"github.com/Azure/go-autorest/autorest/azure"
	"github.com/Azure/go-autorest/autorest/azure/auth"
	azcli "github.com/Azure/go-autorest/autorest/azure/cli"
	log "github.com/sirupsen/logrus"
)

const (
	// AppID is the registered ID of the "Kubeprod Installer" app
	AppID = "2dcc87f0-6e30-4dca-b572-20d971c63a89"
)

// NewAuthorizerFromCli snarfs credentials from azure-cli's
// stored credentials.  These have a short (~1h?) expiry.
func NewAuthorizerFromCli(resource, tenantID string) (autorest.Authorizer, error) {
	path, err := azcli.AccessTokensPath()
	if err != nil {
		return nil, fmt.Errorf("Unable to find azure-cli tokens path: %v", err)
	}
	tokens, err := azcli.LoadTokens(path)
	if err != nil {
		return nil, fmt.Errorf("Unable to load azure-cli tokens: %v", err)
	}

	for _, t := range tokens {
		if t.RefreshToken == "" {
			log.Debugf("skipping azure-cli token: No refresh token")
			continue
		}

		if !strings.HasSuffix(t.Authority, tenantID) {
			log.Debugf("skipping azure-cli token: incorrect tenant %q", t.Authority)
			continue
		}

		config, err := adal.NewOAuthConfig(azure.PublicCloud.ActiveDirectoryEndpoint, t.Authority)
		if err != nil {
			return nil, err
		}

		// Refresh tokens can refresh any resource(!)
		// Set correct resource, force refresh.
		token := adal.Token{
			Type:         t.TokenType,
			RefreshToken: t.RefreshToken,
			Resource:     resource,
		}

		spToken, err := adal.NewServicePrincipalTokenFromManualToken(*config, t.ClientID, resource, token)
		if err != nil {
			return nil, err
		}

		log.Debugf("Found a bearer token")
		return autorest.NewBearerAuthorizer(spToken), nil
	}

	return nil, fmt.Errorf("No acceptable token found.  Perhaps you need to run `az login` first?")
}

/*
func NewAuthorizerFromCli(subID, tenantID, resource string) (autorest.Authorizer, error) {
	cmd := exec.Command("az", "account", "get-access-token", "--subscription", subID, "--resource", resource, "--output", "json")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	type Token struct {
		AccessToken  string `json:"accessToken"`
		ExpiresOn    string `json:"expiresOn"`
		Subscription string `json:"subscription"`
		Tenant       string `json:"tenant"`
		TokenType    string `json:"tokenType"`
	}
	var t Token
	if err := json.Unmarshal(out, &t); err != nil {
		return nil, err
	}

	token, err := t.ToADALToken()
	if err != nil {
		return nil, fmt.Errorf("Error converting access token to token: %v", err)
	}

	config, err := adal.NewOAuthConfig(azure.PublicCloud.ActiveDirectoryEndpoint, t.Authority)
	if err != nil {
		return nil, err
	}

	spToken, err := adal.NewServicePrincipalTokenFromManualToken(*config, t.ClientID, t.Resource, token)
	if err != nil {
		return nil, err
	}

	log.Debugf("Found a bearer token")
	return autorest.NewBearerAuthorizer(spToken), nil
}
*/

func authorizer(resource, tenantID string) (autorest.Authorizer, error) {
	if os.Getenv("AZURE_AUTH_LOCATION") != "" {
		log.Debugf("Trying to initialise Azure SDK from %s", os.Getenv("AZURE_AUTH_LOCATION"))
		return auth.NewAuthorizerFromFile(resource)
	}

	if os.Getenv("AZURE_TENANT_ID") != "" {
		log.Debug("Trying to initialise Azure SDK from environment")
		auther, err := auth.NewAuthorizerFromEnvironmentWithResource(resource)
		if err == nil {
			return auther, err
		}
		log.Debugf("Failed to initialise Azure SDK from environment: %v", err)
	}

	log.Debug("Trying to initialise Azure SDK from azure-cli credentials")
	return NewAuthorizerFromCli(resource, tenantID)

	/*
		log.Debug("Falling back to interactive authentication")
		config := auth.NewDeviceFlowConfig(AppID, tenantID)
		config.Resource = resource
		return config.Authorizer()
	*/
}
