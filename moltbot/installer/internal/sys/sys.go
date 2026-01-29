package sys

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	cachedNpmPrefix string
	cachedNodePath  string
	cachedGitPath   string
	prefixOnce      sync.Once
	nodePathOnce    sync.Once
	gitPathOnce     sync.Once
)

// MoltbotConfig 配置结构
type MoltbotConfig struct {
	Gateway  GatewayConfig     `json:"gateway"`
	Env      map[string]string `json:"env,omitempty"`
	Agents   AgentsConfig      `json:"agents"`
	Models   *ModelsConfig     `json:"models,omitempty"`
	Tools    ToolsConfig       `json:"tools"`
	Channels ChannelsConfig    `json:"channels"`
}

type GatewayConfig struct {
	Mode string `json:"mode"`
	Bind string `json:"bind"`
	Port int    `json:"port"`
}

type AgentsConfig struct {
	Defaults AgentDefaults `json:"defaults"`
}

type AgentDefaults struct {
	Model           ModelRef          `json:"model"`
	ElevatedDefault string            `json:"elevatedDefault,omitempty"`
	Compaction      *CompactionConfig `json:"compaction,omitempty"`
	MaxConcurrent   int               `json:"maxConcurrent,omitempty"`
}

type ModelRef struct {
	Primary string `json:"primary"`
}

type CompactionConfig struct {
	Mode string `json:"mode"`
}

type ModelsConfig struct {
	Mode      string                    `json:"mode"`
	Providers map[string]ProviderConfig `json:"providers"`
}

type ProviderConfig struct {
	BaseURL string       `json:"baseUrl"`
	APIKey  string       `json:"apiKey"`
	API     string       `json:"api"`
	Models  []ModelEntry `json:"models"`
}

type ModelEntry struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type ToolsConfig struct {
	Exec     *ExecConfig    `json:"exec,omitempty"`
	Elevated ElevatedConfig `json:"elevated"`
	Allow    []string       `json:"allow"`
}

type ExecConfig struct {
	BackgroundMs int  `json:"backgroundMs"`
	TimeoutSec   int  `json:"timeoutSec"`
	CleanupMs    int  `json:"cleanupMs"`
	NotifyOnExit bool `json:"notifyOnExit"`
}

type ElevatedConfig struct {
	Enabled   bool                `json:"enabled"`
	AllowFrom map[string][]string `json:"allowFrom"`
}

type ChannelsConfig struct {
	Telegram TelegramConfig `json:"telegram"`
}

type TelegramConfig struct {
	Enabled   bool     `json:"enabled"`
	BotToken  string   `json:"botToken"`
	DMPolicy  string   `json:"dmPolicy"`
	AllowFrom []string `json:"allowFrom"`
}

// GetMoltbotPath 获取执行路径
func GetMoltbotPath() (string, error) {
	if path, err := exec.LookPath("clawdbot"); err == nil {
		return path, nil
	}
	if path, err := exec.LookPath("moltbot"); err == nil {
		return path, nil
	}

	npmPrefix, err := getNpmPrefix()
	if err != nil {
		return "", err
	}

	possibleClawd := filepath.Join(npmPrefix, "clawdbot.cmd")
	if _, err := os.Stat(possibleClawd); err == nil {
		return possibleClawd, nil
	}

	possibleMolt := filepath.Join(npmPrefix, "moltbot.cmd")
	if _, err := os.Stat(possibleMolt); err == nil {
		return possibleMolt, nil
	}

	return "", fmt.Errorf("未找到 moltbot 或 clawdbot 可执行文件")
}

// GetNodePath 获取 Node 路径
func GetNodePath() (string, error) {
	var err error
	nodePathOnce.Do(func() {
		if path, e := exec.LookPath("node"); e == nil {
			cachedNodePath = path
			return
		}
		defaultPath := `C:\Program Files\nodejs\node.exe`
		if _, e := os.Stat(defaultPath); e == nil {
			cachedNodePath = defaultPath
			return
		}
		err = fmt.Errorf("未找到 Node.js")
	})
	if err != nil {
		return "", err
	}
	if cachedNodePath != "" {
		return cachedNodePath, nil
	}
	return "", fmt.Errorf("未找到 Node.js")
}

// GetGitPath 获取 Git 路径
func GetGitPath() (string, error) {
	var err error
	gitPathOnce.Do(func() {
		if path, e := exec.LookPath("git"); e == nil {
			cachedGitPath = path
			return
		}
		defaultPaths := []string{
			`C:\Program Files\Git\cmd\git.exe`,
			`C:\Program Files\Git\bin\git.exe`,
		}
		for _, p := range defaultPaths {
			if _, e := os.Stat(p); e == nil {
				cachedGitPath = p
				return
			}
		}
		err = fmt.Errorf("未找到 Git")
	})
	if err != nil {
		return "", err
	}
	if cachedGitPath != "" {
		return cachedGitPath, nil
	}
	return "", fmt.Errorf("未找到 Git")
}

