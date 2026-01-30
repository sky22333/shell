package sys

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
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
	"sync/atomic"
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

const (
	downloadConcurrentThreshold int64 = 20 * 1024 * 1024
	downloadConcurrentParts           = 4
)

const gitProxyEnv = "GIT_PROXY"
const gitProxyDefault = "https://g.blfrp.cn/"

func gitProxy() string {
	proxy := strings.TrimSpace(os.Getenv(gitProxyEnv))
	if proxy == "" {
		proxy = gitProxyDefault
	}
	if !strings.HasSuffix(proxy, "/") {
		proxy += "/"
	}
	return proxy
}

// SHA256 来源 https://nodejs.org/dist/v24.13.0/SHASUMS256.txt.asc
const nodeMsiSHA256 = "1a5f0cd914386f3be2fbaf03ad9fff808a588ce50d2e155f338fad5530575f18"

// SHA256 来源 https://github.com/git-for-windows/git/releases/tag/v2.52.0.windows.1
const gitExeSHA256 = "d8de7a3152266c8bb13577eab850ea1df6dccf8c2aa48be5b4a1c58b7190d62c"

// OpenclawConfig 配置结构
type OpenclawConfig struct {
	Gateway  GatewayConfig     `json:"gateway"`
	Env      map[string]string `json:"env,omitempty"`
	Agents   AgentsConfig      `json:"agents"`
	Models   *ModelsConfig     `json:"models,omitempty"`
	Tools    ToolsConfig       `json:"tools"`
	Channels ChannelsConfig    `json:"channels"`
}

type GatewayConfig struct {
	Mode string      `json:"mode"`
	Bind string      `json:"bind"`
	Port int         `json:"port"`
	Auth *AuthConfig `json:"auth,omitempty"`
}

