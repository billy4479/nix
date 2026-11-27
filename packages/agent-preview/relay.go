package main

import (
	"context"
	"io"
	"net"
	"net/netip"
	"sync"
	"time"
)

func (l *lease) startRaw(address string) error {
	if l.protocol == "tcp" {
		ln, err := net.Listen("tcp4", address)
		if err != nil {
			return err
		}
		l.track(ln)
		go func() {
			for {
				c, err := ln.Accept()
				if err != nil {
					if l.ctx.Err() != nil {
						return
					}
					// For example, retry after transient file descriptor exhaustion.
					time.Sleep(100 * time.Millisecond)
					continue
				}
				if !l.track(c) {
					c.Close()
					continue
				}
				go l.relayTCP(c.(*net.TCPConn))
			}
		}()
		return nil
	}
	a := netip.MustParseAddrPort(address)
	ln, err := net.ListenUDP("udp4", net.UDPAddrFromAddrPort(a))
	if err != nil {
		return err
	}
	l.track(ln)
	r := &udpRelay{front: ln, lease: l, peers: make(map[netip.AddrPort]*net.UDPConn)}
	go r.run()
	return nil
}

func (l *lease) dialTCP(ctx context.Context) (net.Conn, error) {
	d := net.Dialer{Timeout: 5 * time.Second}
	return d.DialContext(ctx, "tcp4", l.target())
}

func (l *lease) relayTCP(front *net.TCPConn) {
	defer l.untrack(front)
	defer front.Close()
	conn, err := l.dialTCP(l.ctx)
	if err != nil {
		return
	}
	if !l.track(conn) {
		conn.Close()
		return
	}
	defer l.untrack(conn)
	defer conn.Close()
	back := conn.(*net.TCPConn)
	copyHalf := func(dst, src *net.TCPConn) {
		if _, err := io.Copy(dst, src); err != nil {
			dst.Close()
			src.Close()
			return
		}
		dst.CloseWrite()
	}
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		copyHalf(back, front)
	}()
	copyHalf(front, back)
	<-finished
}

const (
	udpIdle     = time.Minute
	maxUDPPeers = 128
)

type udpRelay struct {
	front *net.UDPConn
	lease *lease
	mu    sync.Mutex
	peers map[netip.AddrPort]*net.UDPConn
}

func (r *udpRelay) run() {
	buf := make([]byte, 65535)
	for {
		n, from, err := r.front.ReadFromUDPAddrPort(buf)
		if err != nil {
			return
		}
		if peer := r.peer(from); peer != nil {
			_ = peer.SetWriteDeadline(time.Now().Add(time.Second))
			_, _ = peer.Write(buf[:n])
		}
	}
}

func (r *udpRelay) peer(from netip.AddrPort) *net.UDPConn {
	r.mu.Lock()
	defer r.mu.Unlock()
	if peer := r.peers[from]; peer != nil {
		_ = peer.SetReadDeadline(time.Now().Add(udpIdle))
		return peer
	}
	if len(r.peers) >= maxUDPPeers || r.lease.ctx.Err() != nil {
		return nil
	}
	target := netip.MustParseAddrPort(r.lease.target())
	peer, err := net.DialUDP("udp4", nil, net.UDPAddrFromAddrPort(target))
	if err != nil {
		return nil
	}
	if !r.lease.track(peer) {
		peer.Close()
		return nil
	}
	r.peers[from] = peer
	_ = peer.SetReadDeadline(time.Now().Add(udpIdle))
	go r.returnPackets(from, peer)
	return peer
}

func (r *udpRelay) returnPackets(to netip.AddrPort, peer *net.UDPConn) {
	defer func() {
		r.mu.Lock()
		delete(r.peers, to)
		_ = peer.Close()
		r.lease.untrack(peer)
		r.mu.Unlock()
	}()
	buf := make([]byte, 65535)
	for {
		n, err := peer.Read(buf)
		if err != nil {
			return
		}
		if _, err := r.front.WriteToUDPAddrPort(buf[:n], to); err != nil {
			return
		}
	}
}
