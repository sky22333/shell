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
		fmt.Printf("Error starting installer: %v\n", err)
		os.Exit(1)
	}

	if model, ok := m.(ui.Model); ok {
		if model.DidStartGateway {
			fmt.Println("Web Console: http://127.0.0.1:18789/")
		}
	}
}
