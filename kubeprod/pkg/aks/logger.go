package aks

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"

	"github.com/Azure/go-autorest/autorest"
	log "github.com/sirupsen/logrus"
)

// This is a copy of autorest.LoggingInspector, except with the logger
// replaced with logrus, and (consequently) the priority dropped from
// `log.Printf` (aka `Info`) to `log.Debugf`

// LoggingInspector implements request and response inspectors that log the full request and
// response to a supplied log.
type LoggingInspector struct {
	Logger *log.Logger
}

// WithInspection returns a PrepareDecorator that emits the http.Request to the supplied logger. The
// body is restored after being emitted.
//
// Note: Since it reads the entire Body, this decorator should not be used where body streaming is
// important. It is best used to trace JSON or similar body values.
func (li LoggingInspector) WithInspection() autorest.PrepareDecorator {
	return func(p autorest.Preparer) autorest.Preparer {
		return autorest.PreparerFunc(func(r *http.Request) (*http.Request, error) {
			var body, b bytes.Buffer

			if r.Body != nil {
				defer r.Body.Close()
				r.Body = ioutil.NopCloser(io.TeeReader(r.Body, &body))
			}

			if err := r.Write(&b); err != nil {
				return nil, fmt.Errorf("Failed to write response: %v", err)
			}

			li.Logger.Debugf("HTTP Request:\n%s", b.String())

			if r.Body != nil {
				r.Body = ioutil.NopCloser(&body)
			}
			return p.Prepare(r)
		})
	}
}

// ByInspecting returns a RespondDecorator that emits the http.Response to the supplied logger. The
// body is restored after being emitted.
//
// Note: Since it reads the entire Body, this decorator should not be used where body streaming is
// important. It is best used to trace JSON or similar body values.
func (li LoggingInspector) ByInspecting() autorest.RespondDecorator {
	return func(r autorest.Responder) autorest.Responder {
		return autorest.ResponderFunc(func(resp *http.Response) error {
			var body, b bytes.Buffer
			if resp.Body != nil {
				defer resp.Body.Close()
				resp.Body = ioutil.NopCloser(io.TeeReader(resp.Body, &body))
			}

			if err := resp.Write(&b); err != nil {
				return fmt.Errorf("Failed to write response: %v", err)
			}

			li.Logger.Debugf("HTTP Response:\n%s", b.String())

			if resp.Body != nil {
				resp.Body = ioutil.NopCloser(&body)
			}
			return r.Respond(resp)
		})
	}
}
