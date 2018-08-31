package prodruntime

import (
	"fmt"
	"net/url"
)

type Platform struct {
	Name        string
	Description string
}

// Platforms should append themselves to this in init()
var Platforms = []Platform{}

func FindPlatform(name string) *Platform {
	for i := range Platforms {
		p := &Platforms[i]
		if p.Name == name {
			return p
		}
	}
	return nil
}

func (p *Platform) ManifestURL(base *url.URL) (*url.URL, error) {
	return base.Parse(fmt.Sprintf("platforms/%s.jsonnet", p.Name))
}
