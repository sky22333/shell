package ui

import (
	"fmt"
	"math/rand"
	"time"

	"moltbot-installer/internal/style"
	"moltbot-installer/internal/sys"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

type AppState int

const (
	StateInit AppState = iota
	StateChecking
	StateConfirmInstall
	StateInstallingNode
	StateConfiguringNpm
	StateInstallingMoltbot
	StateConfiguring
	StateInstalled
	StateMenu
	StateConfigApiSelect
	StateConfigInput
	StateUninstallConfirm
	StateUninstalling
	StateError
)

type Model struct {
	state      AppState
	spinner    spinner.Model
	err        error
	logs       []string
	nodeVer    string
	nodeOk     bool
	installMsg string
	quitting   bool

	// Config Wizard
	input      textinput.Model
	configOpts sys.ConfigOptions
	configStep int
	menuIndex  int

	DidStartGateway bool
}

type checkMsg struct {
	nodeVer          string
	nodeOk           bool
	needsNode        bool
	moltbotVer       string
	moltbotInstalled bool
}

type installNodeMsg struct{ err error }
type configNpmMsg struct{ err error }
type installMoltbotMsg struct {
	version string
	err     error
}
type configMsg struct {
	restartPath bool
	err         error
}
type saveConfigMsg struct{ err error }
type uninstallMsg struct{ err error }

func InitialModel() Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = style.HeaderStyle

	ti := textinput.New()
	ti.Cursor.Style = style.HeaderStyle
	ti.Focus()

	return Model{
		state:   StateInit,
		spinner: s,
		input:   ti,
		logs:    []string{},
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		func() tea.Msg {
			time.Sleep(500 * time.Millisecond)
			return checkMsg{}
		},
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			m.quitting = true
			return m, tea.Quit
		}

		// Menu Navigation
		if m.state == StateMenu {
			switch msg.String() {
			case "up", "k":
				if m.menuIndex > 0 {
					m.menuIndex--
				}
			case "down", "j":
				if m.menuIndex < 2 {
					m.menuIndex++
				}
			case "enter":
				switch m.menuIndex {
				case 0: // Start
					sys.StartGateway()
					m.DidStartGateway = true
					return m, tea.Quit
				case 1: // Configure
					m.state = StateConfigApiSelect
					m.configOpts = sys.ConfigOptions{}
				case 2: // Uninstall
					m.state = StateUninstallConfirm
				case 3: // Exit
					return m, tea.Quit
				}
			}
			return m, nil
		}

		// Uninstall Confirm State
		if m.state == StateUninstallConfirm {
			switch msg.String() {
			case "y", "Y":
				m.state = StateUninstalling
				m.logs = append(m.logs, style.RenderStep("➜", "正在卸载 Moltbot 并清理配置...", "running"))
				return m, uninstallCmd
			case "n", "N", "enter":
				m.state = StateMenu
			}
			return m, nil
		}

		// Config API Selection
		if m.state == StateConfigApiSelect {
			switch msg.String() {
			case "1":
				m.configOpts.ApiType = "anthropic"
				m.state = StateConfigInput
				m.configStep = 0
				m.input.Placeholder = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
				m.input.EchoMode = textinput.EchoNormal
				m.input.SetValue("")
			case "2":
				m.configOpts.ApiType = "openai"
				m.state = StateConfigInput
				m.configStep = 0
				m.input.Placeholder = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
				m.input.EchoMode = textinput.EchoNormal
				m.input.SetValue("")
			case "q", "esc":
				m.state = StateMenu // Back to menu
			}
			return m, nil
		}

		// Config Input Steps
		if m.state == StateConfigInput {
			switch msg.String() {
			case "enter":
				val := m.input.Value()
				// Save current step value
				switch m.configStep {
				case 0: // Bot Token
					m.configOpts.BotToken = val
					m.configStep++
					m.input.Placeholder = "123456789"
					m.input.SetValue("")
				case 1: // Admin ID
					m.configOpts.AdminID = val
					m.configStep++
					if m.configOpts.ApiType == "anthropic" {
						m.input.Placeholder = "sk-ant-api03-..."
						m.input.EchoMode = textinput.EchoPassword
					} else {
						m.input.Placeholder = "https://api.openai.com/v1"
						m.input.EchoMode = textinput.EchoNormal
					}
					m.input.SetValue("")
				case 2: // Key (Anthropic) OR BaseURL (OpenAI)
					if m.configOpts.ApiType == "anthropic" {
						m.configOpts.AnthropicKey = val
						// Finish Anthropic
						return m, saveConfigCmd(m.configOpts)
					} else {
						m.configOpts.OpenAIBaseURL = val
						m.configStep++
						m.input.Placeholder = "sk-..."
						m.input.EchoMode = textinput.EchoPassword
						m.input.SetValue("")
					}
				case 3: // Key (OpenAI)
					m.configOpts.OpenAIKey = val
					m.configStep++
					m.input.Placeholder = "gpt-4o / claude-3-5-sonnet"
					m.input.EchoMode = textinput.EchoNormal
					m.input.SetValue("")
				case 4: // Model (OpenAI)
					m.configOpts.OpenAIModel = val
					// Finish OpenAI
					return m, saveConfigCmd(m.configOpts)
				}
				return m, nil
			}
			m.input, cmd = m.input.Update(msg)
			return m, cmd
		}

		// Confirm Install State
		if m.state == StateConfirmInstall {
			switch msg.String() {
			case "y", "Y":
				m.logs = append(m.logs, style.RenderStep("➜", "开始安装...", "running"))
				if !m.nodeOk {
					m.state = StateInstallingNode
					m.logs = append(m.logs, style.RenderStep("➜", "正在安装 Node.js (可能需要管理员权限)...", "running"))
					return m, installNodeCmd
				}
				m.state = StateConfiguringNpm
				m.logs = append(m.logs, style.RenderStep("➜", "正在配置 npm 淘宝镜像...", "running"))
				return m, configNpmCmd
			case "n", "N", "enter":
				m.logs = append(m.logs, style.RenderStep("!", "跳过安装步骤", "warning"))
				m.state = StateConfiguring
				return m, configCmd
			}
			return m, nil
		}

		// Installed State (Transition to Config)
		if m.state == StateInstalled {
			if msg.String() == "enter" {
				m.state = StateConfigApiSelect
				m.configOpts = sys.ConfigOptions{}
			}
			return m, nil
		}

	case checkMsg:
		if m.state == StateInit {
			m.state = StateChecking
			return m, checkEnvCmd
		}

		m.nodeVer = msg.nodeVer
		m.nodeOk = msg.nodeOk
		m.logs = append(m.logs, style.RenderStep("✓", "Windows 系统检测完毕", "done"))

		if msg.nodeOk {
			m.logs = append(m.logs, style.RenderStep("✓", fmt.Sprintf("发现 Node.js %s", msg.nodeVer), "done"))
		} else {
			if msg.nodeVer != "" {
				m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("发现 Node.js %s (需要 v22+)", msg.nodeVer), "warning"))
			} else {
				m.logs = append(m.logs, style.RenderStep("!", "未检测到 Node.js", "warning"))
			}
		}

		if msg.moltbotInstalled {
			m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("检测到 Moltbot 已安装 (%s)", msg.moltbotVer), "warning"))
			m.state = StateConfirmInstall
			return m, nil
		}

		if !msg.nodeOk {
			m.state = StateInstallingNode
			m.logs = append(m.logs, style.RenderStep("➜", "正在安装 Node.js (可能需要管理员权限)...", "running"))
			return m, installNodeCmd
		}

		m.state = StateConfiguringNpm
		m.logs = append(m.logs, style.RenderStep("➜", "正在配置 npm 淘宝镜像...", "running"))
		return m, configNpmCmd

	case installNodeMsg:
		if msg.err != nil {
			m.err = msg.err
			m.state = StateError
			return m, nil
		}
		m.logs = append(m.logs, style.RenderStep("✓", "Node.js 安装成功", "done"))
		m.state = StateConfiguringNpm
		m.logs = append(m.logs, style.RenderStep("➜", "正在配置 npm 淘宝镜像...", "running"))
		return m, configNpmCmd

	case configNpmMsg:
		if msg.err != nil {
			m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("配置镜像失败 (跳过): %v", msg.err), "warning"))
		} else {
			m.logs = append(m.logs, style.RenderStep("✓", "npm 淘宝镜像配置成功", "done"))
		}
		m.state = StateInstallingMoltbot
		m.logs = append(m.logs, style.RenderStep("➜", "正在安装 Moltbot...", "running"))
		return m, installMoltbotCmd

	case installMoltbotMsg:
		if msg.err != nil {
			m.err = msg.err
			m.state = StateError
			return m, nil
		}
		if msg.version != "" {
			m.logs = append(m.logs, style.RenderStep("✓", fmt.Sprintf("Moltbot 安装成功 (%s)", msg.version), "done"))
		} else {
			m.logs = append(m.logs, style.RenderStep("✓", "Moltbot 安装成功", "done"))
		}
		m.state = StateConfiguring
		return m, configCmd

	case configMsg:
		if msg.err != nil {
			m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("配置迁移失败: %v", msg.err), "warning"))
		} else {
			m.logs = append(m.logs, style.RenderStep("✓", "配置迁移/初始化完成", "done"))
		}
		if msg.restartPath {
			m.logs = append(m.logs, style.RenderStep("!", "已添加 PATH 环境变量，请重启终端生效", "warning"))
		}
		m.state = StateInstalled
		m.installMsg = getRandomWelcomeMsg()
		return m, nil

	case saveConfigMsg:
		if msg.err != nil {
			m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("保存配置失败: %v", msg.err), "warning"))
		} else {
			m.logs = append(m.logs, style.RenderStep("✓", "配置文件已生成!", "done"))
			m.logs = append(m.logs, style.RenderStep("✓", "配置完成，准备启动", "done"))
		}
		m.state = StateMenu
		m.menuIndex = 0 // Default to Start
		return m, nil

	case uninstallMsg:
		if msg.err != nil {
			m.logs = append(m.logs, style.RenderStep("!", fmt.Sprintf("卸载失败: %v", msg.err), "warning"))
		} else {
			m.logs = append(m.logs, style.RenderStep("✓", "Moltbot 已卸载并清理配置", "done"))
		}
		m.state = StateMenu
		m.menuIndex = 0
		return m, nil

	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	return m, nil
}

