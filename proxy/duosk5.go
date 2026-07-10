package main

import (
	"bufio"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// 颜色常量（ANSI转义码）
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorCyan   = "\033[36m"

	// 构建：CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o sk5 main.go
	// 脚本过期时间以及其他变量
	EXPIRE_DATE      = "2025-06-08 02:01:01"
	CONFIG_FILE      = "/usr/local/etc/xray/config.json"
	SOCKS_FILE       = "/home/socks.txt"
	XRAY_INSTALL_URL = "https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
	XRAY_VERSION     = "v1.8.4"
	START_PORT       = 10001
)

// 彩色打印函数
func colorPrint(colorCode, format string, a ...interface{}) {
	fmt.Printf(colorCode+format+ColorReset+"\n", a...)
}

// XrayConfig represents the Xray configuration structure
type XrayConfig struct {
	Inbounds  []Inbound  `json:"inbounds"`
	Outbounds []Outbound `json:"outbounds"`
	Routing   Routing    `json:"routing"`
}

type Inbound struct {
	Port           int             `json:"port"`
	Protocol       string          `json:"protocol"`
	Settings       InboundSettings `json:"settings"`
	StreamSettings StreamSettings  `json:"streamSettings"`
	Tag            string          `json:"tag"`
}

type InboundSettings struct {
	Auth     string    `json:"auth"`
	Accounts []Account `json:"accounts"`
	UDP      bool      `json:"udp"`
	IP       string    `json:"ip"`
}

type Account struct {
	User string `json:"user"`
	Pass string `json:"pass"`
}

type StreamSettings struct {
	Network string `json:"network"`
}

type Outbound struct {
	Protocol    string      `json:"protocol"`
	Settings    interface{} `json:"settings"`
	SendThrough string      `json:"sendThrough"`
	Tag         string      `json:"tag"`
}

type Routing struct {
	Rules []Rule `json:"rules"`
}

type Rule struct {
	Type        string   `json:"type"`
	InboundTag  []string `json:"inboundTag"`
	OutboundTag string   `json:"outboundTag"`
}

type NodeInfo struct {
	IP       string
	Port     int
	Username string
	Password string
}

// generateRandomString generates a random string of specified length
func generateRandomString(length int) string {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	for i := range b {
		b[i] = charset[b[i]%byte(len(charset))]
	}
	return string(b)
}

// checkExpiration checks if the script has expired
func checkExpiration() error {
	colorPrint(ColorCyan, "开始运行...")

	// Get timestamp from cloudflare
	resp, err := http.Get("https://www.cloudflare.com/cdn-cgi/trace")
	if err != nil {
		return fmt.Errorf("网络错误")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取响应失败")
	}

	// Extract timestamp
	re := regexp.MustCompile(`ts=(\d+)`)
	matches := re.FindStringSubmatch(string(body))
	if len(matches) < 2 {
		return fmt.Errorf("无法解析时间")
	}

	timestamp, err := strconv.ParseInt(matches[1], 10, 64)
	if err != nil {
		return fmt.Errorf("时间转换失败")
	}

	// Convert to Beijing time
	currentTime := time.Unix(timestamp, 0).In(time.FixedZone("CST", 8*3600))
	expireTime, _ := time.ParseInLocation("2006-01-02 15:04:05", EXPIRE_DATE, time.FixedZone("CST", 8*3600))

	if currentTime.After(expireTime) {
		return fmt.Errorf("当前脚本已过期，请联系作者")
	}

	return nil
}

// commandExists checks if a command exists in PATH
func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

// installJQ installs jq if not present
func installJQ() error {
	if commandExists("jq") {
		colorPrint(ColorGreen, "jq 已安装")
		return nil
	}

	colorPrint(ColorYellow, "jq 未安装，正在安装 jq...")

	// Detect OS
	if _, err := os.Stat("/etc/debian_version"); err == nil {
		// Debian/Ubuntu
		cmd := exec.Command("bash", "-c", "apt update && apt install -yq jq")
		return cmd.Run()
	} else if _, err := os.Stat("/etc/redhat-release"); err == nil {
		// RHEL/CentOS
		cmd := exec.Command("yum", "install", "-y", "epel-release", "jq")
		return cmd.Run()
	}

	return fmt.Errorf("无法确定系统发行版，请手动安装 jq")
}