type AuthConfig struct {
	Mode  string `json:"mode,omitempty"`
	Token string `json:"token"`
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

// GetOpenclawPath 获取执行路径
func GetOpenclawPath() (string, error) {
	if path, err := exec.LookPath("openclaw"); err == nil {
		return path, nil
	}
	// Legacy fallback
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

	possibleClawd := filepath.Join(npmPrefix, "openclaw.cmd")
	if _, err := os.Stat(possibleClawd); err == nil {
		return possibleClawd, nil
	}

	// Legacy checks
	possibleMolt := filepath.Join(npmPrefix, "moltbot.cmd")
	if _, err := os.Stat(possibleMolt); err == nil {
		return possibleMolt, nil
	}

	return "", fmt.Errorf("未找到 openclaw 可执行文件")
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

// CheckOpenclaw 检查安装状态
func CheckOpenclaw() (string, bool) {
	SetupNodeEnv()

	cmdName, err := GetOpenclawPath()
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

func ResetPathCache() {
	cachedNpmPrefix = ""
	cachedNodePath = ""
	cachedGitPath = ""
	prefixOnce = sync.Once{}
	nodePathOnce = sync.Once{}
	gitPathOnce = sync.Once{}
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

func ConfigureGitProxy() error {
	var lastErr error
	for i := 0; i < 3; i++ {
		ResetPathCache()
		gitPath, err := GetGitPath()
		if err != nil {
			lastErr = err
		} else {
			proxy := gitProxy()
			key := fmt.Sprintf("url.%shttps://github.com/.insteadOf", proxy)
			cmd := exec.Command(gitPath, "config", "--global", key, "https://github.com/")
			if err := cmd.Run(); err == nil {
				return nil
			} else {
				lastErr = fmt.Errorf("设置 git 代理失败: %v", err)
			}
		}
		time.Sleep(300 * time.Millisecond)
	}
	return lastErr
}

// downloadFile 下载文件
func downloadFile(url, dest, expectedSHA256 string) error {
	if ok, err := verifyFileSHA256(dest, expectedSHA256); err == nil && ok {
		return nil
	}

	partPath := dest + ".part"
	if ok, err := verifyFileSHA256(partPath, expectedSHA256); err == nil && ok {
		_ = os.Remove(dest)
		return os.Rename(partPath, dest)
	}

	_ = os.Remove(dest)

	size, acceptRanges, err := probeRemoteFile(url)
	if err != nil {
		return err
	}

	if err := downloadWithResume(url, partPath, size, acceptRanges); err != nil {
		return err
	}

	if ok, err := verifyFileSHA256(partPath, expectedSHA256); err != nil || !ok {
		_ = os.Remove(partPath)
		if err != nil {
			return err
		}
		return fmt.Errorf("下载文件校验失败")
	}

	_ = os.Remove(dest)
	return os.Rename(partPath, dest)
}

func downloadWithResume(url, dest string, size int64, acceptRanges bool) error {
	if size > 0 && acceptRanges {
		if info, err := os.Stat(dest); err == nil && info.Size() > 0 && info.Size() < size {
			return downloadRange(url, dest, info.Size(), size-1, size)
		}
		if size >= downloadConcurrentThreshold {
			return downloadConcurrent(url, dest, size, downloadConcurrentParts)
		}
	}
	return downloadRange(url, dest, 0, -1, size)
}

func downloadRange(url, dest string, start, end, total int64) error {
	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer out.Close()

	if start > 0 {
		if _, err := out.Seek(start, 0); err != nil {
			return fmt.Errorf("定位文件失败: %v", err)
		}
	}

	client := &http.Client{Timeout: 30 * time.Minute}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("创建请求失败: %v", err)
	}
	if start > 0 || end >= 0 {
		if end >= start && end >= 0 {
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
		} else {
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-", start))
		}
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("下载失败: %v", err)
	}
	defer resp.Body.Close()

	if start > 0 && resp.StatusCode != http.StatusPartialContent {
		return fmt.Errorf("不支持断点续传，状态码: %d", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		return fmt.Errorf("下载失败，状态码: %d", resp.StatusCode)
	}

	if total <= 0 && resp.ContentLength > 0 {
		total = start + resp.ContentLength
	}
	progress := newProgressReporter(total, start)
	progress.Start()
	reader := &countingReader{r: resp.Body, written: progress.written}
	if _, err = io.Copy(out, reader); err != nil {
		progress.Stop()
		return fmt.Errorf("写入文件失败: %v", err)
	}
	progress.Stop()
	return nil
}

func downloadConcurrent(url, dest string, size int64, parts int) error {
	if parts < 2 {
		return downloadRange(url, dest, 0, -1, size)
	}

	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	if err := out.Truncate(size); err != nil {
		out.Close()
		return fmt.Errorf("预分配文件失败: %v", err)
	}

	var wg sync.WaitGroup
	errCh := make(chan error, parts)
	progress := newProgressReporter(size, 0)
	progress.Start()

	partSize := size / int64(parts)
	for i := 0; i < parts; i++ {
		start := int64(i) * partSize
		end := start + partSize - 1
		if i == parts-1 {
			end = size - 1
		}

		wg.Add(1)
		go func(s, e int64) {
			defer wg.Done()
			client := &http.Client{Timeout: 30 * time.Minute}
			req, err := http.NewRequest("GET", url, nil)
			if err != nil {
				errCh <- fmt.Errorf("创建请求失败: %v", err)
				return
			}
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", s, e))
			resp, err := client.Do(req)
			if err != nil {
				errCh <- fmt.Errorf("下载失败: %v", err)
				return
			}
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusPartialContent {
				errCh <- fmt.Errorf("分段下载失败，状态码: %d", resp.StatusCode)
				return
			}
			writer := &writeAtWriter{file: out, offset: s, written: progress.written}
			if _, err := io.Copy(writer, resp.Body); err != nil {
				errCh <- fmt.Errorf("写入文件失败: %v", err)
				return
			}
		}(start, end)
	}

	wg.Wait()
	close(errCh)
	out.Close()
	progress.Stop()

	for err := range errCh {
		if err != nil {
			return err
		}
	}
	return nil
}

type writeAtWriter struct {
	file   *os.File
	offset int64
	written *int64
}

func (w *writeAtWriter) Write(p []byte) (int, error) {
	n, err := w.file.WriteAt(p, w.offset)
	w.offset += int64(n)
	if w.written != nil && n > 0 {
		atomic.AddInt64(w.written, int64(n))
	}
	return n, err
}

type countingReader struct {
	r       io.Reader
	written *int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	if n > 0 && c.written != nil {
		atomic.AddInt64(c.written, int64(n))
	}
	return n, err
}

type progressReporter struct {
	total   int64
	written *int64
	done    chan struct{}
	once    sync.Once
}

func newProgressReporter(total, initial int64) *progressReporter {
	current := initial
	return &progressReporter{
		total:   total,
		written: &current,
		done:    make(chan struct{}),
	}
}

func (p *progressReporter) Start() {
	if p == nil || p.total <= 0 {
		return
	}
	p.print()
	go func() {
		ticker := time.NewTicker(200 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				p.print()
			case <-p.done:
				p.print()
				fmt.Print("\n")
				return
			}
		}
	}()
}

func (p *progressReporter) Stop() {
	if p == nil || p.total <= 0 {
		return
	}
	p.once.Do(func() {
		close(p.done)
	})
}

func (p *progressReporter) print() {
	current := atomic.LoadInt64(p.written)
	if current < 0 {
		current = 0
	}
	if current > p.total {
		current = p.total
	}
	percent := float64(current) * 100 / float64(p.total)
	fmt.Printf("\r下载进度: %.2f%%", percent)
}

func probeRemoteFile(url string) (int64, bool, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("HEAD", url, nil)
	if err == nil {
		resp, err := client.Do(req)
		if err == nil {
			resp.Body.Close()
			size := resp.ContentLength
			acceptRanges := strings.Contains(strings.ToLower(resp.Header.Get("Accept-Ranges")), "bytes")
			if size > 0 && acceptRanges {
				return size, acceptRanges, nil
			}
		}
	}

	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return 0, false, fmt.Errorf("创建请求失败: %v", err)
	}
	req.Header.Set("Range", "bytes=0-0")
	resp, err := client.Do(req)
	if err != nil {
		return 0, false, fmt.Errorf("探测下载失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusPartialContent {
		return -1, false, nil
	}

	total := parseContentRangeTotal(resp.Header.Get("Content-Range"))
	return total, true, nil
}

func parseContentRangeTotal(value string) int64 {
	parts := strings.Split(value, "/")
	if len(parts) != 2 {
		return -1
	}
	totalStr := strings.TrimSpace(parts[1])
	if totalStr == "*" {
		return -1
	}
	total, err := strconv.ParseInt(totalStr, 10, 64)
	if err != nil {
		return -1
	}
	return total
}

func verifyFileSHA256(path, expected string) (bool, error) {
	if expected == "" {
		return true, nil
	}
	info, err := os.Stat(path)
	if err != nil || info.Size() == 0 {
		return false, err
	}
	sum, err := fileSHA256(path)
	if err != nil {
		return false, err
	}
	return strings.EqualFold(sum, expected), nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("打开文件失败: %v", err)
	}
	defer f.Close()

	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return "", fmt.Errorf("读取文件失败: %v", err)
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

// InstallNode 安装 Node.js
func InstallNode() error {
	if _, ok := CheckNode(); ok {
		return nil
	}

	msiUrl := "https://nodejs.org/dist/v24.13.0/node-v24.13.0-x64.msi"
	tempDir := os.TempDir()
	msiPath := filepath.Join(tempDir, "node-v24.13.0-x64.msi")

	if err := downloadFile(msiUrl, msiPath, nodeMsiSHA256); err != nil {
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

	gitUrl := fmt.Sprintf("%sgithub.com/git-for-windows/git/releases/download/v2.52.0.windows.1/Git-2.52.0-64-bit.exe", gitProxy())
	tempDir := os.TempDir()
	exePath := filepath.Join(tempDir, "Git-2.52.0-64-bit.exe")

	fmt.Println("正在下载 Git...")
	if err := downloadFile(gitUrl, exePath, gitExeSHA256); err != nil {
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

	ResetPathCache()
	SetupGitEnv()
	return nil
}

// InstallOpenclawNpm 安装包
func InstallOpenclawNpm(tag string) error {
	SetupNodeEnv()

	pkgName := "openclaw"
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
	if _, err := exec.LookPath("openclaw"); err == nil {
		return false, nil
	}
	if _, err := exec.LookPath("clawdbot"); err == nil {
		return false, nil
	}

	npmPrefix, err := getNpmPrefix()
	if err != nil {
		return false, err
	}
	npmBin := filepath.Join(npmPrefix, "bin")

	possiblePath := npmPrefix

	if _, err := os.Stat(filepath.Join(npmPrefix, "openclaw.cmd")); os.IsNotExist(err) {
		if _, err := os.Stat(filepath.Join(npmPrefix, "clawdbot.cmd")); os.IsNotExist(err) {
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
	cmdName, err := GetOpenclawPath()
	if err != nil {
		cmdName = "openclaw"
	}

	cmd := exec.Command("cmd", "/c", cmdName, "doctor", "--non-interactive")
	return cmd.Run()
}

// RunOnboard 运行引导
func RunOnboard() error {
	cmdName, err := GetOpenclawPath()
	if err != nil {
		cmdName = "openclaw"
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
	configDir := filepath.Join(userHome, ".openclaw")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("创建配置目录失败: %v", err)
	}
	configFile := filepath.Join(configDir, "openclaw.json")

	// 生成随机 Token
	tokenBytes := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, tokenBytes); err != nil {
		// 降级方案
		copy(tokenBytes, []byte(fmt.Sprintf("%d", time.Now().UnixNano())))
	}
	token := hex.EncodeToString(tokenBytes)

	config := OpenclawConfig{
		Gateway: GatewayConfig{
			Mode: "local",
			Bind: "loopback",
			Port: 18789,
			Auth: &AuthConfig{
				Mode:  "token",
				Token: token,
			},
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

	if err := os.WriteFile(configFile, data, 0644); err != nil {
		return err
	}

	fmt.Printf("配置文件绝对路径: %s\n", configFile)
	fmt.Printf("Gateway Token: %s\n", token)
	fmt.Println("请妥善保存此 Token，用于远程连接 Gateway。")

	return nil
}

// StartGateway 启动网关
func StartGateway() error {
	cmdName, err := GetOpenclawPath()
	if err != nil {
		cmdName = "openclaw"
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

// UninstallOpenclaw 卸载清理
func UninstallOpenclaw() error {
	npmPath, err := getNpmPath()
	if err != nil {
		return err
	}

	packages := []string{"openclaw", "clawdbot"}
	for _, pkg := range packages {
		cmd := exec.Command(npmPath, "uninstall", "-g", pkg)
		cmd.Stdout = nil
		cmd.Stderr = nil
		cmd.Run()
	}

	userHome, err := os.UserHomeDir()
	if err == nil {
		configDir := filepath.Join(userHome, ".openclaw")
		os.RemoveAll(configDir)

		legacyDir := filepath.Join(userHome, ".clawdbot")
		os.RemoveAll(legacyDir)
	}

	return nil
}