func (m Model) View() string {
	if m.err != nil {
		return fmt.Sprintf("\n%s\n\n%s: %v\n\n按 q 退出\n",
			style.HeaderStyle.Render("Moltbot 安装程序"),
			style.ErrorStyle.Render("发生错误"),
			m.err,
		)
	}

	s := fmt.Sprintf("\n%s\n\n", style.HeaderStyle.Render("Moltbot 安装程序"))

	// Show logs for install process
	if m.state != StateMenu && m.state != StateConfigApiSelect && m.state != StateConfigInput {
		for _, log := range m.logs {
			s += log + "\n"
		}
	}

	// Dynamic Content based on State
	switch m.state {
	case StateInstallingNode, StateConfiguringNpm, StateInstallingMoltbot, StateConfiguring, StateUninstalling:
		s += fmt.Sprintf("\n%s %s\n", m.spinner.View(), style.SubtleStyle.Render("处理中..."))

	case StateConfirmInstall:
		s += fmt.Sprintf("\n%s\n", style.SubtleStyle.Render("是否强制重新安装/更新？[y/N]"))

	case StateUninstallConfirm:
		s += fmt.Sprintf("\n%s\n", style.SubtleStyle.Render("确定要卸载 Moltbot 吗？(这将删除配置文件) [y/N]"))

	case StateInstalled:
		s += fmt.Sprintf("\n%s\n", style.SuccessStyle.Render("安装完成!"))
		s += style.SubtleStyle.Render(m.installMsg) + "\n\n"
		s += style.StepStyle.Render("按 Enter 进入配置向导") + "\n"

	case StateMenu:
		s += style.HeaderStyle.Render("主菜单") + "\n\n"
		choices := []string{"启动 Moltbot 网关", "配置 Moltbot", "卸载 Moltbot", "退出"}
		for i, choice := range choices {
			cursor := " "
			if m.menuIndex == i {
				cursor = "➜"
				choice = style.HighlightStyle.Render(choice)
			}
			s += fmt.Sprintf(" %s %s\n", cursor, choice)
		}
		s += "\n" + style.SubtleStyle.Render("使用 ↑/↓ 选择，Enter 确认") + "\n"
		// Show logs below menu if desired, or keep clean
		if len(m.logs) > 0 {
			s += "\n" + style.SubtleStyle.Render("--- 安装日志 ---") + "\n"
			start := len(m.logs) - 3
			if start < 0 {
				start = 0
			}
			for _, log := range m.logs[start:] {
				s += log + "\n"
			}
		}

	case StateConfigApiSelect:
		s += style.HeaderStyle.Render("配置向导 - 选择 API 类型") + "\n\n"
		s += "1. Anthropic 官方 API\n"
		s += "2. OpenAI 兼容 API (中转站/其他模型)\n\n"
		s += style.SubtleStyle.Render("按 1 或 2 选择，Esc 返回") + "\n"

	case StateConfigInput:
		s += style.HeaderStyle.Render("配置向导") + "\n\n"

		label := ""
		switch m.configStep {
		case 0:
			label = "Telegram Bot Token:"
		case 1:
			label = "Telegram User ID (管理员):"
		case 2:
			if m.configOpts.ApiType == "anthropic" {
				label = "Anthropic API Key (sk-ant-...):"
			} else {
				label = "API Base URL (例如 https://api.example.com/v1):"
			}
		case 3:
			label = "API Key:"
		case 4:
			label = "模型名称 (例如 gpt-4o):"
		}

		s += fmt.Sprintf("%s\n\n%s\n\n", label, m.input.View())
		s += style.SubtleStyle.Render("按 Enter 确认") + "\n"
	}

	return style.AppStyle.Render(s)
}

