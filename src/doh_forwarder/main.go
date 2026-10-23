package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

func getAndroidCertPool() *x509.CertPool {
	pool, err := x509.SystemCertPool()
	if err != nil || pool == nil {
		pool = x509.NewCertPool()
	}

	dirs := []string{
		"/system/etc/security/cacerts",
		"/etc/security/cacerts",
		"/apex/com.android.conscrypt/cacerts",
		"/data/misc/user/0/cacerts-added",
	}

	loaded := 0
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			fpath := filepath.Join(dir, e.Name())
			data, err := os.ReadFile(fpath)
			if err == nil {
				if pool.AppendCertsFromPEM(data) {
					loaded++
				}
			}
		}
	}
	return pool
}

var knownBootstrapIPs = map[string][]string{
	"dns.google":           {"8.8.8.8", "8.8.4.4"},
	"cloudflare-dns.com":   {"1.1.1.1", "1.0.0.1"},
	"one.one.one.one":      {"1.1.1.1", "1.0.0.1"},
	"dns.quad9.net":        {"9.9.9.9", "149.112.112.112"},
	"dns.adguard-dns.com":  {"94.140.14.14", "94.140.15.15"},
	"dns.mullvad.net":      {"194.242.2.2"},
	"freedns.controld.com": {"76.76.2.0", "76.76.10.0"},
}

func customDialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
		port = "443"
	}

	if net.ParseIP(host) != nil {
		d := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 60 * time.Second}
		return d.DialContext(ctx, network, addr)
	}

	if ips, ok := knownBootstrapIPs[strings.ToLower(host)]; ok && len(ips) > 0 {
		for _, ip := range ips {
			target := net.JoinHostPort(ip, port)
			d := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 60 * time.Second}
			conn, err := d.DialContext(ctx, network, target)
			if err == nil {
				return conn, nil
			}
		}
	}

	resolver := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{Timeout: 2 * time.Second}
			return d.DialContext(ctx, "udp", "1.1.1.1:53")
		},
	}
	ips, err := resolver.LookupHost(ctx, host)
	if err == nil && len(ips) > 0 {
		for _, ip := range ips {
			target := net.JoinHostPort(ip, port)
			d := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 60 * time.Second}
			conn, err := d.DialContext(ctx, network, target)
			if err == nil {
				return conn, nil
			}
		}
	}

	d := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 60 * time.Second}
	return d.DialContext(ctx, network, addr)
}

type CacheEntry struct {
	data      []byte
	expiresAt time.Time
}

type Forwarder struct {
	listenAddr  string
	upstreamURL string
	configFile  string
	mu          sync.RWMutex
	cache       map[string]CacheEntry
	client      *http.Client
	stats       struct {
		sync.Mutex
		queries uint64
		cached  uint64
		errors  uint64
	}
}

func NewForwarder(listenAddr, upstreamURL, configFile string) *Forwarder {
	tr := &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           customDialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          20,
		MaxIdleConnsPerHost:   10,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   3 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		TLSClientConfig: &tls.Config{
			RootCAs:            getAndroidCertPool(),
			InsecureSkipVerify: false,
		},
	}

	return &Forwarder{
		listenAddr:  listenAddr,
		upstreamURL: upstreamURL,
		configFile:  configFile,
		cache:       make(map[string]CacheEntry),
		client: &http.Client{
			Transport: tr,
			Timeout:   4 * time.Second,
		},
	}
}

func (f *Forwarder) reloadConfig() {
	if f.configFile == "" {
		return
	}
	data, err := os.ReadFile(f.configFile)
	if err != nil {
		return
	}
	lines := strings.Split(string(data), "\n")
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "#") || !strings.Contains(l, "=") {
			continue
		}
		parts := strings.SplitN(l, "=", 2)
		k := strings.TrimSpace(parts[0])
		v := strings.Trim(strings.TrimSpace(parts[1]), "\"'")
		if k == "DNS_UPSTREAM" && v != "" {
			f.upstreamURL = v
			log.Printf("[DoH] Updated upstream to: %s", v)
		}
	}
}

func buildDnsQuery(domain string, qtype uint16) ([]byte, error) {
	var buf bytes.Buffer
	qid := uint16(0x4242)
	// Header: ID=0x4242, Flags=0x0100 (RD=1), QDCOUNT=1
	_ = binary.Write(&buf, binary.BigEndian, qid)
	_ = binary.Write(&buf, binary.BigEndian, uint16(0x0100))
	_ = binary.Write(&buf, binary.BigEndian, uint16(1))
	_ = binary.Write(&buf, binary.BigEndian, uint16(0))
	_ = binary.Write(&buf, binary.BigEndian, uint16(0))
	_ = binary.Write(&buf, binary.BigEndian, uint16(0))

	parts := strings.Split(domain, ".")
	for _, p := range parts {
		if len(p) == 0 {
			continue
		}
		buf.WriteByte(byte(len(p)))
		buf.WriteString(p)
	}
	buf.WriteByte(0)
	_ = binary.Write(&buf, binary.BigEndian, qtype)
	_ = binary.Write(&buf, binary.BigEndian, uint16(1)) // IN
	return buf.Bytes(), nil
}

