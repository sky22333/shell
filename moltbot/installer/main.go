package main

import (
	"fmt"
	"os"

	"moltbot-installer/internal/ui"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	p := tea.NewProgram(ui.InitialModel())
	m, err := p.Run()
	if err != nil {
		fmt.Printf("启动失败: %v\n", err)
		os.Exit(1)
	}

	if model, ok := m.(ui.Model); ok {
		if model.DidStartGateway {
			fmt.Println("Web 控制台: http://127.0.0.1:18789/")
		}
	}

	fmt.Println("\n按 Enter 键退出...")
	fmt.Scanln()
}
