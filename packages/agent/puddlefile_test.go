package agent

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/erdium/puddle/packages/agent/tools"
)

func writeTestPuddlefile(t *testing.T, manifest string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), []byte(manifest), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "AGENT.md"), []byte("Be useful."), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestLoadPuddlefileRejectsUnenforcedPermissions(t *testing.T) {
	for _, field := range []string{
		`"net":{"allow":["example.com"]}`,
		`"env":{"read":["HOME"]}`,
	} {
		dir := writeTestPuddlefile(t, `{"puddlefile":1,"name":"test","permissions":{`+field+`}}`)
		if _, _, err := loadPuddlefile(dir); err == nil {
			t.Fatalf("manifest with %s was accepted", field)
		}
	}
}

func TestLoadPuddlefileRejectsUnsafeOrCollidingNames(t *testing.T) {
	for _, name := range []string{"...", "Name", "two words", "a/b"} {
		dir := writeTestPuddlefile(t, `{"puddlefile":1,"name":"`+name+`"}`)
		if _, _, err := loadPuddlefile(dir); err == nil {
			t.Fatalf("unsafe manifest name %q was accepted", name)
		}
	}
}

func TestLoadPuddlefileRejectsBundledExecutableExtension(t *testing.T) {
	dir := writeTestPuddlefile(t, `{"puddlefile":1,"name":"test"}`)
	ext := filepath.Join(dir, "extensions", "bad")
	if err := os.MkdirAll(ext, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ext, "extension.json"), []byte(`{"name":"bad"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := loadPuddlefile(dir); err == nil || !strings.Contains(err.Error(), "cannot yet be confined") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestCheckPuddlefileMinVersion(t *testing.T) {
	var zf puddlefileLoaded
	zf.Manifest.Runtime.MinPuddle = "0.3.0"
	if err := checkPuddlefileRequirements(zf, "0.2.75"); err == nil {
		t.Fatal("old puddle version accepted")
	}
	if err := checkPuddlefileRequirements(zf, "0.3.0"); err != nil {
		t.Fatalf("minimum version rejected: %v", err)
	}
}

func TestApplyPuddlefileModelRequirementsRejectsUnsupportedFields(t *testing.T) {
	var m PuddlefileManifest
	m.Model.MinTier = "frontier"
	if err := applyPuddlefileModelRequirements(&Args{}, m); err == nil {
		t.Fatal("unsupported min_tier was ignored")
	}
	m.Model.MinTier = ""
	m.Model.Requires = []string{"audio"}
	if err := applyPuddlefileModelRequirements(&Args{}, m); err == nil {
		t.Fatal("unsupported capability was ignored")
	}
}

func TestUntarRejectsTraversalAndOversizedEntry(t *testing.T) {
	makeTar := func(name string, size int64) []byte {
		var buf bytes.Buffer
		tw := tar.NewWriter(&buf)
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o600, Size: size}); err != nil {
			t.Fatal(err)
		}
		_ = tw.Close()
		return buf.Bytes()
	}
	if err := untar(bytes.NewReader(makeTar("../escape", 0)), t.TempDir()); err == nil {
		t.Fatal("path traversal accepted")
	}
	if err := untar(bytes.NewReader(makeTar("large", maxPuddlefileEntrySize+1)), t.TempDir()); err == nil {
		t.Fatal("oversized entry accepted")
	}
}

func TestParseGitHubAgentURL(t *testing.T) {
	tests := []struct {
		input                 string
		owner, repo, ref, dir string
	}{
		{"https://github.com/erdium/agents/puddle-maintenance", "erdium", "agents", "HEAD", "puddle-maintenance"},
		{"https://github.com/erdium/agents/tree/main/puddle-maintenance", "erdium", "agents", "main", "puddle-maintenance"},
		{"https://github.com/acme/agent.git", "acme", "agent", "HEAD", ""},
	}
	for _, tt := range tests {
		u, err := url.Parse(tt.input)
		if err != nil {
			t.Fatal(err)
		}
		owner, repo, ref, dir, err := parseGitHubAgentURL(u)
		if err != nil {
			t.Fatalf("parse %s: %v", tt.input, err)
		}
		if owner != tt.owner || repo != tt.repo || ref != tt.ref || dir != tt.dir {
			t.Fatalf("parse %s = %q, %q, %q, %q", tt.input, owner, repo, ref, dir)
		}
	}
}

func TestLoadRemotePuddlefileDownloadsTemporaryGitHubArchive(t *testing.T) {
	var archive bytes.Buffer
	gz := gzip.NewWriter(&archive)
	tw := tar.NewWriter(gz)
	files := map[string]string{
		"agents-main/puddle-maintenance/manifest.json": `{"puddlefile":1,"name":"puddle-maintenance"}`,
		"agents-main/puddle-maintenance/AGENT.md":      "Maintain puddle.",
	}
	for name, content := range files {
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o600, Size: int64(len(content))}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/gzip")
		_, _ = w.Write(archive.Bytes())
	}))
	defer server.Close()
	oldArchiveURL := githubArchiveURL
	githubArchiveURL = func(_, _, _ string) string { return server.URL }
	t.Cleanup(func() { githubArchiveURL = oldArchiveURL })

	u, _ := url.Parse("https://github.com/erdium/agents/puddle-maintenance")
	zf, cleanup, err := loadRemotePuddlefile(u)
	if err != nil {
		t.Fatal(err)
	}
	if zf.Manifest.Name != "puddle-maintenance" || !zf.Temp {
		t.Fatalf("unexpected puddlefile: %+v", zf)
	}
	root := filepath.Dir(filepath.Dir(zf.Dir))
	cleanup()
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("temporary checkout was not removed: %v", err)
	}
}

func TestPermissionSummaryShowsDeniedScopes(t *testing.T) {
	got := permissionSummary(tools.PermissionSet{})
	if !strings.Contains(got, "fs read: none") || !strings.Contains(got, "fs write: none") {
		t.Fatalf("summary did not show denied scopes:\n%s", got)
	}
}
