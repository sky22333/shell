package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	ExpireDate = "2055-12-30 23:59:59"
)

var (
	// 颜色代码
	Red         = "\033[31m"
	Green       = "\033[32m"
	Yellow      = "\033[33m"
	Blue        = "\033[34m"
	Nc          = "\033[0m"
	RedGloba    = "\033[41;37m"
	GreenGloba  = "\033[42;37m"
	YellowGloba = "\033[43;37m"
	BlueGloba   = "\033[44;37m"

	// 日志前缀
	Info  = fmt.Sprintf("%s[信息]%s", Green, Nc)
	Error = fmt.Sprintf("%s[错误]%s", Red, Nc)
	Tip   = fmt.Sprintf("%s[提示]%s", Yellow, Nc)

	reader = bufio.NewReader(os.Stdin)
)

func printColor(color, text string) {
	fmt.Printf("%s%s%s\n", color, text, Nc)
}

// runCommand 执行 Shell 命令
func runCommand(name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("命令执行超时: %s %v", name, args)
		}
		return fmt.Errorf("命令执行失败: %v", err)
	}
	return nil
}

// runCommandOutput 执行命令并获取输出
func runCommandOutput(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return "", fmt.Errorf("命令执行超时")
		}
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func fileExists(filename string) bool {
	info, err := os.Stat(filename)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir()
}

func dirExists(dirname string) bool {
	info, err := os.Stat(dirname)
	if os.IsNotExist(err) {
		return false
	}
	return info.IsDir()
}

func readInput(prompt string, defaultValue string) string {
	if defaultValue != "" {
		fmt.Printf("%s: ", prompt)
	} else {
		fmt.Printf("%s: ", prompt)
	}
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)
	if input == "" {
		return defaultValue
	}
	return input
}

func askYesNo(prompt string) bool {
	for {
		fmt.Printf("%s [y/N]: ", prompt)
		input, _ := reader.ReadString('\n')
		input = strings.TrimSpace(strings.ToLower(input))
		if input == "y" || input == "yes" {
			return true
		}
		if input == "n" || input == "no" || input == "" {
			return false
		}
	}
}

// 随机字符串生成
func randString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[time.Now().UnixNano()%int64(len(charset))]
	}
	return string(b)
}

// updateConfigFile 更新或追加配置
func updateConfigFile(filePath string, configs map[string]string, separator string) error {
	content, err := os.ReadFile(filePath)
	if err != nil && !os.IsNotExist(err) {
		return err
	}

	lines := strings.Split(string(content), "\n")
	newLines := make([]string, 0, len(lines)+len(configs))
	processedKeys := make(map[string]bool)

	for _, line := range lines {
		trimmedLine := strings.TrimSpace(line)
		updated := false
		for key, value := range configs {
			if strings.HasPrefix(trimmedLine, "#") {
				continue
			}

			// 匹配 key
			cleanLine := strings.ReplaceAll(trimmedLine, " ", "")
			cleanKey := strings.ReplaceAll(key, " ", "")

			if strings.HasPrefix(cleanLine, cleanKey+strings.TrimSpace(separator)) {
				newLines = append(newLines, key+separator+value)
				processedKeys[key] = true
				updated = true
				break
			}
		}
		if !updated {
			newLines = append(newLines, line)
		}
	}

	// 追加新配置
	for key, value := range configs {
		if !processedKeys[key] {
			newLines = append(newLines, key+separator+value)
		}
	}

	// 移除末尾可能的空行并重新组合
	output := strings.Join(newLines, "\n")
	// 确保文件末尾有换行
	if !strings.HasSuffix(output, "\n") {
		output += "\n"
	}

	return os.WriteFile(filePath, []byte(output), 0644)
}

