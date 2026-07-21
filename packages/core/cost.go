package core

import "github.com/puddle-dev/puddle/packages/provider"

// CostTracker accumulates usage across turns in a session.
//
// Total is the cumulative usage shown in the status bar's "$x.xx"
// readout. LastTurn is the per-turn usage of the most recent
// completed turn; the TUI uses LastTurn.InputTokens+cache as a
// proxy for "current context size" so the X%/Ymax gauge tracks the
// prompt size that just went to the model.
type CostTracker struct {
	Total    provider.Usage
	LastTurn provider.Usage
}

// Add folds u into the running total, records u as the last-turn
// snapshot, and returns the new cumulative value.
func (c *CostTracker) Add(u provider.Usage) provider.Usage {
	c.Total = c.Total.Add(u)
	c.LastTurn = u
	return c.Total
}
