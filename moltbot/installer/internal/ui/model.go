package ui

import (
	"fmt"
	"strings"
	"time"

	"moltbot-installer/internal/style"
	"moltbot-installer/internal/sys"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// 会话状态
type SessionState int

const (
	StateDashboard SessionState = iota
	StateWizard
	StateAction
)

// 向导子状态
type WizardStep int

const (
	StepApiSelect WizardStep = iota
	StepApiInput
	StepConfirm
)

type ActionType int

const (
	ActionCheckEnv ActionType = iota
	ActionInstall
	ActionUninstall
	ActionStartGateway
	ActionKillGateway
)

// 主程序模型
type Model struct {
	// 全局状态
	state  SessionState
	width  int
	height int
	
	// 启动标志
	DidStartGateway bool

	// 仪表盘状态
	menuIndex int

	// 向导状态
	wizardStep WizardStep
	configOpts sys.ConfigOptions
	input      textinput.Model
	inputStep  int // 当前输入步骤

	// 动作/进度状态
	actionType  ActionType
	spinner     spinner.Model
	progressMsg string
	actionErr   error
	actionDone  bool

	// 系统状态缓存
	nodeVer    string
	nodeOk     bool
	moltbotVer string
	moltbotOk  bool
	gitVer     string
	gitOk      bool
	gatewayOk  bool
	checkDone  bool

	envRefreshActive          bool
	envRefreshAttempt         int
	envRefreshMax             int
	envRefreshExpectInstalled bool
}

// 消息定义
type checkMsg struct {
	nodeVer          string
	nodeOk           bool
	moltbotVer       string
	moltbotInstalled bool
	gitVer           string
	gitOk            bool
	gatewayRunning   bool
}

type actionResultMsg struct {
	err error
}

type progressMsg string

type tickMsg time.Time

type gatewayStatusMsg bool
type envRefreshMsg int

func InitialModel() Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = style.HeaderStyle

	ti := textinput.New()
	ti.Cursor.Style = style.HeaderStyle
	ti.Focus()

	return Model{
		state:     StateDashboard,
		spinner:   s,
		input:     ti,
		menuIndex: 0,
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		checkEnvCmd,
		tickCmd(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
		// 向导模式返回
		if m.state == StateWizard && msg.String() == "esc" {
			m.state = StateDashboard
			return m, nil
		}
		// 动作结果确认返回
		if m.state == StateAction && m.actionDone && (msg.String() == "enter" || msg.String() == "esc") {
			m.state = StateDashboard
			// 刷新环境
			return m, checkEnvCmd
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case checkMsg:
		m.nodeVer = msg.nodeVer
		m.nodeOk = msg.nodeOk
		m.moltbotVer = msg.moltbotVer
		m.moltbotOk = msg.moltbotInstalled
		m.gitVer = msg.gitVer
		m.gitOk = msg.gitOk
		m.gatewayOk = msg.gatewayRunning
		m.checkDone = true
		if m.envRefreshActive {
			expect := m.envRefreshExpectInstalled
			if m.nodeOk == expect && m.gitOk == expect && m.moltbotOk == expect {
				m.envRefreshActive = false
			}
		}

		// 如果在动作模式下检查环境，可能需要切回主菜单
		if m.state == StateAction && m.actionType == ActionCheckEnv {
			m.state = StateDashboard
		}
		return m, nil

	case progressMsg:
		m.progressMsg = string(msg)
		return m, nil

	case tickMsg:
		return m, tea.Batch(checkGatewayCmd, tickCmd())

	case gatewayStatusMsg:
		m.gatewayOk = bool(msg)
		return m, nil

	case actionResultMsg:
		m.actionErr = msg.err
		m.actionDone = true
		if msg.err == nil {
			m.progressMsg = "操作成功完成！"
			if m.actionType == ActionStartGateway {
				m.DidStartGateway = true
			}
			if m.actionType == ActionInstall || m.actionType == ActionUninstall {
				m.envRefreshActive = true
				m.envRefreshAttempt = 0
				m.envRefreshMax = 5
				m.envRefreshExpectInstalled = m.actionType == ActionInstall
				return m, envRefreshCmd(0)
			}
		} else {
			m.progressMsg = fmt.Sprintf("操作失败: %v", msg.err)
		}
		return m, nil

	case envRefreshMsg:
		if !m.envRefreshActive {
			return m, nil
		}
		attempt := int(msg)
		m.envRefreshAttempt = attempt
		cmds := []tea.Cmd{checkEnvCmd}
		if attempt+1 < m.envRefreshMax {
			cmds = append(cmds, envRefreshCmd(attempt+1))
		}
		return m, tea.Batch(cmds...)
	}

	// 状态更新
	switch m.state {
	case StateDashboard:
		return m.updateDashboard(msg)
	case StateWizard:
		return m.updateWizard(msg)
	case StateAction:
		// 动作模式下主要等待消息
		return m, nil
	}

	return m, nil
}

func (m Model) updateDashboard(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.menuIndex > 0 {
				m.menuIndex--
			}
		case "down", "j":
			if m.menuIndex < 4 { // 5个选项 (0-4)
				m.menuIndex++
			}
		case "enter":
			return m.handleMenuSelect()
		case "q":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m Model) handleMenuSelect() (tea.Model, tea.Cmd) {
	switch m.menuIndex {
	case 0: // 启动/重启网关
		m.state = StateAction
		m.actionDone = false
		m.actionErr = nil
		if m.gatewayOk {
			m.actionType = ActionKillGateway
			m.progressMsg = "正在停止网关..."
			return m, runKillGatewayCmd
		} else {
			m.actionType = ActionStartGateway
			m.progressMsg = "正在启动网关..."
			return m, runStartGatewayCmd
		}
	case 1: // 配置
		m.state = StateWizard
		m.wizardStep = StepApiSelect
		m.configOpts = sys.ConfigOptions{}
		return m, nil
	case 2: // 安装/更新
		m.state = StateAction
		m.actionType = ActionInstall
		m.actionDone = false
		m.actionErr = nil
		m.progressMsg = "准备安装..."
		return m, runInstallFlowCmd
	case 3: // 卸载
		m.state = StateAction
		m.actionType = ActionUninstall
		m.actionDone = false
		m.actionErr = nil
		m.progressMsg = "正在卸载..."
		return m, runUninstallCmd
	case 4: // 退出
		return m, tea.Quit
	}
	return m, nil
}

func (m Model) updateWizard(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch m.wizardStep {
	case StepApiSelect:
		if k, ok := msg.(tea.KeyMsg); ok {
			switch k.String() {
			case "1":
				m.configOpts.ApiType = "anthropic"
				m.wizardStep = StepApiInput
				m.inputStep = 0
				m.input.Placeholder = "sk-ant-api03-..."
				m.input.EchoMode = textinput.EchoPassword
				m.input.SetValue("")
			case "2":
				m.configOpts.ApiType = "openai"
				m.wizardStep = StepApiInput
				m.inputStep = 0
				m.input.Placeholder = "https://api.openai.com/v1"
				m.input.EchoMode = textinput.EchoNormal
				m.input.SetValue("")
			}
		}

	case StepApiInput:
		switch k := msg.(type) {
		case tea.KeyMsg:
			if k.String() == "enter" {
				val := m.input.Value()
				// 处理 Anthropic 或 OpenAI 流程
				isAnthropic := m.configOpts.ApiType == "anthropic"

				if isAnthropic {
					switch m.inputStep {
					case 0: // Key
						m.configOpts.AnthropicKey = val
						m.inputStep++
						m.input.Placeholder = "123456:ABC-DEF..."
						m.input.EchoMode = textinput.EchoNormal
						m.input.SetValue("")
					case 1: // Bot Token
						m.configOpts.BotToken = val
						m.inputStep++
						m.input.Placeholder = "123456789"
						m.input.SetValue("")
					case 2: // Admin ID
						m.configOpts.AdminID = val
						m.wizardStep = StepConfirm
					}
				} else { // OpenAI
					switch m.inputStep {
					case 0: // Base URL
						m.configOpts.OpenAIBaseURL = val
						m.inputStep++
						m.input.Placeholder = "sk-..."
						m.input.EchoMode = textinput.EchoPassword
						m.input.SetValue("")
					case 1: // Key
						m.configOpts.OpenAIKey = val
						m.inputStep++
						m.input.Placeholder = "gpt-4o / claude-3-5-sonnet"
						m.input.EchoMode = textinput.EchoNormal
						m.input.SetValue("")
					case 2: // Model
						m.configOpts.OpenAIModel = val
						m.inputStep++
						m.input.Placeholder = "123456:ABC-DEF..."
						m.input.SetValue("")
					case 3: // Bot Token
						m.configOpts.BotToken = val
						m.inputStep++
						m.input.Placeholder = "123456789"
						m.input.SetValue("")
					case 4: // Admin ID
						m.configOpts.AdminID = val
						m.wizardStep = StepConfirm
					}
				}
				return m, nil
			}
		}
		m.input, cmd = m.input.Update(msg)
		return m, cmd

	case StepConfirm:
		if k, ok := msg.(tea.KeyMsg); ok {
			if k.String() == "enter" {
				// 执行保存
				m.state = StateAction
				m.actionDone = false
				m.actionErr = nil
				m.progressMsg = "正在保存配置..."
				return m, runSaveConfigCmd(m.configOpts)
			}
		}
	}
	return m, nil
}

// 视图渲染
func (m Model) View() string {
	if m.width == 0 {
		return "加载中..."
	}

	switch m.state {
	case StateDashboard:
		return m.renderDashboard()
	case StateWizard:
		return m.renderWizard()
	case StateAction:
		return m.renderAction()
	}
	return ""
}

func (m Model) renderDashboard() string {
	// 1. 标题
	header := style.HeaderStyle.Render("Moltbot Installer")

	// 2. 状态栏
	nodeStatus := style.Badge("检测中...", "info")
	if m.checkDone {
		if m.nodeOk {
			nodeStatus = style.Badge(m.nodeVer, "success")
		} else {
			nodeStatus = style.Badge("缺失", "error")
		}
	}

	moltStatus := style.Badge("检测中...", "info")
	if m.checkDone {
		if m.moltbotOk {
			ver := m.moltbotVer
			if ver == "" {
				ver = "已安装"
			}
			moltStatus = style.Badge(ver, "success")
		} else {
			moltStatus = style.Badge("未安装", "warning")
		}
	}

	gitStatus := style.Badge("检测中...", "info")
	if m.checkDone {
		if m.gitOk {
			ver := m.gitVer
			// 清理版本字符串 "git version 2.x.y..."
			ver = strings.Replace(ver, "git version ", "", 1)
			gitStatus = style.Badge(ver, "success")
		} else {
			gitStatus = style.Badge("缺失", "warning")
		}
	}

	gwStatus := style.Badge("...", "info")
	if m.checkDone {
		if m.gatewayOk {
			gwStatus = style.Badge("运行中", "success")
		} else {
			gwStatus = style.Badge("已停止", "warning")
		}
	}

	statusPanel := style.PanelStyle.Render(lipgloss.JoinVertical(lipgloss.Left,
		style.SubHeaderStyle.Render("系统状态"),
		fmt.Sprintf("Node.js 环境:  %s", nodeStatus),
		fmt.Sprintf("Git 环境:      %s", gitStatus),
		fmt.Sprintf("Moltbot 核心:  %s", moltStatus),
		fmt.Sprintf("网关进程:      %s", gwStatus),
	))

	// 3. 菜单
	menuItems := []struct{ title, desc string }{
		{"启动/重启服务", "管理后台网关进程"},
		{"配置向导", "设置 API 密钥与机器人参数"},
		{"安装/更新环境", "一键部署 Node.js 与核心组件"},
		{"卸载 Moltbot", "清理所有文件与配置"},
		{"退出", "关闭控制台"},
	}

	// 动态切换文本
	if m.gatewayOk {
		menuItems[0].title = "重启服务"
		menuItems[0].desc = "停止当前进程并重新启动"
	} else {
		menuItems[0].title = "启动服务"
		menuItems[0].desc = "启动后台网关进程"
	}

	var menuView string
	for i, item := range menuItems {
		if i == m.menuIndex {
			menuView += style.MenuSelectedStyle.Render(fmt.Sprintf("%s\n%s", item.title, style.DescriptionStyle.Render(item.desc)))
		} else {
			menuView += style.MenuNormalStyle.Render(item.title)
		}
		menuView += "\n\n"
	}

	menuPanel := style.FocusedPanelStyle.Render(lipgloss.JoinVertical(lipgloss.Left,
		style.SubHeaderStyle.Render("主菜单"),
		menuView,
		style.SubtleStyle.Render("使用 ↑/↓ 选择，Enter 确认"),
	))

	// 4. 布局
	if m.width > 100 {
		// 并排
		return style.AppStyle.Render(lipgloss.JoinVertical(lipgloss.Left,
			header,
			"",
			lipgloss.JoinHorizontal(lipgloss.Top, statusPanel, "   ", menuPanel),
		))
	}

	// 垂直堆叠
	return style.AppStyle.Render(lipgloss.JoinVertical(lipgloss.Left,
		header,
		"",
		statusPanel,
		"",
		menuPanel,
	))
}

func (m Model) renderWizard() string {
	var content string

	switch m.wizardStep {
	case StepApiSelect:
		content = lipgloss.JoinVertical(lipgloss.Left,
			style.SubHeaderStyle.Render("Step 1: 选择 API 提供商"),
			"",
			style.MenuNormalStyle.Render("[1] Anthropic 官方 API (推荐)"),
			style.DescriptionStyle.Render("    直接连接 Claude 服务，最稳定"),
			"",
			style.MenuNormalStyle.Render("[2] OpenAI 兼容 API"),
			style.DescriptionStyle.Render("    支持 DeepSeek, GPT-4 等第三方模型"),
			"",
			style.SubtleStyle.Render("按 1 或 2 选择，Esc 返回"),
		)
	case StepApiInput:
		label := "配置项"
		if m.configOpts.ApiType == "anthropic" {
			switch m.inputStep {
			case 0:
				label = "Anthropic API Key"
			case 1:
				label = "Telegram Bot Token (可选)"
			case 2:
				label = "Telegram 账户ID (可选)"
			}
		} else {
			switch m.inputStep {
			case 0:
				label = "API 地址"
			case 1:
				label = "API Key"
			case 2:
				label = "模型名称"
			case 3:
				label = "Telegram Bot Token (可选)"
			case 4:
				label = "Telegram 账户ID (可选)"
			}
		}

		var extraHelp string
		if strings.Contains(label, "(可选)") {
			extraHelp = style.InputHelpStyle.Render("如无需配置，请直接按 Enter 跳过。")
		}

		content = lipgloss.JoinVertical(lipgloss.Left,
			style.SubHeaderStyle.Render("Step 2: 录入凭证"),
			"",
			style.InputHelpStyle.Render("请在下方输入您的 "+label+"。"),
			style.InputHelpStyle.Render("支持使用 Ctrl+V  或 鼠标右键粘贴内容。"),
			extraHelp,
			"",
			style.TitleStyle.Render(label),
			"",
			style.InputFocusedStyle.Render(m.input.View()),
			"",
			style.DescriptionStyle.Render("示例格式: "+m.input.Placeholder),
			"",
			style.SubtleStyle.Render("Enter 下一步"),
		)
	case StepConfirm:
		content = lipgloss.JoinVertical(lipgloss.Left,
			style.SubHeaderStyle.Render("Step 3: 确认配置"),
			"",
			"配置已就绪，准备写入文件。",
			style.DescriptionStyle.Render("路径: ~/.clawdbot/clawdbot.json"),
			"",
			style.SubtleStyle.Render("Enter 确认写入，Esc 取消"),
		)
	}

	return style.AppStyle.Render(style.WizardPanelStyle.Render(content))
}

func (m Model) renderAction() string {
	icon := m.spinner.View()
	title := "正在处理..."

	if m.actionDone {
		icon = "✅"
		if m.actionErr != nil {
			icon = "❌"
			title = "操作失败"
		} else {
			title = "操作完成"
		}
	}

	content := lipgloss.JoinVertical(lipgloss.Center,
		style.SubHeaderStyle.Render(title),
		"",
		fmt.Sprintf("%s %s", icon, m.progressMsg),
		"",
	)

	if m.actionDone {
		content = lipgloss.JoinVertical(lipgloss.Center, content, style.SubtleStyle.Render("按 Enter 返回主菜单"))
	}

	return style.AppStyle.Render(style.PanelStyle.Render(content))
}

// 指令处理

func checkEnvCmd() tea.Msg {
	sys.ResetPathCache()
	nodeVer, nodeOk := sys.CheckNode()
	moltVer, moltOk := sys.CheckMoltbot()
	gitVer, gitOk := sys.CheckGit()
	gwRun := sys.IsGatewayRunning()
	return checkMsg{
		nodeVer:          nodeVer,
		nodeOk:           nodeOk,
		moltbotVer:       moltVer,
		moltbotInstalled: moltOk,
		gitVer:           gitVer,
		gitOk:            gitOk,
		gatewayRunning:   gwRun,
	}
}

func envRefreshDelay(attempt int) time.Duration {
	delay := 300 * time.Millisecond
	for i := 0; i < attempt; i++ {
		delay *= 2
		if delay > 3*time.Second {
			return 3 * time.Second
		}
	}
	return delay
}

func envRefreshCmd(attempt int) tea.Cmd {
	return tea.Tick(envRefreshDelay(attempt), func(t time.Time) tea.Msg {
		return envRefreshMsg(attempt)
	})
}

func runStartGatewayCmd() tea.Msg {
	sys.StartGateway()
	time.Sleep(1 * time.Second) // 等待启动
	return actionResultMsg{err: nil}
}

func runKillGatewayCmd() tea.Msg {
	sys.KillGateway()
	time.Sleep(1 * time.Second)
	return actionResultMsg{err: nil}
}

func runUninstallCmd() tea.Msg {
	// 1. 尝试停止网关
	_ = sys.KillGateway()
	time.Sleep(1 * time.Second)

	// 2. 卸载文件
	err := sys.UninstallMoltbot()
	return actionResultMsg{err: err}
}

func runSaveConfigCmd(opts sys.ConfigOptions) tea.Cmd {
	return func() tea.Msg {
		err := sys.GenerateAndWriteConfig(opts)
		return actionResultMsg{err: err}
	}
}

func runInstallFlowCmd() tea.Msg {
	// 线性流程: 检查Node -> 安装Node -> 检查Git -> 安装Git -> 配置NPM -> 安装Moltbot -> 配置系统
	// 为简化状态，使用阻塞执行

	err := sys.InstallNode()
	if err != nil {
		return actionResultMsg{err: fmt.Errorf("node.js 安装失败: %v", err)}
	}

	err = sys.InstallGit()
	if err != nil {
		return actionResultMsg{err: fmt.Errorf("git 安装失败: %v", err)}
	}

	err = sys.ConfigureNpmMirror()
	if err != nil {
		return actionResultMsg{err: fmt.Errorf("npm 配置失败: %v", err)}
	}

	err = sys.InstallMoltbotNpm("latest")
	if err != nil {
		return actionResultMsg{err: fmt.Errorf("moltbot 安装失败: %v", err)}
	}

	_, err = sys.EnsureOnPath()
	if err != nil {
		// 非致命错误
	}

	sys.RunDoctor()

	return actionResultMsg{err: nil}
}

func tickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func checkGatewayCmd() tea.Msg {
	return gatewayStatusMsg(sys.IsGatewayRunning())
}