func parseDnsAnswers(resp []byte) ([]string, error) {
	if len(resp) < 12 {
		return nil, fmt.Errorf("response too short")
	}
	rcode := resp[3] & 0x0F
	if rcode != 0 {
		return nil, fmt.Errorf("DNS error code: %d", rcode)
	}
	qdcount := binary.BigEndian.Uint16(resp[4:6])
	ancount := binary.BigEndian.Uint16(resp[6:8])
	if ancount == 0 {
		return nil, fmt.Errorf("no answers")
	}

	idx := 12
	// Skip questions
	for i := 0; i < int(qdcount) && idx < len(resp); i++ {
		for idx < len(resp) {
			l := int(resp[idx])
			idx++
			if l == 0 {
				break
			}
			if (l & 0xC0) == 0xC0 {
				idx++
				break
			}
			idx += l
		}
		idx += 4
	}

	var ips []string
	for i := 0; i < int(ancount) && idx+10 <= len(resp); i++ {
		if (resp[idx] & 0xC0) == 0xC0 {
			idx += 2
		} else {
			for idx < len(resp) {
				l := int(resp[idx])
				idx++
				if l == 0 {
					break
				}
				if (l & 0xC0) == 0xC0 {
					idx++
					break
				}
				idx += l
			}
		}
		if idx+10 > len(resp) {
			break
		}
		atype := binary.BigEndian.Uint16(resp[idx : idx+2])
		idx += 8
		rdlen := int(binary.BigEndian.Uint16(resp[idx : idx+2]))
		idx += 2
		if idx+rdlen > len(resp) {
			break
		}
		if atype == 1 && rdlen == 4 { // A
			ip := net.IP(resp[idx : idx+4])
			ips = append(ips, ip.String())
		} else if atype == 28 && rdlen == 16 { // AAAA
			ip := net.IP(resp[idx : idx+16])
			ips = append(ips, ip.String())
		}
		idx += rdlen
	}
	return ips, nil
}

func runDnsTest(upstreamURL, domain string) {
	if upstreamURL == "" {
		upstreamURL = "https://1.1.1.1/dns-query"
	}
	if domain == "" {
		domain = "discord.com"
	}

	qBytes, err := buildDnsQuery(domain, 1)
	if err != nil {
		fmt.Printf("FAILED|%s|query encode error|0ms\n", domain)
		return
	}

	t0 := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, "POST", upstreamURL, bytes.NewReader(qBytes))
	if err != nil {
		fmt.Printf("FAILED|%s|%v|0ms\n", domain, err)
		return
	}
	httpReq.Header.Set("Content-Type", "application/dns-message")
	httpReq.Header.Set("Accept", "application/dns-message")

	client := &http.Client{
		Timeout: 4 * time.Second,
		Transport: &http.Transport{
			DialContext: customDialContext,
			TLSClientConfig: &tls.Config{
				RootCAs:            getAndroidCertPool(),
				InsecureSkipVerify: false,
			},
		},
	}
	resp, err := client.Do(httpReq)
	if err != nil {
		fmt.Printf("FAILED|%s|%v|0ms\n", domain, err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Printf("FAILED|%s|HTTP %d|0ms\n", domain, resp.StatusCode)
		return
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 65535))
	elapsed := time.Since(t0).Milliseconds()
	if err != nil {
		fmt.Printf("FAILED|%s|body read error|%dms\n", domain, elapsed)
		return
	}

	ips, err := parseDnsAnswers(body)
	if err != nil || len(ips) == 0 {
		fmt.Printf("FAILED|%s|no IP returned|%dms\n", domain, elapsed)
		return
	}

	fmt.Printf("SUCCESS|%s|%s|%dms\n", domain, strings.Join(ips, ", "), elapsed)
}