// SetupNodeEnv 配置 Node 环境变量
func SetupNodeEnv() error {
	nodeExe, err := GetNodePath()
	if err != nil {
		return err
	}
	nodeDir := filepath.Dir(nodeExe)

	pathEnv := os.Getenv("PATH")
	if strings.Contains(strings.ToLower(pathEnv), strings.ToLower(nodeDir)) {
		return nil
	}

	newPath := nodeDir + string(os.PathListSeparator) + pathEnv

	if npmPrefix, err := getNpmPrefix(); err == nil {
		if !strings.Contains(strings.ToLower(newPath), strings.ToLower(npmPrefix)) {
			newPath = npmPrefix + string(os.PathListSeparator) + newPath
		}
	}

	return os.Setenv("PATH", newPath)
}

// SetupGitEnv 配置 Git 环境变量
func SetupGitEnv() error {
	gitExe, err := GetGitPath()
	if err != nil {
		return err
	}
	gitDir := filepath.Dir(gitExe)

	pathEnv := os.Getenv("PATH")
	if strings.Contains(strings.ToLower(pathEnv), strings.ToLower(gitDir)) {
		return nil
	}

	newPath := gitDir + string(os.PathListSeparator) + pathEnv
	return os.Setenv("PATH", newPath)
}

// CheckMoltbot 检查安装状态
func CheckMoltbot() (string, bool) {
	SetupNodeEnv()

	cmdName, err := GetMoltbotPath()
	if err != nil {
		return "", false
	}

	cmd := exec.Command("cmd", "/c", cmdName, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(out)), true
}

// CheckNode 检查 Node 版本
func CheckNode() (string, bool) {
	nodePath, err := GetNodePath()
	if err != nil {
		return "", false
	}

	cmd := exec.Command(nodePath, "-v")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}

	versionStr := strings.TrimSpace(string(out))
	re := regexp.MustCompile(`v(\d+)\.`)
	matches := re.FindStringSubmatch(versionStr)
	if len(matches) < 2 {
		return versionStr, false
	}

	majorVer, err := strconv.Atoi(matches[1])
	if err != nil {
		return versionStr, false
	}

	if majorVer >= 22 {
		return versionStr, true
	}
	return versionStr, false
}

// CheckGit 检查 Git 状态
func CheckGit() (string, bool) {
	gitPath, err := GetGitPath()
	if err != nil {
		return "", false
	}

	cmd := exec.Command(gitPath, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}

	return strings.TrimSpace(string(out)), true
}

// getNpmPath 获取 npm
func getNpmPath() (string, error) {
	path, err := exec.LookPath("npm")
	if err == nil {
		return path, nil
	}
	defaultPath := `C:\Program Files\nodejs\npm.cmd`
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath, nil
	}
	return "", fmt.Errorf("未找到 npm，请确认 Node.js 安装成功")
}

func getNpmPrefix() (string, error) {
	var err error
	prefixOnce.Do(func() {
		npmPath, e := getNpmPath()
		if e != nil {
			err = fmt.Errorf("无法定位 npm: %v", e)
			return
		}
		cmd := exec.Command(npmPath, "config", "get", "prefix")
		out, e := cmd.Output()
		if e != nil {
			err = fmt.Errorf("无法获取 npm prefix: %v", e)
			return
		}
		cachedNpmPrefix = strings.TrimSpace(string(out))
	})
	if err != nil {
		return "", err
	}
	return cachedNpmPrefix, nil
}

// ConfigureNpmMirror 配置镜像
func ConfigureNpmMirror() error {
	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}
	cmd := exec.Command(npmPath, "config", "set", "registry", "https://registry.npmmirror.com/")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("设置 npm 镜像失败: %v", err)
	}
	return nil
}

// downloadFile 下载文件
func downloadFile(url, dest string) error {
	if info, err := os.Stat(dest); err == nil && info.Size() > 10000000 {
		return nil
	}

	fmt.Printf("正在下载: %s\n", url)
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("下载失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("下载失败，状态码: %d", resp.StatusCode)
	}

	out, err := os.Create(dest)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	if err != nil {
		return fmt.Errorf("写入文件失败: %v", err)
	}
	return nil
}

