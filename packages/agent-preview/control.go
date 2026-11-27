package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

func socketPath() string {
	if p := os.Getenv("AGENT_PREVIEW_SOCKET"); p != "" {
		return p
	}
	return fmt.Sprintf("/tmp/agent-preview-%d/broker.sock", os.Geteuid())
}

// The socket and lock live in a private directory. The lock makes unlinking a
// socket after SIGKILL safe without disrupting an already running broker.
func lockSocket(path string) (*os.File, error) {
	if !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return nil, errors.New("control socket path must be clean and absolute")
	}
	dir := filepath.Dir(path)
	if err := os.Mkdir(dir, 0700); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := checkSocketDir(path); err != nil {
		return nil, err
	}
	fd, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(fd.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		fd.Close()
		return nil, fmt.Errorf("lock broker socket: %w", err)
	}
	return fd, nil
}

func checkSocketDir(path string) error {
	if !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return errors.New("control socket path must be clean and absolute")
	}
	dir := filepath.Dir(path)
	info, err := os.Lstat(dir)
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode().Perm() != 0700 || info.Sys().(*syscall.Stat_t).Uid != uint32(os.Geteuid()) {
		return fmt.Errorf("socket directory %s must be owned by this UID and have mode 0700", dir)
	}
	return nil
}

func serve(ctx context.Context, b *broker, path string) error {
	defer b.close()
	lock, err := lockSocket(path)
	if err != nil {
		return err
	}
	defer lock.Close()
	if s, err := os.Lstat(path); err == nil {
		if s.Mode()&os.ModeSocket == 0 {
			return errors.New("refusing to replace a non-socket control path")
		}
		if err := os.Remove(path); err != nil {
			return err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	web, err := net.Listen("tcp4", endpoint(b.address, webPort))
	if err != nil {
		return fmt.Errorf("listen for web previews: %w", err)
	}
	defer web.Close()
	control, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return err
	}
	defer control.Close()
	if err := os.Chmod(path, 0600); err != nil {
		return err
	}
	webServer := b.webServer()
	controlServer := &http.Server{
		Handler:        http.HandlerFunc(b.serveControl),
		ReadTimeout:    5 * time.Second,
		WriteTimeout:   5 * time.Second,
		IdleTimeout:    5 * time.Second,
		MaxHeaderBytes: 4096,
	}
	done := make(chan error, 2)
	go func() { done <- webServer.Serve(web) }()
	go func() { done <- controlServer.Serve(control) }()
	select {
	case err = <-done:
	case <-ctx.Done():
	}
	b.close() // Includes upgraded WebSockets, which http.Server.Close does not own.
	_ = controlServer.Close()
	_ = webServer.Close()
	return err
}

type response struct {
	Lease *result `json:"lease,omitempty"`
	Error string  `json:"error,omitempty"`
}

func (b *broker) serveControl(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || r.URL.Path != "/lease" {
		http.NotFound(w, r)
		return
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	d.DisallowUnknownFields()
	var c command
	if err := d.Decode(&c); err != nil || d.Decode(new(any)) != io.EOF {
		http.Error(w, "invalid lease command", http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	lease, err := b.execute(c)
	if err != nil {
		w.WriteHeader(http.StatusConflict)
		_ = json.NewEncoder(w).Encode(response{Error: err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(response{Lease: &lease})
}

func callBroker(path string, c command) (result, error) {
	if err := checkSocketDir(path); err != nil {
		return result{}, fmt.Errorf("cannot contact preview broker: %w", err)
	}
	payload, err := json.Marshal(c)
	if err != nil {
		return result{}, err
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", path)
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 5 * time.Second}
	r, err := client.Post("http://localhost/lease", "application/json", bytes.NewReader(payload))
	if err != nil {
		return result{}, fmt.Errorf("cannot contact preview broker: %w", err)
	}
	defer r.Body.Close()
	var reply response
	if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&reply); err != nil {
		return result{}, fmt.Errorf("invalid broker response (%s): %w", r.Status, err)
	}
	if reply.Error != "" {
		return result{}, errors.New(reply.Error)
	}
	if reply.Lease == nil || r.StatusCode != http.StatusOK {
		return result{}, fmt.Errorf("unexpected broker response (%s)", r.Status)
	}
	return *reply.Lease, nil
}
