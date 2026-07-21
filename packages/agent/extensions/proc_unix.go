//go:build !windows

package extensions

import (
	"os/exec"
	"syscall"
)

// isolateExtensionProcess moves extension subprocesses out of puddle's
// foreground process group. Some terminals, including kitty, inspect
// foreground-process-group members when deciding the cwd for "open new
// tab/split here". Extensions run with cmd.Dir set to their own install
// directory, so leaving them in puddle's process group can make the terminal
// believe the tab cwd is an extension directory even after puddle reports the
// project cwd with OSC 7.
func isolateExtensionProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}
