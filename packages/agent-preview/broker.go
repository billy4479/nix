package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	webPort   = 19999
	firstPort = 20000
	lastPort  = 20063
	maxLeases = 16
	leaseTTL  = 30 * time.Minute
)

type command struct {
	Action   string `json:"action"`
	Protocol string `json:"protocol,omitempty"`
	Port     int    `json:"port,omitempty"`
	Web      bool   `json:"web,omitempty"`
	Token    string `json:"token,omitempty"`
}

type result struct {
	Protocol  string    `json:"protocol"`
	Port      int       `json:"port"`
	Web       bool      `json:"web"`
	Endpoint  string    `json:"endpoint"`
	ExpiresAt time.Time `json:"expires_at"`
	Token     string    `json:"token,omitempty"`
	Released  bool      `json:"released,omitempty"`
}

type slot struct {
	protocol string
	port     int
}

type lease struct {
	slot
	host     string
	token    string
	deadline time.Time // broker.mu
	timer    *time.Timer
	ctx      context.Context
	cancel   context.CancelFunc

	mu     sync.Mutex
	active map[io.Closer]struct{}
}

// track and stop serialize connection registration and teardown. Closers must
// close without waiting on handlers (in particular, use the raw web net.Conn).
func (l *lease) track(c io.Closer) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.ctx.Err() != nil || len(l.active) >= 1024 {
		return false
	}
	l.active[c] = struct{}{}
	return true
}

func (l *lease) untrack(c io.Closer) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.active, c)
}

func (l *lease) stop() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.cancel()
	for c := range l.active {
		_ = c.Close()
	}
	clear(l.active)
}

type broker struct {
	hostname string
	address  string
	ttl      time.Duration
	limit    int

	mu      sync.Mutex
	closed  bool
	byToken map[string]*lease
	byHost  map[string]*lease
	bySlot  map[slot]*lease
}

func newBroker(hostname, address string, ttl time.Duration) (*broker, error) {
	ip, err := netip.ParseAddr(address)
	if err != nil || !ip.Is4() || ip.IsUnspecified() || ip == netip.AddrFrom4([4]byte{127, 0, 0, 1}) || !ip.IsGlobalUnicast() && !ip.IsLoopback() {
		return nil, errors.New("--listen-address must be an explicit unicast IPv4 address other than the app target 127.0.0.1")
	}
	// Reserve room for the 32-hex-character ID and dot on each lease name.
	if len(hostname) > 220 || !validHostname(hostname) {
		return nil, errors.New("--hostname must be a lowercase DNS hostname (without scheme, port, or trailing dot)")
	}
	return &broker{hostname: hostname, address: ip.String(), ttl: ttl, limit: maxLeases,
		byToken: make(map[string]*lease), byHost: make(map[string]*lease), bySlot: make(map[slot]*lease)}, nil
}

func validHostname(host string) bool {
	for _, s := range strings.Split(host, ".") {
		if len(s) == 0 || len(s) > 63 || s[0] == '-' || s[len(s)-1] == '-' {
			return false
		}
		for _, c := range s {
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
				return false
			}
		}
	}
	return true
}

func endpoint(host string, port int) string { return net.JoinHostPort(host, strconv.Itoa(port)) }

func (l *lease) target() string { return endpoint("127.0.0.1", l.port) }

func (b *broker) removeLocked(l *lease) {
	l.timer.Stop()
	l.stop()
	delete(b.bySlot, l.slot)
	delete(b.byToken, l.token)
	delete(b.byHost, l.host)
}

func (b *broker) pruneLocked(now time.Time) {
	for _, l := range b.byToken {
		if !now.Before(l.deadline) {
			b.removeLocked(l)
		}
	}
}

func (b *broker) resetLocked(l *lease) {
	if l.timer != nil {
		l.timer.Stop()
	}
	l.deadline = time.Now().Add(b.ttl)
	l.timer = time.AfterFunc(time.Until(l.deadline), func() {
		b.mu.Lock()
		defer b.mu.Unlock()
		b.pruneLocked(time.Now())
	})
}

func (b *broker) close() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.closed = true
	for _, l := range b.byToken {
		b.removeLocked(l)
	}
}

func (b *broker) lookup(host string) *lease {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.pruneLocked(time.Now())
	return b.byHost[host]
}

func (b *broker) execute(c command) (result, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		return result{}, errors.New("broker is shutting down")
	}
	b.pruneLocked(time.Now())
	if c.Action == "request" {
		return b.requestLocked(c)
	}
	if c.Action != "status" && c.Action != "renew" && c.Action != "release" {
		return result{}, errors.New("unknown action")
	}
	l := b.byToken[c.Token]
	if l == nil {
		return result{}, errors.New("lease expired, does not exist, or token is incorrect")
	}
	if c.Action == "renew" {
		b.resetLocked(l)
	}
	r := b.describeLocked(l)
	if c.Action == "release" {
		b.removeLocked(l)
		r.Released = true
	}
	return r, nil
}

func (b *broker) requestLocked(c command) (result, error) {
	if c.Port < firstPort || c.Port > lastPort {
		return result{}, fmt.Errorf("port must be in %d-%d", firstPort, lastPort)
	}
	if c.Protocol != "tcp" && c.Protocol != "udp" || c.Web && c.Protocol != "tcp" {
		return result{}, errors.New("select tcp or udp; web requires tcp")
	}
	s := slot{c.Protocol, c.Port}
	if b.bySlot[s] != nil {
		return result{}, errors.New("protocol/port already leased")
	}
	if len(b.byToken) >= b.limit {
		return result{}, errors.New("active lease limit reached")
	}
	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return result{}, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	l := &lease{slot: s, token: hex.EncodeToString(secret[:]), ctx: ctx, cancel: cancel, active: make(map[io.Closer]struct{})}
	if c.Web {
		// Independently random: knowing the public hostname gives no token bits.
		var id [16]byte
		if _, err := rand.Read(id[:]); err != nil {
			cancel()
			return result{}, err
		}
		l.host = hex.EncodeToString(id[:]) + "." + b.hostname
	} else if err := l.startRaw(endpoint(b.address, c.Port)); err != nil {
		cancel()
		return result{}, fmt.Errorf("listen on %s/%d: %w", c.Protocol, c.Port, err)
	}
	b.resetLocked(l)
	b.bySlot[s], b.byToken[l.token] = l, l
	if c.Web {
		b.byHost[l.host] = l
	}
	r := b.describeLocked(l)
	r.Token = l.token
	return r, nil
}

func (b *broker) describeLocked(l *lease) result {
	r := result{Protocol: l.protocol, Port: l.port, Web: l.host != "", ExpiresAt: l.deadline.UTC()}
	if r.Web {
		r.Endpoint = "https://" + l.host
	} else {
		r.Endpoint = l.protocol + "://" + endpoint(b.hostname, l.port)
	}
	return r
}