// Commands

func checkEnvCmd() tea.Msg {
	nodeVer, nodeOk := sys.CheckNode()
	moltbotVer, moltbotInstalled := sys.CheckMoltbot()
	return checkMsg{
		nodeVer:          nodeVer,
		nodeOk:           nodeOk,
		needsNode:        !nodeOk,
		moltbotVer:       moltbotVer,
		moltbotInstalled: moltbotInstalled,
	}
}

func installNodeCmd() tea.Msg {
	err := sys.InstallNode()
	return installNodeMsg{err: err}
}

func configNpmCmd() tea.Msg {
	err := sys.ConfigureNpmMirror()
	return configNpmMsg{err: err}
}

func installMoltbotCmd() tea.Msg {
	err := sys.InstallMoltbotNpm("latest")
	if err != nil {
		return installMoltbotMsg{err: err}
	}
	ver, _ := sys.CheckMoltbot()
	return installMoltbotMsg{version: ver, err: nil}
}

func configCmd() tea.Msg {
	restart, _ := sys.EnsureOnPath()
	sys.RunDoctor()
	return configMsg{restartPath: restart, err: nil}
}

func saveConfigCmd(opts sys.ConfigOptions) tea.Cmd {
	return func() tea.Msg {
		err := sys.GenerateAndWriteConfig(opts)
		return saveConfigMsg{err: err}
	}
}

func uninstallCmd() tea.Msg {
	err := sys.UninstallMoltbot()
	return uninstallMsg{err: err}
}

func getRandomWelcomeMsg() string {
	msgs := []string{
		"所有系统准备就绪",
		"Moltbot 已就绪，随时为您服务",
		"环境配置完成，开始使用吧",
		"安装成功，期待您的使用",
	}
	return msgs[rand.Intn(len(msgs))]
}
