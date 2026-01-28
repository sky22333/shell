package sys

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

var (
	cachedNpmPrefix string
	cachedNodePath  string
	prefixOnce      sync.Once
	nodePathOnce    sync.Once
)

// Config Structures

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

// GetMoltbotPath 尝试解析 moltbot 或 clawdbot 的绝对路径
func GetMoltbotPath() (string, error) {
	// 优先检查 clawdbot
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

	// 检查 clawdbot.cmd
	possibleClawd := filepath.Join(npmPrefix, "clawdbot.cmd")
	if _, err := os.Stat(possibleClawd); err == nil {
		return possibleClawd, nil
	}

	// 检查 moltbot.cmd
	possibleMolt := filepath.Join(npmPrefix, "moltbot.cmd")
	if _, err := os.Stat(possibleMolt); err == nil {
		return possibleMolt, nil
	}

	return "", fmt.Errorf("未找到 moltbot 或 clawdbot 可执行文件")
}

// GetNodePath 获取 Node.js 可执行文件的绝对路径
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

// SetupNodeEnv 将 Node.js 所在目录添加到当前进程的 PATH 环境变量
// 这对于刚安装完 Node.js 但未重启终端的情况非常重要
func SetupNodeEnv() error {
	nodeExe, err := GetNodePath()
	if err != nil {
		return err
	}
	nodeDir := filepath.Dir(nodeExe)

	pathEnv := os.Getenv("PATH")
	// 简单检查是否已包含 (忽略大小写)
	if strings.Contains(strings.ToLower(pathEnv), strings.ToLower(nodeDir)) {
		return nil
	}

	newPath := nodeDir + string(os.PathListSeparator) + pathEnv

	// 同时确保 npm prefix 在 PATH 中
	if npmPrefix, err := getNpmPrefix(); err == nil {
		if !strings.Contains(strings.ToLower(newPath), strings.ToLower(npmPrefix)) {
			newPath = npmPrefix + string(os.PathListSeparator) + newPath
		}
	}

	return os.Setenv("PATH", newPath)
}

// CheckMoltbot 检查 Moltbot 是否已安装
// 返回: (版本号, 是否已安装)
func CheckMoltbot() (string, bool) {
	// 确保环境正确
	SetupNodeEnv()

	cmdName, err := GetMoltbotPath()
	if err != nil {
		return "", false
	}

	// Get version
	cmd := exec.Command("cmd", "/c", cmdName, "--version")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(out)), true
}

// CheckNode 检查 Node.js 版本是否 >= 22
func CheckNode() (string, bool) {
	// Try to find node
	nodePath, err := GetNodePath()
	if err != nil {
		return "", false
	}

	cmd := exec.Command(nodePath, "-v")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}

	versionStr := strings.TrimSpace(string(out)) // e.g., "v22.1.0"
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

// getNpmPath 获取 npm 可执行文件路径
func getNpmPath() (string, error) {
	path, err := exec.LookPath("npm")
	if err == nil {
		return path, nil
	}
	// Try default Windows install path
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

// ConfigureNpmMirror 设置 npm 淘宝镜像
func ConfigureNpmMirror() error {
	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}
	// 设置 registry 为淘宝镜像
	cmd := exec.Command(npmPath, "config", "set", "registry", "https://registry.npmmirror.com/")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("设置 npm 镜像失败: %v", err)
	}
	return nil
}

