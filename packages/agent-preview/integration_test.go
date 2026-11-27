package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testSocket(t *testing.T) string {
	t.Helper()
	// Avoid the Unix socket pathname limit with deeply nested test names.
	dir, err := os.MkdirTemp("/tmp", "agent-preview-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return filepath.Join(dir, "broker.sock")
}

func startTestServer(t *testing.T, path string) func() {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	b := testBroker(t, leaseTTL)
	done := make(chan error, 1)
	go func() { done <- serve(ctx, b, path) }()
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("server exit: %v", err)
			}
		case <-time.After(testTimeout):
			t.Error("server did not stop")
		}
	}
	t.Cleanup(stop)
	deadline := time.Now().Add(testTimeout)
	for time.Now().Before(deadline) {
		select {
		case err := <-done:
			cancel()
			stopped = true
			t.Fatalf("server startup: %v", err)
		default:
		}
		conn, err := net.DialTimeout("unix", path, 20*time.Millisecond)
		if err == nil {
			conn.Close()
			return stop
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("server did not start")
	return nil
}

func TestCLIAndRestartFailClosed(t *testing.T) {
	path := testSocket(t)
	// Simulate the socket left behind by a killed process.
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	ln.SetUnlinkOnClose(false)
	ln.Close()
	t.Setenv("AGENT_PREVIEW_SOCKET", path)
	stop := startTestServer(t, path)
	if lock, err := lockSocket(path); err == nil {
		lock.Close()
		t.Fatal("second broker acquired live socket lock")
	}
	cli := func(args ...string) result {
		t.Helper()
		var out, stderr bytes.Buffer
		if err := run(args, &out, &stderr); err != nil {
			t.Fatalf("CLI %s: %v (%s)", args[0], err, &stderr)
		}
		var r result
		if err := json.Unmarshal(out.Bytes(), &r); err != nil {
			t.Fatal(err)
		}
		return r
	}
	l := cli("request", "--tcp", "20053", "--web")
	t.Setenv("AGENT_PREVIEW_TOKEN", l.Token)
	if r := cli("status"); r.Endpoint != l.Endpoint || r.Token != "" {
		t.Fatalf("bad status: %+v", r)
	}
	if r := cli("renew"); !r.ExpiresAt.After(l.ExpiresAt) {
		t.Fatalf("renew did not extend TTL: %+v", r)
	}
	stop()
	startTestServer(t, path)
	if _, err := callBroker(path, command{Action: "status", Token: l.Token}); err == nil {
		t.Fatal("old lease survived restart")
	}
	if r := webGet(t, webClient(), strings.TrimPrefix(l.Endpoint, "https://"), "/"); r.StatusCode != http.StatusNotFound {
		r.Body.Close()
		t.Fatalf("old hostname after restart: %s", r.Status)
	} else {
		r.Body.Close()
	}
	next := cli("request", "--tcp", "20053", "--web")
	if next.Endpoint == l.Endpoint || !cli("release", "--token", next.Token).Released {
		t.Fatal("replacement lease reused old hostname or failed to release")
	}
}

func webClient() *http.Client {
	return &http.Client{Transport: &http.Transport{DisableKeepAlives: true}, Timeout: testTimeout}
}

func webGet(t *testing.T, client *http.Client, host, path string) *http.Response {
	t.Helper()
	r, err := http.NewRequest(http.MethodGet, "http://"+endpoint(bridge, webPort)+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Host = host
	r.Header.Set("X-Forwarded-Proto", "https")
	r.Header.Set("X-Forwarded-For", "spoofed")
	r.Header.Set("Forwarded", "host=spoofed")
	out, err := client.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { out.Body.Close() })
	return out
}

func TestWebStreamingAndWebSocketRevocation(t *testing.T) {
	const port = firstPort + 54
	ln := appTCP(t, port)
	streamClosed := make(chan struct{})
	wsClosed := make(chan struct{})
	app := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/stream":
			defer close(streamClosed)
			if r.Header.Get("X-Forwarded-Proto") != "https" || r.Header.Get("X-Forwarded-Host") != r.Host ||
				r.Header.Get("Forwarded") != "" || r.Header.Get("X-Forwarded-For") != "" || r.URL.Query().Get("q") != "test" {
				http.Error(w, "forwarding headers or query are wrong", http.StatusBadRequest)
				return
			}
			fmt.Fprintln(w, r.Host)
			w.(http.Flusher).Flush()
			<-r.Context().Done()
		case "/ws":
			defer close(wsClosed)
			conn, rw, err := http.NewResponseController(w).Hijack()
			if err != nil {
				return
			}
			defer conn.Close()
			_ = conn.SetDeadline(time.Now().Add(testTimeout))
			hash := sha1.Sum([]byte(r.Header.Get("Sec-Websocket-Key") + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
			fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: %s\r\n\r\n", base64.StdEncoding.EncodeToString(hash[:]))
			rw.Flush()
			// Masked single-byte client frame, followed by an unmasked echo.
			var p [7]byte
			if _, err := io.ReadFull(rw, p[:]); err != nil || p[0] != 0x81 || p[1] != 0x81 {
				return
			}
			rw.Write([]byte{0x81, 1, p[6] ^ p[2]})
			rw.Flush()
			_, err = rw.ReadByte()
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				t.Error("upstream websocket was not closed before deadline")
			}
		}
	})}
	go app.Serve(ln)
	t.Cleanup(func() { app.Close() })
	path := testSocket(t)
	startTestServer(t, path)
	l, err := callBroker(path, command{Action: "request", Protocol: "tcp", Port: port, Web: true})
	if err != nil {
		t.Fatal(err)
	}
	host := strings.TrimPrefix(l.Endpoint, "https://")
	client := webClient()
	for _, invalid := range []string{publicHost, "other." + publicHost, host + ":443", host + ".", strings.ToUpper(host)} {
		r := webGet(t, client, invalid, "/")
		r.Body.Close()
		if r.StatusCode != http.StatusNotFound {
			t.Fatalf("invalid host %q got %s", invalid, r.Status)
		}
	}
	r := webGet(t, client, host, "/stream?q=test")
	body := bufio.NewReader(r.Body)
	if p, err := body.ReadString('\n'); err != nil || p != host+"\n" || r.StatusCode != http.StatusOK {
		t.Fatalf("stream not flushed or wrong upstream: %q, %s, %v", p, r.Status, err)
	}
	ws := dialTest(t, "tcp4", bridge, webPort)
	fmt.Fprintf(ws, "GET /ws HTTP/1.1\r\nHost: %s\r\nX-Forwarded-Proto: https\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", host)
	frames := bufio.NewReader(ws)
	switchResponse, err := http.ReadResponse(frames, nil)
	if err != nil || switchResponse.StatusCode != http.StatusSwitchingProtocols ||
		switchResponse.Header.Get("Sec-WebSocket-Accept") != "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" {
		t.Fatalf("websocket upgrade: %v, %v", switchResponse, err)
	}
	ws.Write([]byte{0x81, 0x81, 1, 2, 3, 4, 'x' ^ 1})
	var p [3]byte
	if _, err := io.ReadFull(frames, p[:]); err != nil || p != [3]byte{0x81, 1, 'x'} {
		t.Fatalf("websocket relay: %v, %v", p, err)
	}
	if _, err := callBroker(path, command{Action: "release", Token: l.Token}); err != nil {
		t.Fatal(err)
	}
	wantClosed(t, frames)
	wantClosed(t, body)
	for _, ch := range []chan struct{}{streamClosed, wsClosed} {
		select {
		case <-ch:
		case <-time.After(testTimeout):
			t.Fatal("upstream session survived release")
		}
	}
}
