// macenv-tui — seletor de itens do mac-env-setup (Fase 4 do roadmap).
// Companion do mac_env_install.sh: recebe o catálogo por arquivo, desenha o
// seletor no /dev/tty e imprime a seleção final no stdout ("ITEMS id1 id2...").
// Sai com 130 quando cancelado — o bash cai no fluxo gum.
//
// Protocolo do arquivo de catálogo (argumento 1), uma linha por registro:
//   C|id|Rótulo da categoria
//   I|id|categoria|Rótulo|0/1 (pré-selecionado)|descrição
//   P|Nome do perfil|id1 id2 id3...
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Paleta Event Horizon (idêntica ao instalador bash) ──────────────────────

var rampStops = [][3]int{
	{0x7a, 0x3b, 0x00}, // brasa
	{0xc4, 0x78, 0x00},
	{0xf5, 0xb0, 0x00}, // âmbar assinatura
	{0xff, 0xd7, 0x5e},
	{0xff, 0xf3, 0xc4}, // branco-quente
}

const (
	cAmber = lipgloss.Color("#f5b000")
	cInfo  = lipgloss.Color("#8892b0")
	cMuted = lipgloss.Color("#5a6480")
	cCyan  = lipgloss.Color("#00e5cc")
	cCrust = lipgloss.Color("#120b02")
)

var (
	stAmber    = lipgloss.NewStyle().Foreground(cAmber)
	stInfo     = lipgloss.NewStyle().Foreground(cInfo)
	stMuted    = lipgloss.NewStyle().Foreground(cMuted)
	stCyan     = lipgloss.NewStyle().Foreground(cCyan)
	stCursor   = lipgloss.NewStyle().Foreground(cCrust).Background(cAmber).Bold(true)
	stCatHead  = lipgloss.NewStyle().Foreground(cAmber).Bold(true)
	stFilter   = lipgloss.NewStyle().Foreground(cCyan)
	stSelected = lipgloss.NewStyle().Foreground(cAmber)
)

func rampColor(pos float64) lipgloss.Color {
	if pos < 0 {
		pos = 0
	}
	if pos > 1 {
		pos = 1
	}
	span := float64(len(rampStops) - 1)
	seg := int(pos * span)
	if seg >= len(rampStops)-1 {
		seg = len(rampStops) - 2
	}
	frac := pos*span - float64(seg)
	a, b := rampStops[seg], rampStops[seg+1]
	r := int(float64(a[0]) + (float64(b[0])-float64(a[0]))*frac)
	g := int(float64(a[1]) + (float64(b[1])-float64(a[1]))*frac)
	bl := int(float64(a[2]) + (float64(b[2])-float64(a[2]))*frac)
	return lipgloss.Color(fmt.Sprintf("#%02x%02x%02x", r, g, bl))
}

// gradiente por caractere com fase (espelhada) — o shimmer do instalador
func gradient(s string, phase float64) string {
	runes := []rune(s)
	if len(runes) < 2 {
		return s
	}
	var b strings.Builder
	for i, r := range runes {
		if r == ' ' {
			b.WriteRune(' ')
			continue
		}
		p := float64(i)/float64(len(runes)-1) + phase
		for p > 2 {
			p -= 2
		}
		if p > 1 {
			p = 2 - p
		}
		b.WriteString(lipgloss.NewStyle().Foreground(rampColor(p)).Render(string(r)))
	}
	return b.String()
}

// ── Catálogo ────────────────────────────────────────────────────────────────

type item struct {
	ID, Cat, Label, Desc string
}

type category struct {
	ID, Label string
}

type profile struct {
	Name  string
	Items map[string]bool
}

func parseCatalog(path string) ([]category, []item, []profile, map[string]bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	defer f.Close()
	var cats []category
	var items []item
	var profiles []profile
	sel := map[string]bool{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		parts := strings.Split(sc.Text(), "|")
		switch {
		case len(parts) >= 3 && parts[0] == "C":
			cats = append(cats, category{ID: parts[1], Label: parts[2]})
		case len(parts) >= 6 && parts[0] == "I":
			it := item{ID: parts[1], Cat: parts[2], Label: parts[3], Desc: parts[5]}
			items = append(items, it)
			if parts[4] == "1" {
				sel[it.ID] = true
			}
		case len(parts) >= 3 && parts[0] == "P":
			set := map[string]bool{}
			for _, id := range strings.Fields(parts[2]) {
				set[id] = true
			}
			profiles = append(profiles, profile{Name: parts[1], Items: set})
		}
	}
	return cats, items, profiles, sel, sc.Err()
}

// ── Modelo ──────────────────────────────────────────────────────────────────

type tickMsg struct{}

func tick() tea.Cmd {
	return tea.Tick(90*time.Millisecond, func(time.Time) tea.Msg { return tickMsg{} })
}

type model struct {
	cats      []category
	items     []item
	profiles  []profile
	sel       map[string]bool
	cursor    int // índice em visible()
	offset    int
	filter    string
	filtering bool
	width     int
	height    int
	phase     float64
	confirmed bool
	cancelled bool
}

func (m model) visible() []int {
	var out []int
	q := strings.ToLower(m.filter)
	for i, it := range m.items {
		if q == "" || strings.Contains(strings.ToLower(it.Label+" "+it.Desc+" "+it.Cat), q) {
			out = append(out, i)
		}
	}
	return out
}

