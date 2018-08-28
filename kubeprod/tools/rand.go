package tools

import (
	"crypto/rand"
	"encoding/base64"
)

// Base64RandBytes returns a base64 encoded string of `n` random
// bytes.
// NB: `n` is the number of bytes *before* base64 encoding.  The
// returned string will be roughly 4/3 times longer, and includes
// trailing padding if `n` is not a multiple of 3.
func Base64RandBytes(n uint) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(buf), nil
}
