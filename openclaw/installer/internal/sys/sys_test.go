package sys

import (
	"bufio"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestCheckLocation(t *testing.T) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://www.cloudflare.com/cdn-cgi/trace")
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	var loc, ip string
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		parts := strings.SplitN(strings.TrimSpace(scanner.Text()), "=", 2)
		if len(parts) == 2 {
			switch parts[0] {
			case "ip":
				ip = parts[1]
			case "loc":
				loc = parts[1]
			}
		}
	}

	const cyan = "\033[1;36m"
	const reset = "\033[0m"

	fmt.Printf("\n%s"+
		"IP  : %s\n"+
		"LOC : %s\n"+
		"是否代理: %v\n"+
		"%s\n", cyan, ip, loc, loc == "CN", reset)
}
