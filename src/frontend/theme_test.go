// Tests for the UI customizations: dark mode toggle, Customize UI panel and
// the owner credit. They render the real templates, so a broken template
// fails CI before an image is built.
package main

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func renderHeader(t *testing.T) string {
	t.Helper()
	var buf bytes.Buffer
	data := map[string]interface{}{"baseUrl": "", "show_currency": false}
	if err := templates.ExecuteTemplate(&buf, "header", data); err != nil {
		t.Fatalf("rendering header: %v", err)
	}
	return buf.String()
}

func TestHeaderHasDarkModeToggle(t *testing.T) {
	out := renderHeader(t)
	for _, want := range []string{`id="ob-dark-toggle"`, `role="switch"`, `/static/js/theme.js`, `/static/styles/theme.css`} {
		if !strings.Contains(out, want) {
			t.Errorf("header missing %q", want)
		}
	}
}

func TestHeaderHasCustomizePanel(t *testing.T) {
	out := renderHeader(t)
	for _, want := range []string{`id="ob-customize-btn"`, `data-setting="color"`, `data-setting="density"`, `data-setting="font"`, `data-setting="cols"`, `id="ob-reset"`} {
		if !strings.Contains(out, want) {
			t.Errorf("header missing %q", want)
		}
	}
	for _, theme := range []string{"default", "ocean", "sunset", "forest"} {
		if !strings.Contains(out, `data-value="`+theme+`"`) {
			t.Errorf("color theme %q missing from panel", theme)
		}
	}
}

func TestOwnerCreditOnEveryHeaderPage(t *testing.T) {
	out := renderHeader(t)
	if !strings.Contains(out, "ALIYAN MALIK") {
		t.Error("owner credit missing from header output")
	}
	if strings.Count(out, "ALIYAN MALIK") != 1 {
		t.Error("owner name should appear exactly once per page")
	}
}

func TestThemeAssetsExist(t *testing.T) {
	for _, f := range []string{"static/styles/theme.css", "static/js/theme.js"} {
		if _, err := os.Stat(f); err != nil {
			t.Errorf("missing asset %s: %v", f, err)
		}
	}
}
