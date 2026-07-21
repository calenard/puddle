package telegram

import "testing"

func TestIsStopCommand(t *testing.T) {
	tests := []struct {
		text string
		want bool
	}{
		{"stop", true},
		{" STOP ", true},
		{"Stop", true},
		{"/stop", false}, // handled by the slash-command switch
		{"stop please", false},
		{"please stop", false},
		{"", false},
	}
	for _, tt := range tests {
		if got := isStopCommand(tt.text); got != tt.want {
			t.Fatalf("isStopCommand(%q) = %v, want %v", tt.text, got, tt.want)
		}
	}
}
