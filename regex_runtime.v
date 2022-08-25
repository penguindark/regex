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

struct State {
mut:
	i   int
	pc  int
	match_start int = -1
	match_end   int = -1
	group_index int = 0
	rep []int // counters for quantifier check (repetitions)
}

[direct_array_access]
pub fn (mut re RE) match_base(in_txt &u8, in_txt_len int) (int, int) {
	// result status
	mut result := regex.no_match_found // function return

	mut ch := rune(0) // examinated char
	mut char_len := 0 // utf8 examinated char len

	mut states_index := 0 // actual state index in states stack
	mut states_stack := []State{len:1}  // states stack

	mut ist := u32(0) // actual instruction
	states_stack[0].rep = []int{len:re.prog_len, init:0}

	re.groups << Group{
		id : 0,
	}

	mut token_match := false

	mut step_count := 0

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
		for {

			mut state := &states_stack[states_index]
			// println("states_index: ${states_index} PC: ${state.pc} i: ${state.i} txt_len:${in_txt_len}")

			// check out of text
			if state.i > in_txt_len {
				// println("Out of text!")
				if states_index > 0 {
					// println("this Out of text branch is no godd,restore state!")
					states_index--
					continue
				}
				break
			}

			// load the instruction
			if state.pc >= 0 && state.pc < re.prog.len {
				ist = re.prog[state.pc].ist
			} else if state.pc >= re.prog.len {
				// eprintln("ERROR!! PC overflow!!")
				return regex.err_internal_error, state.i
			}

			//******************************************
			// DEBUG LOG
			//******************************************
			if re.debug > 0 {
				mut buf2 := strings.new_builder(re.cc.len + 128)

				// print all the instructions

				// end of the input text
				if state.i >= in_txt_len {
					buf2.write_string('# ${step_count:3d} END OF INPUT TEXT\n')
					sss := buf2.str()
					re.log_func(sss)
				} else {
					// print only the exe instruction
					if re.debug == 1 || re.debug == 2 {
						if ist == regex.ist_prog_end {
							buf2.write_string('# ${step_count:3d} PROG_END\n')
						
						} else {
							ch, char_len = re.get_charb(in_txt, state.i)
							buf2.write_string('# ${step_count:3d} TL:${in_txt_len:3d} SI:${states_index:2d} PC: ${state.pc:3d}=>')
							// buf2.write_string('${ist:8x}'.replace(' ', '0'))
							buf2.write_string(" i,ch,len:[${state.i:3d},'${utf8_str(ch)}',$char_len] f.m:[${state.match_start:3d},${state.match_end:3d}] ")

							if ist == regex.ist_simple_char {
								buf2.write_string('query_ch: [${re.prog[state.pc].ch:1c}]')
							} else {
								if ist == regex.ist_bsls_char {
									buf2.write_string('BSLS [\\${re.prog[state.pc].ch:1c}]')
								} else if ist == regex.ist_prog_end {
									buf2.write_string('PROG_END')
								} else if ist == regex.ist_or_branch {
									buf2.write_string('OR')
								} else if ist == regex.ist_char_class_pos {
									buf2.write_string('CHAR_CLASS_POS[${re.get_char_class(state.pc)}]')
								} else if ist == regex.ist_char_class_neg {
									buf2.write_string('CHAR_CLASS_NEG[${re.get_char_class(state.pc)}]')
								} else if ist == regex.ist_dot_char {
									buf2.write_string('DOT_CHAR')
								} 
								else if ist == regex.ist_group_start {
									tmp_gi := re.prog[state.pc].group_id
									//tmp_gr := re.prog[re.prog[state.pc].goto_pc].group_rep
									//buf2.write_string('GROUP_START #:$tmp_gi rep:$tmp_gr ')
									buf2.write_string('GROUP_START #:$tmp_gi')
								} else if ist == regex.ist_group_end {
									buf2.write_string('GROUP_END   #:${re.prog[state.pc].group_id} deep:$state.group_index')
								}
								
							}
							if re.prog[state.pc].rep_max == regex.max_quantifier {
								buf2.write_string('{${re.prog[state.pc].rep_min},MAX}:${state.rep[state.pc]}')
							} else {
								buf2.write_string('{${re.prog[state.pc].rep_min},${re.prog[state.pc].rep_max}}:${state.rep[state.pc]}')
							}
							if re.prog[state.pc].greedy == true {
								buf2.write_string('?')
							}
							//buf2.write_string(' (#$state.group_index)')

							buf2.write_string('\n')
						}
						sss2 := buf2.str()
						re.log_func(sss2)
					}
				}
				step_count++
			}
			//******************************************
			
			if ist == regex.ist_prog_end {
				// println("HERE we end!")
				break
			}

			// load the char
			ch, char_len = re.get_charb(in_txt, state.i)

			// check new line if flag f_nl enabled
			if (re.flag & regex.f_nl) != 0 && char_len == 1 && u8(ch) in regex.new_line_list {
				if states_index > 0 {
					// println("this EOL branch is no godd,restore state!")
					states_index--
					continue
				}
				break
			}			

			token_match = false

			// char class IST
			if ist == regex.ist_char_class_pos || ist == regex.ist_char_class_neg {
				mut cc_neg := false
				if ist == regex.ist_char_class_neg {
					cc_neg = true
				}
				
				mut cc_res := re.check_char_class(state.pc, ch)

				if cc_neg {
					cc_res = !cc_res
				}

				if cc_res == true {
					token_match = true
					if state.match_start < 0 {
						state.match_start = state.i
					} else {
						state.match_end = state.i + char_len
					}

					state.rep[state.pc]++ // increase repetitions
					state.i += char_len // next char
				}
				
			}

			// dot_char IST
			else if ist == regex.ist_dot_char {
				token_match = true
				if state.match_start < 0 {
					state.match_start = state.i
				} else {
					state.match_end = state.i + char_len
				}

				state.rep[state.pc]++ // increase repetitions
				state.i += char_len // next char
			}

			// bsls IST
			else if ist == regex.ist_bsls_char {
				if re.prog[state.pc].validator(u8(ch)) {
					token_match = true
					if state.match_start < 0 {
						state.match_start = state.i
					} else {
						state.match_end = state.i + char_len
					}

					state.rep[state.pc]++ // increase repetitions
					state.i += char_len // next char
				}
			}

			// simple char IST
			else if ist == regex.ist_simple_char {
				if re.prog[state.pc].ch == ch {
					token_match = true
					if state.match_start < 0 {
						state.match_start = state.i
					} else {
						state.match_end = state.i + char_len
					}

					state.rep[state.pc]++ // increase repetitions
					state.i += char_len // next char
				}
			}

			//******************************************
			// Check quantifier
			//******************************************
			rep        := state.rep[state.pc]
			rep_min    := re.prog[state.pc].rep_min
			rep_max    := re.prog[state.pc].rep_max
			greedy     := re.prog[state.pc].greedy
			save_state := re.prog[state.pc].save_state

			if token_match == true {
				// not enough token, continue
				if rep < rep_min {
					continue
				}
				// we are satisfied
				if rep >= rep_min && rep < rep_max {
/*					
					// greedy flag management
					if greedy == true {
						if re.prog[state.pc].or_flag == true {
							state.pc++
						}
						state.pc++
					}
*/					
					
					// we need to manage the state
					// in order to keep track of the next tokens
					if save_state == true {
						
						// we have not this level, create it
						if states_index >= states_stack.len - 1 { 
							// println("Create New state!")
							states_stack << State {
								i:state.i,
								pc:state.pc,
								match_start:state.match_start,
								match_end:state.match_end,
								rep:[]int{len:re.prog_len, init:0}
							}
							states_index++
						} 
						// we can reuse some memory, do it
						else {
							// println("Reuse New state!")
							states_index++

							states_stack[states_index].i = state.i
							states_stack[states_index].pc = state.pc
							states_stack[states_index].match_start = state.match_start
							states_stack[states_index].match_start = state.match_start
						}

						// copy all the repetition
						// must be optimized
						/*
						for c,x in state.rep[..state.pc] {
							states_stack[states_index].rep[c] = x
						}
						*/

						states_stack[states_index].rep = state.rep.clone()


						tmp_pc := states_stack[states_index].pc + 1
						if re.prog[state.pc].or_flag == true {
							tmp_pc++
						}
						
						states_stack[states_index].pc = tmp_pc
						states_stack[states_index].rep[tmp_pc] = 0
						// println("New state ready!")
					}
					continue
				}
				if rep == rep_max {
					if re.prog[state.pc].or_flag == true {
						state.pc++
					}
					state.pc++
					state.rep[state.pc] = 0
					continue
				}
			} else {
				// we have enough token, continue
				if rep >= rep_min && rep <= rep_max {
					if re.prog[state.pc].or_flag == true {
						state.pc++
					}
					state.pc++
					state.rep[state.pc] = 0
					continue
				}

				// not a match

				// we have to solve precedent situation
				if states_index > 0 {
					// println("this branch is no good,restore state!")
					states_index--
					continue
				}

				// we have an OR try it
				if re.prog[state.pc].or_flag == true {
					state.pc++
					state.rep[state.pc] = 0
					continue
				}

				// no alternatives, break
				break
			}
			
		
		}
	} // end unsafe

	state := states_stack[states_index]
	if ist == regex.ist_prog_end {
		return state.match_start, state.match_end
	}
	if state.i > in_txt_len && 
		re.prog[state.pc + 1 ].ist == regex.ist_prog_end &&
		token_match == true
	{
			print("Here!")
			return state.match_start, state.match_end - char_len
	}
	return -1, -1
}