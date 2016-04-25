package main

import (
	"flag"
	"fmt"
	"os"

	"../interpreter"
	"../lua"
)

func setLuaArg(L lua.Lua, arg0 string) {
	L.NewTable()
	L.PushString(arg0)
	L.RawSetI(-2, 0)
	for i, arg1 := range flag.Args() {
		L.PushString(arg1)
		L.RawSetI(-2, lua.Integer(i+1))
	}
	L.SetGlobal("arg")
}

func optionParse(it *interpreter.Interpreter, L lua.Lua) bool {
	result := true

	if *optionK != "" {
		it.Interpret(*optionK)
	}
	if *optionC != "" {
		it.Interpret(*optionC)
		result = false
	}
	if *optionF != "" {
		setLuaArg(L, *optionF)
		err := L.Source(*optionF)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
		result = false
	}
	if *optionE != "" {
		err := L.LoadString(*optionE)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		} else {
			setLuaArg(L, *optionE)
			L.Call(0, 0)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
			}
		}
		result = false
	}
	return result
}
