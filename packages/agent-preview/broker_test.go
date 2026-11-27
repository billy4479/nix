package main

import (
	"net"
	"strings"
	"testing"
	"time"
)

const bridge = "127.0.0.2"
const publicHost = "preview.example.test"

func testBroker(t *testing.T, ttl time.Duration) *broker {
	t.Helper()
	b, err := newBroker(publicHost, bridge, ttl)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(b.close)
	return b
}

func manage(t *testing.T, b *broker, c command) result {
	t.Helper()
	r, err := b.execute(c)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestLeaseOwnershipAndLimits(t *testing.T) {
	b := testBroker(t, leaseTTL)
	bad := []command{
		{Action: "request", Protocol: "tcp", Port: webPort},
		{Action: "request", Protocol: "tcp", Port: lastPort + 1},
		{Action: "request", Protocol: "udp", Port: firstPort, Web: true},
		{Action: "request", Protocol: "sctp", Port: firstPort},
	}
	for _, c := range bad {
		if _, err := b.execute(c); err == nil {
			t.Fatalf("accepted invalid request: %+v", c)
		}
	}
	c := command{Action: "request", Protocol: "tcp", Port: firstPort, Web: true}
	l := manage(t, b, c)
	if !strings.HasPrefix(l.Endpoint, "https://") || len(l.Token) != 64 {
		t.Fatalf("bad lease response: %+v", l)
	}
	for _, action := range []string{"status", "renew", "release"} {
		if _, err := b.execute(command{Action: action, Token: l.Token[1:]}); err == nil {
			t.Fatalf("allowed unauthorized %s", action)
		}
	}
	s := manage(t, b, command{Action: "status", Token: l.Token})
	if s.Token != "" || s.ExpiresAt != l.ExpiresAt {
		t.Fatalf("status changed deadline or exposed token: %+v", s)
	}
	r := manage(t, b, command{Action: "renew", Token: l.Token})
	if !r.ExpiresAt.After(l.ExpiresAt) || r.Endpoint != l.Endpoint || r.Token != "" {
		t.Fatalf("bad renewal: %+v", r)
	}
	c.Web = false
	if _, err := b.execute(c); err == nil {
		t.Fatal("allowed raw TCP to replace web TCP")
	}
	c.Web = true
	for i := 1; i < maxLeases; i++ {
		manage(t, b, command{Action: "request", Protocol: "tcp", Port: firstPort + i, Web: true})
	}
	if _, err := b.execute(command{Action: "request", Protocol: "tcp", Port: firstPort + maxLeases, Web: true}); err == nil {
		t.Fatal("lease cap ignored")
	}
	manage(t, b, command{Action: "release", Token: l.Token})
	next := manage(t, b, c)
	if next.Endpoint == l.Endpoint || next.Token == l.Token {
		t.Fatal("replacement reused host or token")
	}
	if _, err := b.execute(command{Action: "renew", Token: l.Token}); err == nil {
		t.Fatal("released token usable")
	}
}

func TestRejectUnsafeConfig(t *testing.T) {
	for _, a := range []string{"0.0.0.0", "127.0.0.1", "::", "not-an-address"} {
		if _, err := newBroker(publicHost, a, leaseTTL); err == nil {
			t.Fatalf("accepted unsafe bind address %s", a)
		}
	}
	for _, h := range []string{"https://example.test", "example.test.", "example.test:443", "a..b", "*.example.test"} {
		if _, err := newBroker(h, bridge, leaseTTL); err == nil {
			t.Fatalf("accepted invalid host %s", h)
		}
	}
}

func TestListenerConflictDoesNotReserveSlot(t *testing.T) {
	b := testBroker(t, leaseTTL)
	ln, err := net.Listen("tcp4", endpoint(bridge, firstPort))
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	c := command{Action: "request", Protocol: "tcp", Port: firstPort}
	if _, err := b.execute(c); err == nil {
		t.Fatal("allowed double bind")
	}
	ln.Close()
	manage(t, b, c)
	// UDP has an independent slot on the same number.
	manage(t, b, command{Action: "request", Protocol: "udp", Port: firstPort})
}
