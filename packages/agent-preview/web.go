package main

import (
	"context"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"
)

type webConnKey struct{}

func (b *broker) webServer() *http.Server {
	return &http.Server{
		Handler: http.HandlerFunc(b.serveWeb),
		ConnContext: func(ctx context.Context, c net.Conn) context.Context {
			return context.WithValue(ctx, webConnKey{}, c)
		},
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       time.Minute,
		MaxHeaderBytes:    32 << 10,
		// No read/write deadline on request bodies: they may be live streams.
		DisableGeneralOptionsHandler: true,
	}
}

func (b *broker) serveWeb(w http.ResponseWriter, r *http.Request) {
	// Host is matched literally: no aliases, port suffixes, or trailing dot.
	l := b.lookup(r.Host)
	if l == nil {
		http.NotFound(w, r)
		return
	}
	if r.Method == http.MethodConnect || r.URL.IsAbs() || !strings.HasPrefix(r.RequestURI, "/") {
		http.Error(w, "origin-form request required", http.StatusBadRequest)
		return
	}
	upgrade := r.Header.Values("Upgrade")
	if len(upgrade) > 0 && (len(upgrade) != 1 || !strings.EqualFold(upgrade[0], "websocket")) {
		http.Error(w, "only WebSocket upgrades are supported", http.StatusBadRequest)
		return
	}
	proto := r.Header.Values("X-Forwarded-Proto")
	if len(proto) != 1 || proto[0] != "https" {
		http.Error(w, "expected HTTPS ingress", http.StatusBadRequest)
		return
	}

	front := r.Context().Value(webConnKey{}).(net.Conn)
	if !l.track(front) {
		http.NotFound(w, r)
		return
	}
	defer l.untrack(front)
	ctx, cancel := context.WithCancel(r.Context())
	stop := context.AfterFunc(l.ctx, cancel)
	defer stop()
	defer cancel()

	transport := &http.Transport{
		DisableKeepAlives: len(upgrade) == 0, // WebSocket requires Connection: Upgrade.
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			back, err := l.dialTCP(ctx)
			if err != nil {
				return nil, err
			}
			if !l.track(back) {
				back.Close()
				return nil, net.ErrClosed
			}
			return &trackedConn{Conn: back, lease: l}, nil
		},
	}
	defer transport.CloseIdleConnections()
	target := &url.URL{Scheme: "http", Host: l.target()}
	proxy := &httputil.ReverseProxy{
		Transport: transport,
		Rewrite: func(req *httputil.ProxyRequest) {
			req.SetURL(target)
			req.Out.Host = l.host
			for h := range req.Out.Header {
				if strings.HasPrefix(h, "X-Forwarded-") || h == "X-Real-Ip" || h == "Forwarded" {
					delete(req.Out.Header, h)
				}
			}
			req.Out.Header.Set("X-Forwarded-Proto", "https")
			req.Out.Header.Set("X-Forwarded-Host", l.host)
		},
		FlushInterval: -1, // Flush every write, including unmarked streamed responses.
		ErrorHandler: func(w http.ResponseWriter, _ *http.Request, _ error) {
			http.Error(w, "preview upstream unavailable", http.StatusBadGateway)
		},
	}
	// Do not make response streaming wait for the entire request body on HTTP/1.1.
	_ = http.NewResponseController(w).EnableFullDuplex()
	proxy.ServeHTTP(w, r.WithContext(ctx))
}

type trackedConn struct {
	net.Conn
	lease *lease
}

func (c *trackedConn) Close() error {
	err := c.Conn.Close()
	c.lease.untrack(c.Conn)
	return err
}
