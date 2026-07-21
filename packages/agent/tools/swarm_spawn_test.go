package tools

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/puddle-dev/puddle/packages/agent/swarm"
	"github.com/puddle-dev/puddle/packages/provider"
)

type noopSwarmRunner struct{}

func (noopSwarmRunner) Run(context.Context, swarm.Sink) error { return nil }

func newTestSwarm(t *testing.T) *swarm.Swarm {
	t.Helper()
	root := t.TempDir()
	return swarm.New(swarm.Config{
		Root:     filepath.Join(root, "swarm"),
		RepoRoot: root,
		NewRunner: func(*swarm.Agent) swarm.Runner {
			return noopSwarmRunner{}
		},
	})
}

func TestSwarmSpawnInheritsHostModelAndProviderWhenOmitted(t *testing.T) {
	tool := &SwarmSpawnTool{
		Swarm:           newTestSwarm(t),
		Enabled:         func() bool { return true },
		DefaultModel:    func() string { return "gpt-5" },
		DefaultProvider: func() string { return "openai-codex" },
	}

	res, err := tool.Execute(context.Background(), json.RawMessage(`{"task":"research docs"}`), nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.IsError {
		t.Fatalf("unexpected tool error: %s", textResult(res.Content))
	}
	details, ok := res.Details.(map[string]any)
	if !ok {
		t.Fatalf("details type = %T, want map[string]any", res.Details)
	}
	if got := details["model"]; got != "gpt-5" {
		t.Fatalf("model detail = %v, want gpt-5", got)
	}
	if got := details["provider"]; got != "openai-codex" {
		t.Fatalf("provider detail = %v, want openai-codex", got)
	}
	text := textResult(res.Content)
	if !strings.Contains(text, "model: gpt-5") || !strings.Contains(text, "provider: openai-codex") {
		t.Fatalf("result text missing inherited model/provider:\n%s", text)
	}

	agents := tool.Swarm.List()
	if len(agents) != 1 {
		t.Fatalf("spawned agents = %d, want 1", len(agents))
	}
	if agents[0].Model != "gpt-5" || agents[0].Provider != "openai-codex" {
		t.Fatalf("agent model/provider = %q/%q, want gpt-5/openai-codex", agents[0].Model, agents[0].Provider)
	}
}

func TestSwarmSpawnRejectsPartialModelProviderOverride(t *testing.T) {
	tool := &SwarmSpawnTool{
		Swarm:           newTestSwarm(t),
		Enabled:         func() bool { return true },
		DefaultModel:    func() string { return "gpt-5" },
		DefaultProvider: func() string { return "openai-codex" },
	}

	res, err := tool.Execute(context.Background(), json.RawMessage(`{"task":"research docs","provider":"openai"}`), nil)
	if err != nil {
		t.Fatal(err)
	}
	if !res.IsError {
		t.Fatalf("expected partial override to fail")
	}
	if got := textResult(res.Content); !strings.Contains(got, "omit both model/provider") {
		t.Fatalf("error text = %q", got)
	}
	if got := len(tool.Swarm.List()); got != 0 {
		t.Fatalf("spawned agents = %d, want 0", got)
	}
}

func textResult(content []provider.Content) string {
	if len(content) == 0 {
		return ""
	}
	if tb, ok := content[0].(provider.TextBlock); ok {
		return tb.Text
	}
	return ""
}