func checkExpiration() error {
	urls := []string{
		"https://www.cloudflare.com/cdn-cgi/trace",
		"https://www.visa.cn/cdn-cgi/trace",
	}

	beijingLocation := time.FixedZone("Asia/Shanghai", 8*3600)
	pattern := regexp.MustCompile(`ts=(\d+)`)

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	var beijingTime time.Time
	success := false

	for _, url := range urls {
		resp, err := client.Get(url)
		if err != nil {
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode != 200 {
			continue
		}

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			continue
		}

		match := pattern.FindStringSubmatch(string(body))
		if len(match) < 2 {
			continue
		}

		timestamp, err := strconv.ParseInt(match[1], 10, 64)
		if err != nil {
			continue
		}

		utcTime := time.Unix(timestamp, 0).UTC()
		beijingTime = utcTime.In(beijingLocation)
		success = true
		break
	}

	if !success {
		return fmt.Errorf("无法验证有效期")
	}

	expireTime, err := time.ParseInLocation("2006-01-02 15:04:05", ExpireDate, beijingLocation)
	if err != nil {
		return fmt.Errorf("解析时间失败: %v", err)
	}

	if beijingTime.After(expireTime) {
		return fmt.Errorf("当前脚本已过期，请联系管理员获取更新")
	}

	return nil
}

func detectRegion() bool {
	fmt.Printf("%s 检测网络位置...\n", Blue)
	urls := []string{
		"https://www.cloudflare.com/cdn-cgi/trace",
		"https://www.visa.cn/cdn-cgi/trace",
	}
	client := &http.Client{Timeout: 5 * time.Second}

	for _, url := range urls {
		resp, err := client.Get(url)
		if err != nil {
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if strings.Contains(string(body), "loc=CN") {
			fmt.Printf("%s CN 网络环境\n", Green)
			return true
		}
	}
	fmt.Printf("%s 非 CN 网络环境\n", Green)
	return false
}

func changeMirrors() {
	fmt.Printf("%s [0/5] 配置软件源\n", Yellow)
	isCN := detectRegion()

	var cmdStr string
	if isCN {
		fmt.Println("使用阿里源...")
		cmdStr = `bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh) --source mirrors.aliyun.com --protocol http --use-intranet-source false --install-epel true --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --pure-mode`
	} else {
		fmt.Println("使用官方源...")
		cmdStr = `bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh) --use-official-source true --protocol http --use-intranet-source false --install-epel true --backup true --upgrade-software false --clean-cache false --ignore-backup-tips --pure-mode`
	}

	cmd := exec.Command("bash", "-c", cmdStr)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Printf("%s 警告：软件源切换失败，继续使用当前源\n", Yellow)
	} else {
		exec.Command("apt", "update", "-qq").Run()
	}
}

func checkCloudKernel() (bool, []string) {
	out, _ := runCommandOutput("uname", "-r")
	isCloud := strings.Contains(out, "cloud")

	dpkgOut, _ := runCommandOutput("bash", "-c", "dpkg -l | awk '/linux-(image|headers)-[0-9].*cloud/ {print $2}'")
	pkgs := strings.Fields(dpkgOut)

	return isCloud, pkgs
}

func installStandardKernel() error {
	fmt.Printf("%s [1/5] 安装标准内核\n", Yellow)

	imagePkg := "linux-image-amd64"
	headersPkg := "linux-headers-amd64"

	if releaseOut, _ := os.ReadFile("/etc/os-release"); strings.Contains(string(releaseOut), "Ubuntu") {
		imagePkg = "linux-image-generic"
		headersPkg = "linux-headers-generic"
	}

	fmt.Printf("正在安装 %s %s ...\n", imagePkg, headersPkg)

	cmd := exec.Command("apt", "install", "-y", "--reinstall", imagePkg, headersPkg)
	cmd.Env = append(os.Environ(), "DEBIAN_FRONTEND=noninteractive")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("标准内核安装失败")
	}

	// 更新 initramfs
	cmdStr := `ls /boot/vmlinuz-* 2>/dev/null | grep -v cloud | sort -V | tail -1 | sed 's|/boot/vmlinuz-||'`
	stdKernel, _ := runCommandOutput("bash", "-c", cmdStr)
	if stdKernel != "" {
		fmt.Printf("更新 initramfs: %s\n", stdKernel)
		runCommand("update-initramfs", "-u", "-k", stdKernel)
	}

	fmt.Printf("%s ✓ 标准内核安装完成: %s\n", Green, stdKernel)
	return nil
}

