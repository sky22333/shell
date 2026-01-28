package style

import "github.com/charmbracelet/lipgloss"

var (
	// Colors
	ColorPrimary   = lipgloss.Color("#7D56F4") // Purple
	ColorSecondary = lipgloss.Color("#04B575") // Green
	ColorError     = lipgloss.Color("#FF4C4C") // Red
	ColorWarning   = lipgloss.Color("#FFD700") // Gold
	ColorSubtle    = lipgloss.Color("#626262") // Gray
	ColorText      = lipgloss.Color("#FAFAFA") // White

	// Styles
	AppStyle = lipgloss.NewStyle().
			Padding(1, 2)

	HeaderStyle = lipgloss.NewStyle().
			Foreground(ColorPrimary).
			Bold(true).
			PaddingBottom(1)

	StepStyle = lipgloss.NewStyle().
			Foreground(ColorText)

	SuccessStyle = lipgloss.NewStyle().
			Foreground(ColorSecondary).
			Bold(true)

	ErrorStyle = lipgloss.NewStyle().
			Foreground(ColorError).
			Bold(true)

	WarningStyle = lipgloss.NewStyle().
			Foreground(ColorWarning)

	SubtleStyle = lipgloss.NewStyle().
			Foreground(ColorSubtle)

	CmdStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#00FFFF")).
			Padding(0, 1)

	HighlightStyle = lipgloss.NewStyle().
			Foreground(ColorSecondary).
			Bold(true)
)

func RenderStep(prefix string, msg string, status string) string {
	var statusStyle lipgloss.Style
	switch status {
	case "pending":
		statusStyle = SubtleStyle
	case "running":
		statusStyle = lipgloss.NewStyle().Foreground(ColorPrimary)
	case "done":
		statusStyle = SuccessStyle
	case "error":
		statusStyle = ErrorStyle
	default:
		statusStyle = StepStyle
	}

	return lipgloss.JoinHorizontal(lipgloss.Left,
		statusStyle.Width(3).Render(prefix),
		statusStyle.Render(msg),
	)
}
