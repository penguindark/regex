/*
regex 2.0 alpha

Copyright (c) 2019-2022 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains runtime parts

Know limitation:

*/
module regex

import strings


enum Match_state {
	start = 0
	stop
	end
	new_line
	ist_load // load and execute instruction
	ist_next // go to next instruction
	ist_next_ks // go to next instruction without clenaning the state
	ist_quant_p // match positive ,quantifier check
	ist_quant_n // match negative, quantifier check
	ist_quant_pg // match positive ,group quantifier check
	ist_quant_ng // match negative ,group quantifier check
}

struct State {
mut:
	i   int = 0 
	pc  int = 0
	match_start int = -1
	match_end int = -1
	rep []int
}

[direct_array_access]
pub fn (mut re RE) match_base(in_txt &u8, in_txt_len int) (int, int) {
	// result status
	mut result := regex.no_match_found // function return

	mut ch := rune(0) // examinated char
	mut char_len := 0 // utf8 examinated char len

	mut states_index := 0 // actual state index in states stack
	mut states_stack := []State{len:1}  // states stack
	mut fsm_state := Match_state.start // start point for the matcher FSM

	mut ist := u32(0) // actual instruction
	states_stack[0].rep = []int{len:re.prog_len, init:0}

	if re.debug > 0 {
		// print header
		mut h_buf := strings.new_builder(32)
		h_buf.write_string('flags: ')
		h_buf.write_string('${re.flag:8x}'.replace(' ', '0'))
		h_buf.write_string('\n')
		sss := h_buf.str()
		re.log_func(sss)
	}

	unsafe{	
		for fsm_state != .end {

			mut state := &states_stack[states_index]

			// load the instruction
			if state.pc >= 0 && state.pc < re.prog.len {
				ist = re.prog[state.pc].ist
			} else if state.pc >= re.prog.len {
				// eprintln("ERROR!! PC overflow!!")
				return regex.err_internal_error, state.i
			}
			
			if ist == regex.ist_prog_end {
				// println("HERE we end!")
				break
			}

			// load the char
			ch, char_len = re.get_charb(in_txt, state.i)

			// check new line if flag f_nl enabled
			if (re.flag & regex.f_nl) != 0 && char_len == 1 && u8(ch) in regex.new_line_list {
				fsm_state = .new_line
				continue
			}

			mut token_match := false

			// simple char IST
			if ist == regex.ist_simple_char {
				if re.prog[state.pc].ch == ch {
					token_match = true
					if state.match_start < 0 {
						state.match_start = state.i
					} else {
						state.match_end = state.i
					}

					state.rep[state.pc]++ // increase repetitions
					state.i += char_len // next char
				}
			}

			/******************************
			 * 
			 *  Check quantifier
			 * 
			 ******************************/
			rep := state.rep[state.pc]
			rep_min := re.prog[state.pc].rep_min
			rep_max := re.prog[state.pc].rep_max
			greedy := re.prog[state.pc].greedy
			if token_match == true {
				// not enough token, continue
				if rep < rep_min {
					continue
				}
				// we are satsfied
				if rep >= rep_min && rep < rep_max {
					if greedy == true {
						state.pc++
					}
					continue
				}
				if rep == rep_max {
					state.pc++
					continue
				}
			} else {
				// we have enough token, continue
				if rep >= rep_min && rep < rep_max {
					state.pc++
					continue
				}

				// not a match
				break
			}
			
		
		}
	} // end unsafe

	state := states_stack[states_index]
	if ist == regex.ist_prog_end {
		return state.match_start, state.match_end
	}
	return -1, -1
}