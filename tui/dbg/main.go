package main

import (
	"fmt"
	"os"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

var early = lipgloss.NewStyle().Foreground(lipgloss.Color("#f5b000"))

func main() {
	lipgloss.SetColorProfile(termenv.TrueColor)
	late := lipgloss.NewStyle().Foreground(lipgloss.Color("#f5b000"))
	fmt.Fprintf(os.Stderr, "estilo criado ANTES do SetColorProfile: %q\n", early.Render("X"))
	fmt.Fprintf(os.Stderr, "estilo criado DEPOIS: %q\n", late.Render("X"))
}
