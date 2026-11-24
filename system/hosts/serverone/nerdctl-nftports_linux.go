package portutil

import (
	"encoding/json"
	"fmt"
	"os/exec"
)

type publishedPort struct {
	IP   string
	Port uint64
}

func readCNIPublishedPorts(protocol string) ([]publishedPort, error) {
	// Listing the ruleset also handles the first container, before CNI has
	// created its table. Query both IPv4 and IPv6 tables in one snapshot.
	cmd := exec.Command("nft", "-j", "-n", "list", "ruleset")
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("listing nftables port mappings: %w", err)
	}
	return parseCNIPublishedPorts(out, protocol)
}

func parseCNIPublishedPorts(data []byte, protocol string) ([]publishedPort, error) {
	var ruleset struct {
		NFTables []struct {
			Rule *struct {
				Table string
				Chain string
				Expr  []struct {
					DNAT  json.RawMessage
					Match *struct {
						Op   string
						Left struct {
							Payload struct{ Protocol, Field string }
						}
						Right json.RawMessage
					}
				}
			}
		}
	}
	if err := json.Unmarshal(data, &ruleset); err != nil {
		return nil, fmt.Errorf("decoding nftables port mappings: %w", err)
	}
	var ports []publishedPort
	for _, object := range ruleset.NFTables {
		r := object.Rule
		if r == nil || r.Table != "cni_hostport" || (r.Chain != "hostports" && r.Chain != "hostip_hostports") {
			continue
		}
		var binding publishedPort
		var dnat bool
		for _, expr := range r.Expr {
			dnat = dnat || expr.DNAT != nil
			m := expr.Match
			if m == nil || m.Op != "==" {
				continue
			}
			p := m.Left.Payload
			switch {
			case p.Protocol == protocol && p.Field == "dport":
				if err := json.Unmarshal(m.Right, &binding.Port); err != nil {
					return nil, fmt.Errorf("decoding CNI host port: %w", err)
				}
			case (p.Protocol == "ip" || p.Protocol == "ip6") && p.Field == "daddr":
				if err := json.Unmarshal(m.Right, &binding.IP); err != nil {
					return nil, fmt.Errorf("decoding CNI host address: %w", err)
				}
			}
		}
		if dnat && binding.Port != 0 {
			ports = append(ports, binding)
		}
	}
	return ports, nil
}
