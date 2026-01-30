package main

import (
	"fmt"
	"os"

	"openclaw-installer/internal/ui"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	p := tea.NewProgram(ui.InitialModel())
	if _, err := p.Run(); err != nil {
		fmt.Printf("启动失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("\n按 Enter 键退出...")
	fmt.Scanln()
}