// InstallNode 下载并安装 Node.js MSI
func InstallNode() error {
	msiUrl := "https://nodejs.org/dist/v24.13.0/node-v24.13.0-x64.msi"
	tempDir := os.TempDir()
	msiPath := filepath.Join(tempDir, "node-v24.13.0-x64.msi")

	// 1. 下载 MSI
	fmt.Printf("正在下载 Node.js: %s\n", msiUrl)
	resp, err := http.Get(msiUrl)
	if err != nil {
		return fmt.Errorf("下载失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("下载失败，状态码: %d", resp.StatusCode)
	}

	out, err := os.Create(msiPath)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	if err != nil {
		return fmt.Errorf("写入文件失败: %v", err)
	}

	// 2. 安装 MSI (静默安装)
	// msiexec /i <file> /qn
	fmt.Println("正在安装 Node.js...")
	installCmd := exec.Command("msiexec", "/i", msiPath, "/qn")
	if err := installCmd.Run(); err != nil {
		return fmt.Errorf("安装失败: %v", err)
	}

	// 3. 刷新环境变量 (当前进程无法立即生效，但后续调用 getNpmPath 会尝试绝对路径)
	SetupNodeEnv()
	return nil
}

// InstallMoltbotNpm 使用 npm 全局安装
func InstallMoltbotNpm(tag string) error {
	// 确保 Node 环境就绪
	SetupNodeEnv()

	// 强制使用 clawdbot 包，因为用户反馈该包更稳定
	// 如果之前传入的是 beta，重置为 latest，因为 clawdbot 的版本管理可能不同
	pkgName := "clawdbot"
	if tag == "" || tag == "beta" {
		tag = "latest"
	}

	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}

	// 设置环境变量以减少 npm 输出
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

// EnsureOnPath 确保 moltbot 或 clawdbot 在 PATH 中
// 返回值: (需要重启终端, error)
func EnsureOnPath() (bool, error) {
	if _, err := exec.LookPath("clawdbot"); err == nil {
		return false, nil // 已存在
	}
	if _, err := exec.LookPath("moltbot"); err == nil {
		return false, nil // 已存在
	}

	npmPrefix, err := getNpmPrefix()
	if err != nil {
		return false, err
	}
	npmBin := filepath.Join(npmPrefix, "bin")

	// 查找 clawdbot.cmd 或 moltbot.cmd
	possiblePath := npmPrefix

	// Check priority: clawdbot -> moltbot
	if _, err := os.Stat(filepath.Join(npmPrefix, "clawdbot.cmd")); os.IsNotExist(err) {
		if _, err := os.Stat(filepath.Join(npmPrefix, "moltbot.cmd")); os.IsNotExist(err) {
			// Check bin subdir
			possiblePath = npmBin
		}
	}

	// 添加到用户 PATH
	// 这里我们添加包含 .cmd 文件的目录到 PATH
	psCmd := fmt.Sprintf(`
		$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
		if (-not ($userPath -split ";" | Where-Object { $_ -ieq "%s" })) {
			[Environment]::SetEnvironmentVariable("Path", "$userPath;%s", "User")
		}
	`, possiblePath, possiblePath)

	exec.Command("powershell", "-Command", psCmd).Run()

	return true, nil // 已添加，需要重启终端
}

// RunDoctor 运行迁移
func RunDoctor() error {
	cmdName, err := GetMoltbotPath()
	if err != nil {
		// 尝试直接运行，虽然可能失败
		cmdName = "moltbot"
	}

	// 在 Windows 上，需要通过 cmd /c 或 powershell 来运行 .cmd 文件
	// 但 exec.Command 如果指向 .cmd 文件通常可以直接运行
	// 为了保险，使用 cmd /c
	cmd := exec.Command("cmd", "/c", cmdName, "doctor", "--non-interactive")
	return cmd.Run()
}

// RunOnboard 运行引导 (未使用，保留备用)
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

// Config Options Struct
type ConfigOptions struct {
	ApiType       string // "anthropic" or "openai"
	BotToken      string
	AdminID       string
	AnthropicKey  string
	OpenAIBaseURL string
	OpenAIKey     string
	OpenAIModel   string
}

// GenerateAndWriteConfig 生成并写入配置文件
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
				Enabled: true,
				AllowFrom: map[string][]string{
					"telegram": {opts.AdminID},
				},
			},
			Allow: []string{"exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"},
		},
		Channels: ChannelsConfig{
			Telegram: TelegramConfig{
				Enabled:   true,
				BotToken:  opts.BotToken,
				DMPolicy:  "pairing",
				AllowFrom: []string{opts.AdminID},
			},
		},
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
	} else {
		// OpenAI Compatible
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
		// Add extra exec config for OpenAI mode (as per install.sh)
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

// StartGateway 在新窗口启动网关
func StartGateway() error {
	cmdName, err := GetMoltbotPath()
	if err != nil {
		// Fallback if not found (though unlikely if installed)
		cmdName = "moltbot"
	}

	// 使用 start 命令在新窗口运行
	// Windows start command: start "Title" "Executable" args...
	cmd := exec.Command("cmd", "/c", "start", "Moltbot Gateway", cmdName, "gateway", "--verbose")
	return cmd.Start()
}

// UninstallMoltbot 卸载 Moltbot/Clawdbot 并清理配置
func UninstallMoltbot() error {
	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}

	// 1. Uninstall global packages
	packages := []string{"clawdbot", "moltbot"}
	for _, pkg := range packages {
		cmd := exec.Command(npmPath, "uninstall", "-g", pkg)
		cmd.Stdout = nil
		cmd.Stderr = nil
		cmd.Run() // Ignore errors if not installed
	}

	// 2. Remove configuration directory
	userHome, err := os.UserHomeDir()
	if err == nil {
		configDir := filepath.Join(userHome, ".clawdbot")
		os.RemoveAll(configDir)

		// Also check for legacy .moltbot if exists
		legacyDir := filepath.Join(userHome, ".moltbot")
		os.RemoveAll(legacyDir)
	}

	return nil
}
