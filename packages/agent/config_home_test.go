package agent

import (
	"path/filepath"
	"testing"
)

func TestPuddleHomePrefersExplicitHomeOverXDGStateHome(t *testing.T) {
	t.Setenv("PUDDLE_HOME", filepath.Join("explicit", "puddle"))
	t.Setenv("XDG_STATE_HOME", filepath.Join("xdg", "state"))

	if got, want := PuddleHome(), filepath.Join("explicit", "puddle"); got != want {
		t.Fatalf("PuddleHome() = %q, want %q", got, want)
	}
}

func TestPuddleHomeUsesXDGStateHome(t *testing.T) {
	t.Setenv("PUDDLE_HOME", "")
	t.Setenv("XDG_STATE_HOME", filepath.Join("xdg", "state"))

	if got, want := PuddleHome(), filepath.Join("xdg", "state", "puddle"); got != want {
		t.Fatalf("PuddleHome() = %q, want %q", got, want)
	}
}
