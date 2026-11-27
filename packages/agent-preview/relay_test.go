package main

import (
	"io"
	"net"
	"testing"
	"time"
)

const testTimeout = 5 * time.Second

func dialTest(t *testing.T, network, host string, port int) net.Conn {
	t.Helper()
	c, err := net.DialTimeout(network, endpoint(host, port), testTimeout)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	c.SetDeadline(time.Now().Add(testTimeout))
	return c
}

func wantClosed(t *testing.T, r io.Reader) {
	t.Helper()
	var one [1]byte
	if _, err := r.Read(one[:]); err == nil {
		t.Fatal("connection still delivered data")
	} else if e, ok := err.(net.Error); ok && e.Timeout() {
		t.Fatal("connection was not closed before deadline")
	}
}

func appTCP(t *testing.T, port int) *net.TCPListener {
	t.Helper()
	ln, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: port})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	return ln
}

func TestTCPHalfCloseAndRelease(t *testing.T) {
	const port = firstPort + 40
	ln := appTCP(t, port)
	b := testBroker(t, leaseTTL)
	l := manage(t, b, command{Action: "request", Protocol: "tcp", Port: port})
	front := dialTest(t, "tcp4", bridge, port).(*net.TCPConn)
	ln.SetDeadline(time.Now().Add(testTimeout))
	back, err := ln.AcceptTCP()
	if err != nil {
		t.Fatal(err)
	}
	defer back.Close()
	back.SetDeadline(time.Now().Add(testTimeout))
	front.Write([]byte("ping"))
	front.CloseWrite()
	if p, err := io.ReadAll(back); err != nil || string(p) != "ping" {
		t.Fatalf("upstream did not see half-close: %q, %v", p, err)
	}
	back.Write([]byte("pong"))
	p := make([]byte, 4)
	if _, err := io.ReadFull(front, p); err != nil || string(p) != "pong" {
		t.Fatalf("downstream reply: %q, %v", p, err)
	}
	manage(t, b, command{Action: "release", Token: l.Token})
	wantClosed(t, front)
	manage(t, b, command{Action: "request", Protocol: "tcp", Port: port})
}

func TestExpiryClosesLiveTCP(t *testing.T) {
	const port = firstPort + 41
	ln := appTCP(t, port)
	b := testBroker(t, leaseTTL)
	l := manage(t, b, command{Action: "request", Protocol: "tcp", Port: port})
	front := dialTest(t, "tcp4", bridge, port)
	ln.SetDeadline(time.Now().Add(testTimeout))
	back, err := ln.AcceptTCP()
	if err != nil {
		t.Fatal(err)
	}
	defer back.Close()
	back.SetDeadline(time.Now().Add(testTimeout))
	front.Write([]byte("x"))
	if _, err := io.ReadFull(back, make([]byte, 1)); err != nil {
		t.Fatal(err)
	}
	// Exercise the real timer without racing connection setup on slow hosts.
	b.mu.Lock()
	b.ttl = 40 * time.Millisecond
	b.mu.Unlock()
	manage(t, b, command{Action: "renew", Token: l.Token})
	wantClosed(t, front)
	wantClosed(t, back)
	if _, err := b.execute(command{Action: "renew", Token: l.Token}); err == nil {
		t.Fatal("expired lease was revived")
	}
}

func TestUDPIsolatesPeersAndClosesOnRelease(t *testing.T) {
	const port = firstPort + 42
	app, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: port})
	if err != nil {
		t.Fatal(err)
	}
	defer app.Close()
	app.SetDeadline(time.Now().Add(testTimeout))
	b := testBroker(t, leaseTTL)
	l := manage(t, b, command{Action: "request", Protocol: "udp", Port: port})
	clients := []net.Conn{dialTest(t, "udp4", bridge, port), dialTest(t, "udp4", bridge, port)}
	peers := make([]*net.UDPAddr, len(clients))
	for i, c := range clients {
		if _, err := c.Write([]byte{byte(i)}); err != nil {
			t.Fatal(err)
		}
		var data [5]byte
		n, peer, err := app.ReadFromUDP(data[:])
		if err != nil || n != 1 || data[0] != byte(i) {
			t.Fatalf("bad forwarded datagram: %v, %v", data[:n], err)
		}
		peers[i] = peer
	}
	if peers[0].Port == peers[1].Port {
		t.Fatal("UDP peers shared an upstream socket")
	}
	for i := len(clients) - 1; i >= 0; i-- {
		app.WriteToUDP([]byte{42, byte(i)}, peers[i])
	}
	for i, c := range clients {
		var data [5]byte
		n, err := c.Read(data[:])
		if err != nil || n != 2 || data[0] != 42 || data[1] != byte(i) {
			t.Fatalf("bad reply routing: %v, %v", data[:n], err)
		}
	}
	manage(t, b, command{Action: "release", Token: l.Token})
	for _, peer := range peers {
		// Successful rebinding proves the old connected UDP socket is gone.
		ln, err := net.ListenUDP("udp4", peer)
		if err != nil {
			t.Fatal(err)
		}
		ln.Close()
	}
	if c, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP(bridge), Port: port}); err == nil {
		c.Close()
	} else {
		t.Fatalf("old UDP listener survived: %v", err)
	}
}