func removeCloudKernels(pkgs []string) {
	fmt.Printf("%s [2/5] 卸载所有 Cloud 内核\n", Yellow)
	if len(pkgs) == 0 {
		fmt.Printf("%s 未找到 Cloud 内核包\n", Yellow)
		return
	}

	fmt.Println("正在卸载以下包:", pkgs)

	// unhold
	args := append([]string{"unhold"}, pkgs...)
	exec.Command("apt-mark", args...).Run()

	// purge
	purgeArgs := append([]string{"purge", "-y"}, pkgs...)
	cmd := exec.Command("apt", purgeArgs...)
	cmd.Env = append(os.Environ(), "DEBIAN_FRONTEND=noninteractive")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	exec.Command("apt", "autoremove", "-y", "--purge").Run()
	fmt.Printf("%s ✓ Cloud 内核清理流程结束\n", Green)
}

func updateGrub() {
	fmt.Printf("%s [3/5] 配置 GRUB\n", Yellow)

	grubConfig := `GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=$(lsb_release -i -s 2> /dev/null || echo Debian)
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
`
	// 备份：仅当目录为空时备份
	backupDir := "/root/grub_backup"
	os.MkdirAll(backupDir, 0755)
	
	files, _ := os.ReadDir(backupDir)
	if len(files) == 0 {
		runCommand("cp", "/etc/default/grub", fmt.Sprintf("%s/grub.default.bak", backupDir))
	}

	distributor := "Debian"
	if out, err := runCommandOutput("lsb_release", "-i", "-s"); err == nil {
		distributor = out
	}

	finalGrubConfig := strings.Replace(grubConfig, "$(lsb_release -i -s 2> /dev/null || echo Debian)", distributor, 1)

	os.WriteFile("/etc/default/grub", []byte(finalGrubConfig), 0644)

	fmt.Println("重新生成 GRUB 配置...")
	runCommand("update-grub")
	runCommand("grub-set-default", "0")

	if dirExists("/sys/firmware/efi") {
		fmt.Println("更新 UEFI 引导...")
		runCommand("grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi", "--bootloader-id=debian", "--recheck")
	}

	fmt.Printf("%s ✓ GRUB 更新完成\n", Green)
}

func performKernelSwap() {
	osInfo := getOSInfo()
	if osInfo.ID != "debian" && osInfo.ID != "ubuntu" && osInfo.ID != "kali" {
		fmt.Printf("%s 错误: 内核切换功能仅支持 Debian/Ubuntu 系统 (当前检测为: %s)\n", Error, osInfo.ID)
		return
	}

	fmt.Printf("\n%s⚠️  高危操作警告 ⚠️%s\n", Red, Nc)
	fmt.Println("更换内核有可能会失败导致系统无法启动，请务必提前备份重要数据")
	if !askYesNo("确认继续？") {
		fmt.Println("操作已取消")
		return
	}

	// 确保基础工具存在
	runCommand("apt-get", "update", "-qq")
	runCommand("apt-get", "install", "-y", "-qq", "curl", "ca-certificates")

	changeMirrors()
	if err := installStandardKernel(); err != nil {
		fmt.Println(Error, err)
		return
	}

	_, pkgs := checkCloudKernel()
	removeCloudKernels(pkgs)

	updateGrub()

	fmt.Printf("\n%s内核切换操作完成！需要重启生效。%s\n", Green, Nc)
	if askYesNo("立即重启？") {
		runCommand("reboot")
	} else {
		fmt.Println("请稍后手动重启。")
	}
	os.Exit(0)
}

// OSInfo 系统信息
type OSInfo struct {
	ID        string
	VersionID string
}

func getOSInfo() OSInfo {
	content, err := os.ReadFile("/etc/os-release")
	if err != nil {
		// 尝试 /usr/lib/os-release
		content, _ = os.ReadFile("/usr/lib/os-release")
	}

	info := OSInfo{}
	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "ID=") {
			info.ID = strings.Trim(strings.TrimPrefix(line, "ID="), "\"")
		}
		if strings.HasPrefix(line, "VERSION_ID=") {
			info.VersionID = strings.Trim(strings.TrimPrefix(line, "VERSION_ID="), "\"")
		}
	}
	return info
}