// installXray installs Xray if not present
func installXray() error {
	if commandExists("xray") {
		colorPrint(ColorGreen, "Xray 已安装")
		return nil
	}

	colorPrint(ColorYellow, "Xray 未安装，正在安装 Xray...")

	cmd := exec.Command("bash", "-c", fmt.Sprintf("curl -L %s | bash -s install --version %s", XRAY_INSTALL_URL, XRAY_VERSION))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Xray 安装失败: %v", err)
	}

	colorPrint(ColorGreen, "Xray 安装完成")
	return nil
}

// getPublicIPv4 gets all public IPv4 addresses
func getPublicIPv4() ([]string, error) {
	var publicIPs []string

	// Get all network interfaces
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			if ipNet, ok := addr.(*net.IPNet); ok && !ipNet.IP.IsLoopback() {
				if ipNet.IP.To4() != nil {
					ip := ipNet.IP.String()
					// Check if it's a public IP
					if isPublicIP(ip) {
						publicIPs = append(publicIPs, ip)
					}
				}
			}
		}
	}

	return publicIPs, nil
}

// isPublicIP checks if an IP is public
func isPublicIP(ip string) bool {
	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		return false
	}

	// Check for private IP ranges
	privateRanges := []string{
		"127.0.0.0/8",    // loopback
		"10.0.0.0/8",     // private
		"172.16.0.0/12",  // private
		"192.168.0.0/16", // private
		"169.254.0.0/16", // link-local
	}

	for _, cidr := range privateRanges {
		_, network, _ := net.ParseCIDR(cidr)
		if network.Contains(parsedIP) {
			return false
		}
	}

	return true
}

// ensureSocksFileExists creates socks.txt if it doesn't exist
func ensureSocksFileExists() error {
	if _, err := os.Stat(SOCKS_FILE); os.IsNotExist(err) {
		colorPrint(ColorYellow, "socks.txt 文件不存在，正在创建...")
		file, err := os.Create(SOCKS_FILE)
		if err != nil {
			return err
		}
		file.Close()
	}
	return nil
}

// saveNodeInfo saves node information to file and prints it
func saveNodeInfo(node NodeInfo) error {
	// Print node info with colors
	fmt.Printf(" IP: %s%s%s 端口: %s%d%s 用户名: %s%s%s 密码: %s%s%s\n",
		ColorGreen, node.IP, ColorReset,
		ColorGreen, node.Port, ColorReset,
		ColorGreen, node.Username, ColorReset,
		ColorGreen, node.Password, ColorReset)

	// Save to file
	file, err := os.OpenFile(SOCKS_FILE, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = fmt.Fprintf(file, "%s %d %s %s\n", node.IP, node.Port, node.Username, node.Password)
	return err
}

// configureXray configures Xray with multiple IPs
func configureXray() error {
	publicIPs, err := getPublicIPv4()
	if err != nil {
		return fmt.Errorf("获取公网IP失败: %v", err)
	}

	if len(publicIPs) == 0 {
		return fmt.Errorf("未找到额外IP地址")
	}

	colorPrint(ColorCyan, "找到的公网 IPv4 地址: %v", publicIPs)

	// Create initial config
	config := XrayConfig{
		Inbounds:  []Inbound{},
		Outbounds: []Outbound{},
		Routing: Routing{
			Rules: []Rule{},
		},
	}

	// Configure each IP
	port := START_PORT
	for _, ip := range publicIPs {
		colorPrint(ColorCyan, "正在配置 IP: %s 端口: %d", ip, port)

		username := generateRandomString(8)
		password := generateRandomString(8)

		// Create inbound
		inbound := Inbound{
			Port:     port,
			Protocol: "socks",
			Settings: InboundSettings{
				Auth: "password",
				Accounts: []Account{
					{User: username, Pass: password},
				},
				UDP: true,
				IP:  "0.0.0.0",
			},
			StreamSettings: StreamSettings{
				Network: "tcp",
			},
			Tag: fmt.Sprintf("in-%d", port),
		}

		// Create outbound
		outbound := Outbound{
			Protocol:    "freedom",
			Settings:    map[string]interface{}{},
			SendThrough: ip,
			Tag:         fmt.Sprintf("out-%d", port),
		}

		// Create routing rule
		rule := Rule{
			Type:        "field",
			InboundTag:  []string{fmt.Sprintf("in-%d", port)},
			OutboundTag: fmt.Sprintf("out-%d", port),
		}

		config.Inbounds = append(config.Inbounds, inbound)
		config.Outbounds = append(config.Outbounds, outbound)
		config.Routing.Rules = append(config.Routing.Rules, rule)

		// Save node info
		node := NodeInfo{
			IP:       ip,
			Port:     port,
			Username: username,
			Password: password,
		}
		if err := saveNodeInfo(node); err != nil {
			return fmt.Errorf("保存节点信息失败: %v", err)
		}

		port++
	}

	// Write config file
	configData, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %v", err)
	}

	if err := os.WriteFile(CONFIG_FILE, configData, 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}

	colorPrint(ColorGreen, "Xray 配置完成")
	return nil
}

