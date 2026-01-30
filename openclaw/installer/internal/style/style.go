package style

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

// 配色方案
var (
	ColorPrimary   = lipgloss.Color("#7D56F4") // 紫色
	ColorSecondary = lipgloss.Color("#04B575") // 绿色
	ColorError     = lipgloss.Color("#FF3B30") // 红色
	ColorWarning   = lipgloss.Color("#FFCC00") // 黄色
	ColorSubtle    = lipgloss.Color("#666666") // 灰色
	ColorText      = lipgloss.Color("#E0E0E0") // 白字
	ColorHighlight = lipgloss.Color("#2A2A2A") // 深灰
	ColorPanel     = lipgloss.Color("#1E1E1E") // 面板底色
	ColorBorder    = lipgloss.Color("#333333") // 边框
)

// 基础样式
var AppStyle = lipgloss.NewStyle().
	Padding(1, 2)

// 标题样式
var HeaderStyle = lipgloss.NewStyle().
	Foreground(ColorPrimary).
	Bold(true).
	PaddingBottom(1)

var SubHeaderStyle = lipgloss.NewStyle().
	Foreground(ColorText).
	Bold(true).
	PaddingBottom(1)

var TitleStyle = lipgloss.NewStyle().
	Foreground(ColorPrimary).
	Bold(true).
	Padding(0, 1).
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorPrimary)

// 状态样式
var SuccessStyle = lipgloss.NewStyle().Foreground(ColorSecondary).Bold(true)
var ErrorStyle = lipgloss.NewStyle().Foreground(ColorError).Bold(true)
var WarningStyle = lipgloss.NewStyle().Foreground(ColorWarning)
var SubtleStyle = lipgloss.NewStyle().Foreground(ColorSubtle)

// 面板样式
var PanelStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorBorder).
	Padding(1, 2)

var FocusedPanelStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorPrimary).
	Padding(1, 2)

var WizardPanelStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorPrimary).
	Padding(1, 4).
	Width(80)

// 菜单样式
var MenuNormalStyle = lipgloss.NewStyle().
	Foreground(ColorText).
	PaddingLeft(2)

var MenuSelectedStyle = lipgloss.NewStyle().
	Foreground(ColorSecondary).
	Background(ColorHighlight).
	PaddingLeft(1).
	Bold(true).
	Border(lipgloss.NormalBorder(), false, false, false, true).
	BorderForeground(ColorSecondary)

// 输入框样式
var KeyStyle = lipgloss.NewStyle().
	Foreground(ColorPrimary).
	Bold(true)

var DescriptionStyle = lipgloss.NewStyle().
	Foreground(ColorSubtle).
	Italic(true)

var InputHelpStyle = lipgloss.NewStyle().
	Foreground(ColorSubtle).
	MarginBottom(1)

var StepStyle = lipgloss.NewStyle().
	Foreground(ColorWarning).
	Bold(true)

var InputStyle = lipgloss.NewStyle().
	Foreground(ColorText).
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorSubtle).
	Padding(0, 1)

var InputFocusedStyle = lipgloss.NewStyle().
	Foreground(ColorText).
	Border(lipgloss.RoundedBorder()).
	BorderForeground(ColorPrimary).
	Padding(0, 1)

// Badges
var BadgeBase = lipgloss.NewStyle().
	Bold(true)

var BadgeInfo = BadgeBase.
	Foreground(ColorPrimary)

var BadgeSuccess = BadgeBase.
	Foreground(ColorSecondary)

var BadgeWarning = BadgeBase.
	Foreground(ColorWarning)

var BadgeError = BadgeBase.
	Foreground(ColorError)

// Helpers
func Badge(text, status string) string {
	switch status {
	case "success":
		return BadgeSuccess.Render(text)
	case "warning":
		return BadgeWarning.Render(text)
	case "error":
		return BadgeError.Render(text)
	default:
		return BadgeInfo.Render(text)
	}
}

func Checkbox(label string, checked bool) string {
	if checked {
		return fmt.Sprintf("[%s] %s", SuccessStyle.Render("x"), label)
	}
	return fmt.Sprintf("[ ] %s", label)
}

func RenderStep(step, total int, title string) string {
	return fmt.Sprintf("%s %s",
		StepStyle.Render(fmt.Sprintf("STEP %d/%d", step, total)),
		SubHeaderStyle.Render(title),
	)
}