// InstallNode 安装 Node.js
func InstallNode() error {
	if _, ok := CheckNode(); ok {
		return nil
	}

	msiUrl := "https://nodejs.org/dist/v24.13.0/node-v24.13.0-x64.msi"
	tempDir := os.TempDir()
	msiPath := filepath.Join(tempDir, "node-v24.13.0-x64.msi")

	if err := downloadFile(msiUrl, msiPath); err != nil {
		return err
	}

	fmt.Println("正在安装 Node.js (可能需要管理员权限)...")
	
	for i := 0; i < 3; i++ {
		installCmd := exec.Command("msiexec", "/i", msiPath, "/qn")
		output, err := installCmd.CombinedOutput()
		if err == nil {
			break
		}
		
		outStr := string(output)
		if strings.Contains(outStr, "1618") {
			time.Sleep(5 * time.Second)
			continue
		}
		
		if strings.Contains(outStr, "1619") {
			return fmt.Errorf("安装包损坏 (Error 1619). 请尝试手动下载: %s", msiUrl)
		}
		
		if i == 2 {
			return fmt.Errorf("安装失败: %v, Output: %s", err, outStr)
		}
		time.Sleep(2 * time.Second)
	}

	SetupNodeEnv()
	return nil
}

// InstallGit 安装 Git
func InstallGit() error {
	if _, ok := CheckGit(); ok {
		return nil
	}

	gitUrl := "https://github.com/git-for-windows/git/releases/download/v2.52.0.windows.1/Git-2.52.0-64-bit.exe"
	tempDir := os.TempDir()
	exePath := filepath.Join(tempDir, "Git-2.52.0-64-bit.exe")

	fmt.Println("正在下载 Git...")
	if err := downloadFile(gitUrl, exePath); err != nil {
		return fmt.Errorf("git 下载失败: %v", err)
	}

	fmt.Println("正在安装 Git (可能需要管理员权限)...")
	installCmd := exec.Command(exePath,
		"/VERYSILENT",
		"/NORESTART",
		"/NOCANCEL",
		"/SP-",
		"/CLOSEAPPLICATIONS",
		"/RESTARTAPPLICATIONS",
		"/o:PathOption=Cmd",
	)
	
	if out, err := installCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git 安装失败: %v, Output: %s", err, string(out))
	}

	SetupGitEnv()
	return nil
}

// InstallMoltbotNpm 安装包
func InstallMoltbotNpm(tag string) error {
	SetupNodeEnv()

	pkgName := "clawdbot"
	if tag == "" || tag == "beta" {
		tag = "latest"
	}

	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}

	os.Setenv("NPM_CONFIG_LOGLEVEL", "error")
	os.Setenv("NPM_CONFIG_UPDATE_NOTIFIER", "false")
	os.Setenv("NPM_CONFIG_FUND", "false")
	os.Setenv("NPM_CONFIG_AUDIT", "false")

	cmd := exec.Command(npmPath, "install", "-g", fmt.Sprintf("%s@%s", pkgName, tag))
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return err
	}

	return nil
}

// EnsureOnPath 检查并配置 PATH
func EnsureOnPath() (bool, error) {
	if _, err := exec.LookPath("clawdbot"); err == nil {
		return false, nil
	}
	if _, err := exec.LookPath("moltbot"); err == nil {
		return false, nil
	}

	npmPrefix, err := getNpmPrefix()
	if err != nil {
		return false, err
	}
	npmBin := filepath.Join(npmPrefix, "bin")

	possiblePath := npmPrefix

	if _, err := os.Stat(filepath.Join(npmPrefix, "clawdbot.cmd")); os.IsNotExist(err) {
		if _, err := os.Stat(filepath.Join(npmPrefix, "moltbot.cmd")); os.IsNotExist(err) {
			possiblePath = npmBin
		}
	}

	psCmd := fmt.Sprintf(`
		$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
		if (-not ($userPath -split ";" | Where-Object { $_ -ieq "%s" })) {
			[Environment]::SetEnvironmentVariable("Path", "$userPath;%s", "User")
		}
	`, possiblePath, possiblePath)

	exec.Command("powershell", "-Command", psCmd).Run()

	return true, nil
}

// RunDoctor 运行诊断
func RunDoctor() error {
	cmdName, err := GetMoltbotPath()
	if err != nil {
		cmdName = "moltbot"
	}

	cmd := exec.Command("cmd", "/c", cmdName, "doctor", "--non-interactive")
	return cmd.Run()
}