func (m model) Init() tea.Cmd { return tick() }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tickMsg:
		m.phase += 0.055
		if m.phase > 2 {
			m.phase -= 2
		}
		return m, tick()
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case tea.KeyMsg:
		if m.filtering {
			switch msg.String() {
			case "esc":
				m.filtering, m.filter, m.cursor = false, "", 0
			case "enter":
				m.filtering = false
			case "backspace":
				if len(m.filter) > 0 {
					m.filter = m.filter[:len(m.filter)-1]
				}
			default:
				if msg.Type == tea.KeyRunes {
					m.filter += string(msg.Runes)
					m.cursor = 0
				}
			}
			return m, nil
		}
		vis := m.visible()
		switch msg.String() {
		case "q", "esc", "ctrl+c":
			m.cancelled = true
			return m, tea.Quit
		case "enter":
			m.confirmed = true
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(vis)-1 {
				m.cursor++
			}
		case " ":
			if len(vis) > 0 {
				id := m.items[vis[m.cursor]].ID
				m.sel[id] = !m.sel[id]
			}
		case "a":
			if len(vis) > 0 {
				cat := m.items[vis[m.cursor]].Cat
				all := true
				for _, it := range m.items {
					if it.Cat == cat && !m.sel[it.ID] {
						all = false
						break
					}
				}
				for _, it := range m.items {
					if it.Cat == cat {
						m.sel[it.ID] = !all
					}
				}
			}
		case "/":
			m.filtering = true
		default:
			s := msg.String()
			if len(s) == 1 && s[0] >= '1' && s[0] <= '9' {
				idx := int(s[0] - '1')
				if idx < len(m.profiles) {
					m.sel = map[string]bool{}
					for id := range m.profiles[idx].Items {
						m.sel[id] = true
					}
				}
			}
		}
	}
	return m, nil
}

func (m model) catLabel(id string) string {
	for _, c := range m.cats {
		if c.ID == id {
			return c.Label
		}
	}
	return id
}

func (m model) View() string {
	if m.width == 0 {
		return ""
	}
	var b strings.Builder

	// cabeçalho: anel + wordmark com shimmer
	ring := "░▒▓██████████████████████▓▒░"
	b.WriteString("  " + gradient(ring, m.phase) + "\n")
	b.WriteString("  " + gradient("◆  M A C · E N V  —  seleção  ◆", m.phase+0.3) + "\n")

	// linha de status: contagem + perfis
	n := 0
	for _, v := range m.sel {
		if v {
			n++
		}
	}
	status := fmt.Sprintf("%d selecionados", n)
	var pkeys []string
	for i, p := range m.profiles {
		pkeys = append(pkeys, fmt.Sprintf("[%d]%s", i+1, p.Name))
	}
	b.WriteString("  " + stCyan.Render(status) + "   " + stMuted.Render(strings.Join(pkeys, " ")) + "\n")
	if m.filtering || m.filter != "" {
		b.WriteString("  " + stFilter.Render("/ "+m.filter+"▌") + "\n")
	} else {
		b.WriteString("\n")
	}

	// lista com headers de categoria e scroll
	vis := m.visible()
	type row struct {
		header bool
		text   string
		visIdx int
	}
	var rows []row
	lastCat := ""
	for vi, idx := range vis {
		it := m.items[idx]
		if it.Cat != lastCat {
			rows = append(rows, row{header: true, text: "  " + stCatHead.Render("── "+m.catLabel(it.Cat)+" ──"), visIdx: -1})
			lastCat = it.Cat
		}
		mark := stMuted.Render("◇")
		label := it.Label
		if m.sel[it.ID] {
			mark = stSelected.Render("◆")
		}
		line := "   " + mark + " "
		if vi == m.cursor {
			line += stCursor.Render(" " + label + " ")
		} else if m.sel[it.ID] {
			line += stAmber.Render(label)
		} else {
			line += stInfo.Render(label)
		}
		rows = append(rows, row{text: line, visIdx: vi})
	}

	page := m.height - 9
	if page < 4 {
		page = 4
	}
	cursorRow := 0
	for i, r := range rows {
		if r.visIdx == m.cursor {
			cursorRow = i
			break
		}
	}
	offset := m.offset
	if cursorRow < offset {
		offset = cursorRow
	}
	if cursorRow >= offset+page {
		offset = cursorRow - page + 1
	}
	end := offset + page
	if end > len(rows) {
		end = len(rows)
	}
	for _, r := range rows[offset:end] {
		b.WriteString(r.text + "\n")
	}
	for i := end - offset; i < page; i++ {
		b.WriteString("\n")
	}

	// rodapé: descrição do item atual + teclas
	desc := ""
	if len(vis) > 0 && m.cursor < len(vis) {
		desc = m.items[vis[m.cursor]].Desc
	}
	b.WriteString("  " + stInfo.Render(desc) + "\n")
	b.WriteString("  " + stMuted.Render("espaço marca · a categoria · / busca · 1-9 perfis · enter confirma · q sai") + "\n")
	return b.String()
}

// ── Main ────────────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "uso: macenv-tui <arquivo-catalogo>")
		os.Exit(2)
	}
	cats, items, profiles, sel, err := parseCatalog(os.Args[1])
	if err != nil || len(items) == 0 {
		fmt.Fprintln(os.Stderr, "catálogo inválido:", err)
		os.Exit(2)
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "sem /dev/tty:", err)
		os.Exit(2)
	}
	defer tty.Close()

	m := model{cats: cats, items: items, profiles: profiles, sel: sel}
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithInput(tty), tea.WithOutput(tty))
	final, err := p.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "erro no TUI:", err)
		os.Exit(2)
	}
	fm := final.(model)
	if fm.cancelled || !fm.confirmed {
		os.Exit(130)
	}
	var out []string
	for _, it := range items { // preserva a ordem do catálogo
		if fm.sel[it.ID] {
			out = append(out, it.ID)
		}
	}
	fmt.Println("ITEMS " + strings.Join(out, " "))
}
