package commands

import (
	"context"
	"fmt"
	"os"
	"syscall"

	"github.com/zetamatta/go-getch"

	"github.com/zetamatta/nyagos/dos"
	"github.com/zetamatta/nyagos/shell"
)

func cmd_mkdir(ctx context.Context, cmd *shell.Cmd) (int, error) {
	if len(cmd.Args) <= 1 {
		fmt.Println("Usage: mkdir [/p] DIRECTORIES...")
		return 0, nil
	}
	errorcount := 0
	mkdir := os.Mkdir
	for _, arg1 := range cmd.Args[1:] {
		if arg1 == "/p" {
			mkdir = os.MkdirAll
			continue
		}
		err := mkdir(arg1, 0777)
		if err != nil {
			fmt.Fprintf(cmd.Stderr, "%s: %s\n", arg1, err)
			errorcount++
		}
	}
	return errorcount, nil
}

func cmd_rmdir(ctx context.Context, cmd *shell.Cmd) (int, error) {
	if len(cmd.Args) <= 1 {
		fmt.Println("Usage: rmdir [/s] [/q] DIRECTORIES...")
		return 0, nil
	}
	s_option := false
	quiet := false
	message := "%s: Rmdir Are you sure? [Yes/No/Quit] "
	errorcount := 0
	for _, arg1 := range cmd.Args[1:] {
		switch arg1 {
		case "/s":
			s_option = true
			message = "%s : Delete Tree. Are you sure? [Yes/No/Quit] "
			continue
		case "/q":
			quiet = true
			continue
		}
		stat, err := os.Lstat(arg1)
		if err != nil {
			fmt.Fprintf(cmd.Stderr, "%s: %s\n", arg1, err)
			errorcount++
			continue
		}
		if !stat.IsDir() {
			fmt.Fprintf(cmd.Stderr, "%s: not directory\n", arg1)
			errorcount++
			continue
		}
		if !quiet {
			fmt.Fprintf(cmd.Stderr, message, arg1)
			ch := getch.Rune()
			fmt.Fprintf(cmd.Stderr, "%c ", ch)
			switch ch {
			case 'y', 'Y':

			case 'q', 'Q':
				fmt.Fprintln(cmd.Stderr, "-> canceled all")
				return errorcount, nil
			default:
				fmt.Fprintln(cmd.Stderr, "-> canceled")
				continue
			}
		}
		if s_option {
			if !quiet {
				fmt.Fprintln(cmd.Stdout)
			}
			err = dos.Truncate(arg1, func(path string, err error) bool {
				fmt.Fprintf(cmd.Stderr, "%s -> %s\n", path, err)
				return true
			}, cmd.Stdout)
		} else {
			err = syscall.Rmdir(arg1)
		}
		if err != nil {
			fmt.Fprintf(cmd.Stderr, "-> %s\n", err)
			errorcount++
		} else {
			fmt.Fprintln(cmd.Stderr, "-> done.")
		}
	}
	return errorcount, nil
}
