package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
)

const usage = `Usage:
  agent-preview serve [--hostname HOST] [--listen-address ADDRESS] [--max-leases COUNT]
  agent-preview request --tcp PORT [--web]
  agent-preview request --udp PORT
  agent-preview status|renew|release [--token TOKEN]

Serve flags default to AGENT_PREVIEW_HOSTNAME and AGENT_PREVIEW_LISTEN_ADDRESS.
The token defaults to AGENT_PREVIEW_TOKEN; only request returns it. Results are JSON.
`

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintf(os.Stderr, "agent-preview: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return errors.New("missing subcommand")
	}
	if args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
		fmt.Fprint(stdout, usage)
		return nil
	}
	f := flag.NewFlagSet("agent-preview "+args[0], flag.ContinueOnError)
	f.SetOutput(stderr)
	parse := func() error {
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if f.NArg() != 0 {
			return errors.New("unexpected positional arguments")
		}
		return nil
	}
	c := command{Action: args[0]}
	switch c.Action {
	case "serve":
		host := f.String("hostname", os.Getenv("AGENT_PREVIEW_HOSTNAME"), "public DNS hostname")
		addr := f.String("listen-address", os.Getenv("AGENT_PREVIEW_LISTEN_ADDRESS"), "bridge IPv4 address")
		limit := f.Int("max-leases", maxLeases, "maximum active leases")
		if err := parse(); err != nil {
			return helpOK(err)
		}
		b, err := newBroker(*host, *addr, leaseTTL)
		if err != nil {
			return err
		}
		if *limit < 1 || *limit > lastPort-firstPort+1 {
			return errors.New("--max-leases must be between 1 and 64")
		}
		b.limit = *limit
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		return serve(ctx, b, socketPath())
	case "request":
		tcp := f.Int("tcp", 0, "TCP application port")
		udp := f.Int("udp", 0, "UDP application port")
		f.BoolVar(&c.Web, "web", false, "use HTTPS ingress rather than raw TCP")
		if err := parse(); err != nil {
			return helpOK(err)
		}
		count := 0
		f.Visit(func(fl *flag.Flag) {
			switch fl.Name {
			case "tcp":
				c.Protocol, c.Port = "tcp", *tcp
				count++
			case "udp":
				c.Protocol, c.Port = "udp", *udp
				count++
			}
		})
		if count != 1 || c.Web && c.Protocol != "tcp" {
			return errors.New("choose exactly one of --tcp and --udp; --web requires --tcp")
		}
	case "status", "renew", "release":
		// Keep the environment token out of the flag package's help defaults.
		f.StringVar(&c.Token, "token", "", "lease ownership token (or use AGENT_PREVIEW_TOKEN)")
		if err := parse(); err != nil {
			return helpOK(err)
		}
		if c.Token == "" {
			c.Token = os.Getenv("AGENT_PREVIEW_TOKEN")
		}
		if c.Token == "" {
			return errors.New("provide --token or AGENT_PREVIEW_TOKEN")
		}
	default:
		return fmt.Errorf("unknown subcommand %q (see --help)", c.Action)
	}
	r, err := callBroker(socketPath(), c)
	if err != nil {
		return err
	}
	return json.NewEncoder(stdout).Encode(r)
}

func helpOK(err error) error {
	if errors.Is(err, flag.ErrHelp) {
		return nil
	}
	return err
}