func installDependencies(osInfo OSInfo) {
	fmt.Printf("%s 正在检查并安装依赖...%s\n", Tip, Nc)

	var updateCmd, installCmd string
	apps := []string{"curl", "xl2tpd", "strongswan", "pptpd", "nftables"}

	switch osInfo.ID {
	case "debian", "ubuntu", "kali":
		updateCmd = "apt update -y -q"
		installCmd = "apt install -y -q"
	case "alpine":
		updateCmd = "apk update -f -q"
		installCmd = "apk add -f -q"
	case "centos", "almalinux", "rocky", "oracle", "fedora":
		updateCmd = "dnf update -y -q"
		installCmd = "dnf install -y -q"
		if osInfo.ID == "centos" {
			updateCmd = "yum update -y -q"
			installCmd = "yum install -y -q"
		}
	default:
		fmt.Printf("%s 不支持的操作系统: %s\n", Error, osInfo.ID)
		os.Exit(1)
	}

	// 执行更新
	if err := runCommand("bash", "-c", updateCmd); err != nil {
		fmt.Printf("%s 警告: 系统更新失败，尝试继续安装...\n", Tip)
	}

	// 安装软件包
	fullInstallCmd := fmt.Sprintf("%s %s ppp", installCmd, strings.Join(apps, " "))

	fmt.Printf("%s 正在安装依赖...\n", Tip)
	if err := runCommand("bash", "-c", fullInstallCmd); err != nil {
		fmt.Printf("%s 错误: 依赖安装失败，脚本退出。\n", Error)
		os.Exit(1)
	}
}

