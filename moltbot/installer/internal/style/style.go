package style

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

// Colors Palette - Modern & Professional
var (
	ColorPrimary   = lipgloss.Color("#7D56F4") // Purple
	ColorSecondary = lipgloss.Color("#04B575") // Green
	ColorError     = lipgloss.Color("#FF3B30") // Red
	ColorWarning   = lipgloss.Color("#FFCC00") // Yellow
	ColorSubtle    = lipgloss.Color("#666666") // Grey
	ColorText      = lipgloss.Color("#E0E0E0") // White-ish
	ColorHighlight = lipgloss.Color("#2A2A2A") // Dark Grey
	ColorPanel     = lipgloss.Color("#1E1E1E") // Panel BG
	ColorBorder    = lipgloss.Color("#333333") // Border
)

// Base App Style
var AppStyle = lipgloss.NewStyle().
	Padding(1, 2)

// Headers
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

// Status Colors
var SuccessStyle = lipgloss.NewStyle().Foreground(ColorSecondary).Bold(true)
var ErrorStyle = lipgloss.NewStyle().Foreground(ColorError).Bold(true)
var WarningStyle = lipgloss.NewStyle().Foreground(ColorWarning)
var SubtleStyle = lipgloss.NewStyle().Foreground(ColorSubtle)

// Panels
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

// Menu Styles
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

// Input & Form Styles
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