// RunOnboard 运行引导
func RunOnboard() error {
	cmdName, err := GetMoltbotPath()
	if err != nil {
		cmdName = "moltbot"
	}
	cmd := exec.Command("cmd", "/c", cmdName, "onboard")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// ConfigOptions 配置选项
type ConfigOptions struct {
	ApiType       string
	BotToken      string
	AdminID       string
	AnthropicKey  string
	OpenAIBaseURL string
	OpenAIKey     string
	OpenAIModel   string
}

// GenerateAndWriteConfig 生成配置
func GenerateAndWriteConfig(opts ConfigOptions) error {
	userHome, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("无法获取用户目录: %v", err)
	}
	configDir := filepath.Join(userHome, ".clawdbot")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("创建配置目录失败: %v", err)
	}
	configFile := filepath.Join(configDir, "clawdbot.json")

	config := MoltbotConfig{
		Gateway: GatewayConfig{
			Mode: "local",
			Bind: "loopback",
			Port: 18789,
		},
		Tools: ToolsConfig{
			Elevated: ElevatedConfig{
				Enabled:   true,
				AllowFrom: map[string][]string{},
			},
			Allow: []string{"exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"},
		},
		Channels: ChannelsConfig{
			Telegram: TelegramConfig{
				Enabled:   false,
				DMPolicy:  "pairing",
				AllowFrom: []string{},
			},
		},
	}

	if opts.BotToken != "" {
		config.Channels.Telegram.Enabled = true
		config.Channels.Telegram.BotToken = opts.BotToken
		if opts.AdminID != "" {
			config.Channels.Telegram.AllowFrom = []string{opts.AdminID}
			config.Tools.Elevated.AllowFrom["telegram"] = []string{opts.AdminID}
		}
	}

	if opts.ApiType == "anthropic" {
		config.Env = map[string]string{
			"ANTHROPIC_API_KEY": opts.AnthropicKey,
		}
		config.Agents = AgentsConfig{
			Defaults: AgentDefaults{
				Model: ModelRef{
					Primary: "anthropic/claude-opus-4-5",
				},
			},
		}
	} else if opts.ApiType == "skip" {
		config.Channels.Telegram.Enabled = false
		config.Agents = AgentsConfig{
			Defaults: AgentDefaults{
				Model: ModelRef{
					Primary: "anthropic/claude-opus-4-5",
				},
			},
		}
	} else {
		config.Agents = AgentsConfig{
			Defaults: AgentDefaults{
				Model: ModelRef{
					Primary: fmt.Sprintf("openai-compat/%s", opts.OpenAIModel),
				},
				ElevatedDefault: "full",
				Compaction: &CompactionConfig{
					Mode: "safeguard",
				},
				MaxConcurrent: 4,
			},
		}
		config.Models = &ModelsConfig{
			Mode: "merge",
			Providers: map[string]ProviderConfig{
				"openai-compat": {
					BaseURL: opts.OpenAIBaseURL,
					APIKey:  opts.OpenAIKey,
					API:     "openai-completions",
					Models: []ModelEntry{
						{ID: opts.OpenAIModel, Name: opts.OpenAIModel},
					},
				},
			},
		}
		config.Tools.Exec = &ExecConfig{
			BackgroundMs: 10000,
			TimeoutSec:   1800,
			CleanupMs:    1800000,
			NotifyOnExit: true,
		}
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %v", err)
	}

	return os.WriteFile(configFile, data, 0644)
}

// StartGateway 启动网关
func StartGateway() error {
	cmdName, err := GetMoltbotPath()
	if err != nil {
		cmdName = "moltbot"
	}

	cmd := exec.Command(cmdName, "gateway", "--verbose")
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: 0x08000000,
	}

	return cmd.Start()
}

// IsGatewayRunning 检查端口
func IsGatewayRunning() bool {
	conn, err := net.DialTimeout("tcp", "127.0.0.1:18789", 500*time.Millisecond)
	if err == nil {
		conn.Close()
		return true
	}
	return false
}

// KillGateway 停止网关
func KillGateway() error {
	cmd := exec.Command("netstat", "-ano")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.Output()
	if err != nil {
		return err
	}

	scanner := bufio.NewScanner(bytes.NewReader(out))
	var pid string
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, ":18789") && strings.Contains(line, "LISTENING") {
			fields := strings.Fields(line)
			if len(fields) > 0 {
				pid = fields[len(fields)-1]
				break
			}
		}
	}

	if pid == "" {
		return nil
	}

	killCmd := exec.Command("taskkill", "/F", "/PID", pid)
	killCmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return killCmd.Run()
}

// UninstallMoltbot 卸载清理
func UninstallMoltbot() error {
	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}

	packages := []string{"clawdbot", "moltbot"}
	for _, pkg := range packages {
		cmd := exec.Command(npmPath, "uninstall", "-g", pkg)
		cmd.Stdout = nil
		cmd.Stderr = nil
		cmd.Run()
	}

	userHome, err := os.UserHomeDir()
	if err == nil {
		configDir := filepath.Join(userHome, ".clawdbot")
		os.RemoveAll(configDir)

		legacyDir := filepath.Join(userHome, ".moltbot")
		os.RemoveAll(legacyDir)
	}

	return nil
}