// getPublicIP 并发获取公网IP
func getPublicIP() string {
	apis := []string{
		"http://api64.ipify.org",
		"http://4.ipw.cn",
		"http://ip.sb",
		"http://checkip.amazonaws.com",
		"http://icanhazip.com",
		"http://ipinfo.io/ip",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resultChan := make(chan string, 1)
	var wg sync.WaitGroup

	for _, url := range apis {
		wg.Add(1)
		go func(apiURL string) {
			defer wg.Done()
			
			req, err := http.NewRequestWithContext(ctx, "GET", apiURL, nil)
			if err != nil {
				return
			}

			client := &http.Client{}
			resp, err := client.Do(req)
			if err == nil {
				defer resp.Body.Close()
				body, _ := io.ReadAll(resp.Body)
				ip := strings.TrimSpace(string(body))
				
				if ip != "" && !strings.Contains(ip, "<") {
					select {
					case resultChan <- ip:
						cancel()
					default:
					}
				}
			}
		}(url)
	}

	go func() {
		wg.Wait()
		close(resultChan)
	}()

	select {
	case ip := <-resultChan:
		if ip != "" {
			return ip
		}
	case <-ctx.Done():
	}

	return "127.0.0.1"
}

func setupSysctl() {
	configs := map[string]string{
		"net.ipv4.ip_forward":                  "1",
		"net.ipv4.conf.all.send_redirects":     "0",
		"net.ipv4.conf.default.send_redirects": "0",
		"net.ipv4.conf.all.accept_redirects":   "0",
		"net.ipv4.conf.default.accept_redirects": "0",
	}

	fmt.Println(Tip, "正在配置 Sysctl 参数...")
	if err := updateConfigFile("/etc/sysctl.conf", configs, " = "); err != nil {
		fmt.Printf("%s 警告: 更新 sysctl.conf 失败: %v\n", Tip, err)
	}

	runCommand("sysctl", "-p")
}

func setupNftables(l2tpPort, pptpPort, l2tpLocIP, pptpLocIP string) {
	// 备份
	if fileExists("/etc/nftables.conf") && !fileExists("/etc/nftables.conf.bak") {
		runCommand("cp", "/etc/nftables.conf", "/etc/nftables.conf.bak")
	}

	interfaceName := "eth0"
	// 获取默认网卡
	out, err := runCommandOutput("bash", "-c", "ip route get 8.8.8.8 | awk '{print $5; exit}'")
	if err == nil && out != "" {
		interfaceName = out
	}

	config := fmt.Sprintf(`#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        ct state established,related accept
        ip protocol icmp accept
        iif lo accept
        udp dport {500,4500,%s,%s} accept
        accept
    }
    chain forward {
        type filter hook forward priority 0;
        ct state established,related accept
        ip saddr %s.0/24 accept
        ip saddr %s.0/24 accept
        accept
    }
    chain output {
        type filter hook output priority 0;
        accept
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority 0;
        accept
    }
    chain postrouting {
        type nat hook postrouting priority 100;
        oif "%s" masquerade
    }
    chain output {
        type nat hook output priority 0;
        accept
    }
}
`, l2tpPort, pptpPort, l2tpLocIP, pptpLocIP, interfaceName)

	os.WriteFile("/etc/nftables.conf", []byte(config), 0755)
	runCommand("systemctl", "daemon-reload")
	runCommand("systemctl", "enable", "nftables")
	runCommand("systemctl", "restart", "nftables")
}

func installVPN() string {
	publicIP := getPublicIP()

	fmt.Println()
	// L2TP 配置
	fmt.Println(Tip, "请输入 L2TP IP范围:")
	l2tpLocIP := readInput("(默认范围: 10.10.10)", "10.10.10")

	fmt.Println(Tip, "请输入 L2TP 端口:")
	l2tpPort := readInput("(默认端口: 1701)", "1701")

	l2tpUser := randString(5)
	fmt.Printf("%s 请输入 L2TP 用户名:\n", Tip)
	l2tpUser = readInput(fmt.Sprintf("(默认用户名: %s)", l2tpUser), l2tpUser)

	l2tpPass := randString(7)
	fmt.Printf("%s 请输入 %s 的密码:\n", Tip, l2tpUser)
	l2tpPass = readInput(fmt.Sprintf("(默认密码: %s)", l2tpPass), l2tpPass)

	l2tpPSK := randString(20)
	fmt.Printf("%s 请输入 L2TP PSK 密钥:\n", Tip)
	l2tpPSK = readInput(fmt.Sprintf("(默认PSK: %s)", l2tpPSK), l2tpPSK)

	// PPTP 配置
	fmt.Println(Tip, "请输入 PPTP IP范围:")
	pptpLocIP := readInput("(默认范围: 192.168.30)", "192.168.30")

	fmt.Println(Tip, "请输入 PPTP 端口:")
	pptpPort := readInput("(默认端口: 1723)", "1723")

	pptpUser := randString(5)
	fmt.Printf("%s 请输入 PPTP 用户名:\n", Tip)
	pptpUser = readInput(fmt.Sprintf("(默认用户名: %s)", pptpUser), pptpUser)

	pptpPass := randString(7)
	fmt.Printf("%s 请输入 %s 的密码:\n", Tip, pptpUser)
	pptpPass = readInput(fmt.Sprintf("(默认密码: %s)", pptpPass), pptpPass)

	// 展示配置信息
	fmt.Println()
	fmt.Printf("%s L2TP服务器本地IP: %s%s.1%s\n", Info, Green, l2tpLocIP, Nc)
	fmt.Printf("%s L2TP客户端IP范围: %s%s.11-%s.255%s\n", Info, Green, l2tpLocIP, l2tpLocIP, Nc)
	fmt.Printf("%s L2TP端口    : %s%s%s\n", Info, Green, l2tpPort, Nc)
	fmt.Printf("%s L2TP用户名  : %s%s%s\n", Info, Green, l2tpUser, Nc)
	fmt.Printf("%s L2TP密码    : %s%s%s\n", Info, Green, l2tpPass, Nc)
	fmt.Printf("%s L2TPPSK密钥 : %s%s%s\n", Info, Green, l2tpPSK, Nc)
	fmt.Println()
	fmt.Printf("%s PPTP服务器本地IP: %s%s.1%s\n", Info, Green, pptpLocIP, Nc)
	fmt.Printf("%s PPTP客户端IP范围: %s%s.11-%s.255%s\n", Info, Green, pptpLocIP, pptpLocIP, Nc)
	fmt.Printf("%s PPTP端口    : %s%s%s\n", Info, Green, pptpPort, Nc)
	fmt.Printf("%s PPTP用户名  : %s%s%s\n", Info, Green, pptpUser, Nc)
	fmt.Printf("%s PPTP密码    : %s%s%s\n", Info, Green, pptpPass, Nc)
	fmt.Println()

	fmt.Println("正在生成配置文件...")

	// /etc/ipsec.conf
	ipsecConf := fmt.Sprintf(`config setup
    charondebug="ike 2, knl 2, cfg 2"
    uniqueids=no

conn %%default
    keyexchange=ikev1
    authby=secret
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1,3des-sha1!
    keyingtries=3
    ikelifetime=8h
    lifetime=1h
    dpdaction=clear
    dpddelay=30s
    dpdtimeout=120s
    rekey=no
    forceencaps=yes
    fragmentation=yes

conn L2TP-PSK
    left=%%any
    leftid=%s
    leftfirewall=yes
    leftprotoport=17/%s
    right=%%any
    rightprotoport=17/%%any
    type=transport
    auto=add
    also=%%default
`, publicIP, l2tpPort)
	os.WriteFile("/etc/ipsec.conf", []byte(ipsecConf), 0644)

	// /etc/ipsec.secrets
	ipsecSecrets := fmt.Sprintf(`%%any %%any : PSK "%s"
`, l2tpPSK)
	os.WriteFile("/etc/ipsec.secrets", []byte(ipsecSecrets), 0600)

	// /etc/xl2tpd/xl2tpd.conf
	xl2tpdConf := fmt.Sprintf(`[global]
port = %s

[lns default]
ip range = %s.11-%s.255
local ip = %s.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
`, l2tpPort, l2tpLocIP, l2tpLocIP, l2tpLocIP)
	os.MkdirAll("/etc/xl2tpd", 0755)
	os.WriteFile("/etc/xl2tpd/xl2tpd.conf", []byte(xl2tpdConf), 0644)

	// /etc/ppp/options.xl2tpd
	pppOptXl2tpd := `ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
noccp
auth
hide-password
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
`
	os.MkdirAll("/etc/ppp", 0755)
	os.WriteFile("/etc/ppp/options.xl2tpd", []byte(pppOptXl2tpd), 0644)

	// /etc/pptpd.conf
	pptpdConf := fmt.Sprintf(`option /etc/ppp/pptpd-options
debug
localip %s.1
remoteip %s.11-255
`, pptpLocIP, pptpLocIP)
	os.WriteFile("/etc/pptpd.conf", []byte(pptpdConf), 0644)

	// /etc/ppp/pptpd-options
	pptpdOptions := `name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
`
	os.WriteFile("/etc/ppp/pptpd-options", []byte(pptpdOptions), 0644)

	// /etc/ppp/chap-secrets
	chapSecrets := "# Secrets for authentication using CHAP\n# client    server    secret    IP addresses\n"

	// 1. 添加主用户 (静态 IP .10)
	chapSecrets += fmt.Sprintf("%s    l2tpd    %s    %s.10\n", l2tpUser, l2tpPass, l2tpLocIP)
	chapSecrets += fmt.Sprintf("%s    pptpd    %s    %s.10\n", pptpUser, pptpPass, pptpLocIP)

	// 2. 批量生成用户 (IP 11-255)
	for i := 11; i <= 255; i++ {
		chapSecrets += fmt.Sprintf("%s%d    l2tpd    %s%d    %s.%d\n", l2tpUser, i, l2tpPass, i, l2tpLocIP, i)
		chapSecrets += fmt.Sprintf("%s%d    pptpd    %s%d    %s.%d\n", pptpUser, i, pptpPass, i, pptpLocIP, i)
	}

	os.WriteFile("/etc/ppp/chap-secrets", []byte(chapSecrets), 0600)

	// 设置系统和防火墙
	setupSysctl()
	setupNftables(l2tpPort, pptpPort, l2tpLocIP, pptpLocIP)

	// 启动服务
	fmt.Println("正在启动服务...")
	services := []string{"ipsec", "xl2tpd", "pptpd"}
	
	// 检查 ipsec 服务名
	if _, err := runCommandOutput("systemctl", "list-unit-files", "strongswan.service"); err == nil {
		if _, err := runCommandOutput("systemctl", "list-unit-files", "ipsec.service"); err != nil {
			services[0] = "strongswan"
		}
	}
	runCommand("systemctl", "daemon-reload")
	
	if err := os.WriteFile("/proc/sys/net/ipv4/ip_forward", []byte("1\n"), 0644); err != nil {
		fmt.Printf("%s 警告: 无法写入 ip_forward: %v\n", Tip, err)
	}

	for _, svc := range services {
		runCommand("systemctl", "enable", svc)
		runCommand("systemctl", "restart", svc)
	}

	fmt.Println()
	fmt.Printf("%s===============================================%s\n", Green, Nc)
	fmt.Printf("%sVPN 安装完成%s\n", Green, Nc)
	fmt.Printf("%s===============================================%s\n", Green, Nc)
	fmt.Printf("请保留好以下信息:\n")
	fmt.Printf("服务器IP: %s\n", publicIP)
	fmt.Printf("L2TP PSK: %s\n", l2tpPSK)
	fmt.Printf("L2TP 主账号: %s / 密码: %s\n", l2tpUser, l2tpPass)
	fmt.Printf("PPTP 主账号: %s / 密码: %s\n", pptpUser, pptpPass)
	fmt.Printf("\n%s 已自动生成批量账号，详情请查看 /etc/ppp/chap-secrets 文件%s\n", Tip, Nc)
	return l2tpLocIP
}

func configureSingboxFirewall(l2tpLocIP string, port string) {
	fmt.Printf("%s 配置透明代理分流规则 (端口: %s)...\n", Tip, port)

	// 1. 配置策略路由
	runCommand("/bin/ip", "rule", "add", "fwmark", "1", "table", "100")
	runCommand("/bin/ip", "route", "add", "local", "0.0.0.0/0", "dev", "lo", "table", "100")

	// 2. 新建 SINGBOX 链
	runCommand("iptables", "-t", "mangle", "-N", "SINGBOX")

	// 3. 绕过局域网和私有地址
	privateIPs := []string{
		"0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16",
		"172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "240.0.0.0/4",
	}
	for _, ip := range privateIPs {
		runCommand("iptables", "-t", "mangle", "-A", "SINGBOX", "-d", ip, "-j", "RETURN")
	}

	// 4. 配置拦截规则
	l2tpSubnet := fmt.Sprintf("%s.0/24", l2tpLocIP)
	runCommand("iptables", "-t", "mangle", "-A", "SINGBOX", "-s", l2tpSubnet, "-p", "tcp", "-j", "TPROXY", "--on-port", port, "--tproxy-mark", "1")
	runCommand("iptables", "-t", "mangle", "-A", "SINGBOX", "-s", l2tpSubnet, "-p", "udp", "-j", "TPROXY", "--on-port", port, "--tproxy-mark", "1")

	// 5. 应用到 PREROUTING 链
	runCommand("iptables", "-t", "mangle", "-A", "PREROUTING", "-j", "SINGBOX")

	// 6. 禁止公网访问透明代理端口
	runCommand("iptables", "-I", "INPUT", "-p", "tcp", "--dport", port, "-j", "DROP")
	runCommand("iptables", "-I", "INPUT", "-p", "udp", "--dport", port, "-j", "DROP")

	fmt.Printf("%s 透明代理分流规则配置完成\n", Green)
}

func uninstallService(port string) {
	fmt.Printf("%s 正在卸载服务...\n", Tip)

	// 停止服务
	exec.Command("bash", "-c", "systemctl stop xl2tpd strongswan-starter strongswan pptpd 2>/dev/null || true").Run()

	// 禁用服务
	exec.Command("bash", "-c", "systemctl disable xl2tpd strongswan-starter strongswan pptpd 2>/dev/null || true").Run()

	// 卸载软件
	cmd := exec.Command("apt", "purge", "-y", "xl2tpd", "strongswan", "pptpd")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	// 清理防火墙规则
	exec.Command("iptables", "-t", "mangle", "-D", "PREROUTING", "-j", "SINGBOX").Run()
	exec.Command("iptables", "-t", "mangle", "-F", "SINGBOX").Run()
	exec.Command("iptables", "-t", "mangle", "-X", "SINGBOX").Run()

	// 清理路由表
	exec.Command("/bin/ip", "route", "del", "local", "0.0.0.0/0", "dev", "lo", "table", "100").Run()
	exec.Command("/bin/ip", "rule", "del", "fwmark", "1", "table", "100").Run()

	// 放行端口
	exec.Command("iptables", "-D", "INPUT", "-p", "tcp", "--dport", port, "-j", "DROP").Run()
	exec.Command("iptables", "-D", "INPUT", "-p", "udp", "--dport", port, "-j", "DROP").Run()

	fmt.Printf("%s 卸载完成\n", Green)
}

func main() {
	outFlag := flag.Bool("out", false, "安装完成后自动配置分流规则")
	rmFlag := flag.Bool("rm", false, "卸载服务并清理规则")
	flag.Parse()

	// 1. 检查 Root
	if os.Geteuid() != 0 {
		fmt.Printf("%s 错误: 必须使用 root 权限运行此脚本\n", Error)
		os.Exit(1)
	}

	if *rmFlag {
		fmt.Println(Tip, "请输入配置时使用的透明代理分流端口:")
		port := readInput("(默认: 12345)", "12345")
		uninstallService(port)
		return
	}

	// 清屏
	if runtime.GOOS == "linux" {
		fmt.Print("\033[H\033[2J")
	}

	fmt.Printf("%s###############################################################%s\n", Green, Nc)
	fmt.Printf("%s# L2TP/IPSec & PPTP VPN 一键安装脚本                        #%s\n", Green, Nc)
	fmt.Printf("%s###############################################################%s\n", Green, Nc)
	fmt.Println()

	// 2. 时间过期检查
	if err := checkExpiration(); err != nil {
		fmt.Printf("%s %v\n", Error, err)
		os.Exit(1)
	}

	// 3. 检查 OpenVZ
	if dirExists("/proc/vz") {
		fmt.Printf("%s 警告: 你的VPS基于OpenVZ，内核可能不支持IPSec。L2TP安装已取消。\n", Error)
		os.Exit(1)
	}

	// 4. 检查 PPP 支持与内核切换逻辑
	if !fileExists("/dev/ppp") {
		fmt.Printf("%s 警告: 未检测到 /dev/ppp 设备，当前内核可能不支持 PPP。\n", Error)
		uname, _ := runCommandOutput("uname", "-r")
		fmt.Printf("%s 当前内核版本: %s\n", Tip, uname)

		if askYesNo("是否尝试切换到标准内核 (将卸载Cloud内核并重置GRUB)?") {
			performKernelSwap()
		} else {
			fmt.Printf("%s 用户取消操作，无法继续安装 VPN。\n", Error)
			os.Exit(1)
		}
	} else {
		isCloud, _ := checkCloudKernel()
		if isCloud {
			fmt.Printf("%s 提示: 检测到当前运行在 Cloud 内核上，但 /dev/ppp 存在，可以继续。\n", Tip)
			fmt.Printf("如果安装后无法连接，建议重新运行脚本并选择切换内核。\n")
		}
	}

	// 5. 安装 VPN
	osInfo := getOSInfo()
	installDependencies(osInfo)
	l2tpLocIP := installVPN()

	if *outFlag {
		fmt.Println(Tip, "请输入透明代理分流端口:")
		port := readInput("(默认: 12345)", "12345")
		configureSingboxFirewall(l2tpLocIP, port)
	}
}
