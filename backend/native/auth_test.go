package main

import "testing"

func TestPasslibPasswordCompatibility(t *testing.T) {
	const password = "demo-प्रयोग-credential"
	const existingHash = "$pbkdf2-sha256$29000$AAECAwQFBgcICQoLDA0ODw$B3j5LkrHc/CFGmzPv2aVJWhaBczknuCbnEr/QKNgkqA"
	for _, hash := range []string{existingHash, hashPassword(password)} {
		if !verifyPassword(password, hash) {
			t.Fatal("valid credential was rejected")
		}
		if verifyPassword("wrong-password", hash) {
			t.Fatal("invalid credential was accepted")
		}
	}
	if verifyPassword(password, "not-a-passlib-hash") {
		t.Fatal("malformed stored password hash was accepted")
	}
}