// restartXray restarts the Xray service
func restartXray() error {
	colorPrint(ColorCyan, "正在重启 Xray 服务...")

	// Restart service
	cmd := exec.Command("systemctl", "restart", "xray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("Xray 服务重启失败: %v", err)
	}

	// Enable service
	cmd = exec.Command("systemctl", "enable", "xray")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("启用 Xray 服务失败: %v", err)
	}

	colorPrint(ColorGreen, "Xray 服务已重启")
	return nil
}

// readUserInput reads user input for confirmation
func readUserInput(prompt string) string {
	fmt.Print(prompt)
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	return strings.TrimSpace(input)
}

func main() {
	colorPrint(ColorCyan, "站群多IP源进源出sk5协议一键脚本")
	colorPrint(ColorCyan, "当前为测试版，可以联系作者获取源码")
	expireTime, err := time.ParseInLocation("2006-01-02 15:04:05", EXPIRE_DATE, time.FixedZone("CST", 8*3600))
	if err == nil {
		expireStr := fmt.Sprintf("%d年%d月%d日%d点%d分%d秒",
			expireTime.Year(),
			expireTime.Month(),
			expireTime.Day(),
			expireTime.Hour(),
			expireTime.Minute(),
			expireTime.Second())
		colorPrint(ColorCyan, "脚本过期时间: %s", expireStr)
	} else {
		colorPrint(ColorYellow, "脚本过期时间解析失败")
	}
	fmt.Println()

	// Check expiration
	if err := checkExpiration(); err != nil {
		colorPrint(ColorRed, "错误: %v", err)
		os.Exit(1)
	}

	// Ensure socks file exists
	if err := ensureSocksFileExists(); err != nil {
		colorPrint(ColorRed, "创建socks文件失败: %v", err)
		os.Exit(1)
	}

	// Install jq
	if err := installJQ(); err != nil {
		colorPrint(ColorRed, "安装jq失败: %v", err)
		os.Exit(1)
	}

	// Install Xray
	if err := installXray(); err != nil {
		colorPrint(ColorRed, "安装Xray失败: %v", err)
		os.Exit(1)
	}

	// Configure Xray
	if err := configureXray(); err != nil {
		colorPrint(ColorRed, "配置Xray失败: %v", err)
		os.Exit(1)
	}

	// Restart Xray
	if err := restartXray(); err != nil {
		colorPrint(ColorRed, "重启Xray失败: %v", err)
		os.Exit(1)
	}

	colorPrint(ColorGreen, "部署完成，所有节点信息已保存到 %s", SOCKS_FILE)
}