func extractQuestion(req []byte) (string, uint16, bool) {
	if len(req) < 12 {
		return "", 0, false
	}
	qdcount := binary.BigEndian.Uint16(req[4:6])
	if qdcount < 1 {
		return "", 0, false
	}

	pos := 12
	var domainParts []string
	for pos < len(req) {
		labelLen := int(req[pos])
		if labelLen == 0 {
			pos++
			break
		}
		if labelLen >= 64 || pos+1+labelLen > len(req) {
			return "", 0, false
		}
		domainParts = append(domainParts, string(req[pos+1:pos+1+labelLen]))
		pos += 1 + labelLen
	}

	if pos+4 > len(req) {
		return "", 0, false
	}
	qtype := binary.BigEndian.Uint16(req[pos : pos+2])
	domain := strings.ToLower(strings.Join(domainParts, "."))
	return domain, qtype, true
}

func (f *Forwarder) handlePacket(conn *net.UDPConn, clientAddr *net.UDPAddr, req []byte) {
	if len(req) < 12 {
		return
	}
	queryID := binary.BigEndian.Uint16(req[0:2])
	domain, qtype, ok := extractQuestion(req)

	f.stats.Lock()
	f.stats.queries++
	f.stats.Unlock()

	var cacheKey string
	if ok && domain != "" {
		cacheKey = fmt.Sprintf("%d:%s", qtype, domain)
		f.mu.RLock()
		entry, found := f.cache[cacheKey]
		f.mu.RUnlock()

		if found && time.Now().Before(entry.expiresAt) {
			f.stats.Lock()
			f.stats.cached++
			f.stats.Unlock()

			resp := make([]byte, len(entry.data))
			copy(resp, entry.data)
			binary.BigEndian.PutUint16(resp[0:2], queryID)
			_, _ = conn.WriteToUDP(resp, clientAddr)
			return
		}
	}

	f.mu.RLock()
	upstream := f.upstreamURL
	f.mu.RUnlock()

	ctx, cancel := context.WithTimeout(context.Background(), 3500*time.Millisecond)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, "POST", upstream, bytes.NewReader(req))
	if err != nil {
		f.stats.Lock()
		f.stats.errors++
		f.stats.Unlock()
		return
	}
	httpReq.Header.Set("Content-Type", "application/dns-message")
	httpReq.Header.Set("Accept", "application/dns-message")

	resp, err := f.client.Do(httpReq)
	if err != nil {
		f.stats.Lock()
		f.stats.errors++
		f.stats.Unlock()
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		f.stats.Lock()
		f.stats.errors++
		f.stats.Unlock()
		return
	}

	rawResp, err := io.ReadAll(io.LimitReader(resp.Body, 65535))
	if err != nil || len(rawResp) < 12 {
		f.stats.Lock()
		f.stats.errors++
		f.stats.Unlock()
		return
	}

	binary.BigEndian.PutUint16(rawResp[0:2], queryID)
	_, _ = conn.WriteToUDP(rawResp, clientAddr)

	if cacheKey != "" {
		ttl := 60 * time.Second
		f.mu.Lock()
		f.cache[cacheKey] = CacheEntry{
			data:      rawResp,
			expiresAt: time.Now().Add(ttl),
		}
		if len(f.cache) > 2048 {
			for k := range f.cache {
				delete(f.cache, k)
				if len(f.cache) <= 1500 {
					break
				}
			}
		}
		f.mu.Unlock()
	}
}

func main() {
	listenFlag := flag.String("listen", "127.0.0.1:5354", "Listen UDP address")
	upstreamFlag := flag.String("upstream", "https://1.1.1.1/dns-query", "Upstream DoH URL")
	configFlag := flag.String("config", "", "Path to config file for dynamic upstream reload")
	testFlag := flag.String("test", "", "Test domain resolution via upstream DoH")
	flag.Parse()

	if *testFlag != "" {
		runDnsTest(*upstreamFlag, *testFlag)
		return
	}

	fwd := NewForwarder(*listenFlag, *upstreamFlag, *configFlag)
	fwd.reloadConfig()

	udpAddr, err := net.ResolveUDPAddr("udp", fwd.listenAddr)
	if err != nil {
		log.Fatalf("ResolveUDPAddr error: %v", err)
	}

	conn, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		log.Fatalf("ListenUDP error: %v", err)
	}
	defer conn.Close()

	log.Printf("[DoH Forwarder] Listening on %s, upstream %s", fwd.listenAddr, fwd.upstreamURL)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGHUP)
	go func() {
		for range sigChan {
			fwd.reloadConfig()
		}
	}()

	buf := make([]byte, 4096)
	for {
		n, clientAddr, err := conn.ReadFromUDP(buf)
		if err != nil {
			if strings.Contains(err.Error(), "closed") {
				break
			}
			continue
		}
		reqCopy := make([]byte, n)
		copy(reqCopy, buf[:n])
		go fwd.handlePacket(conn, clientAddr, reqCopy)
	}
}
