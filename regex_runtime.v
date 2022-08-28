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
	group_index int
	rep []int // counters for quantifier check (repetitions)
}

[inline; direct_array_access]
fn (mut re RE) get_next_token_pc(tmp_pc int) int {
	mut tmp_or_pc := tmp_pc
	for re.prog[tmp_or_pc].or_flag == true {
		if re.prog[tmp_or_pc].ist == regex.ist_group_start {
			tmp_or_pc = re.groups[re.prog[tmp_or_pc].group_id].pc_end + 1
			continue
		}
		tmp_or_pc++
	}
	tmp_or_pc++
	return tmp_or_pc
}

[direct_array_access]
pub fn (mut re RE) match_base(in_txt &u8, in_txt_len int) (int, int) {
	// result status
	mut result := regex.no_match_found // function return

	mut ch := rune(0) // examinated char
	mut char_len := 0 // utf8 examinated char len

	// reset and init the states
	mut states_index := 0 // actual state index in states stack
	if re.states_stack[0].rep.len == 0 {
		re.states_stack[0].rep = []int{len:re.prog_len, init:0} // create the first state
	}

	mut ist := u32(0) // actual instruction
	mut group_id := 0
	
	mut token_match := false
	mut out_of_text := false

	mut step_count := 0

	if re.debug > 0 {
		// print header
		mut h_buf := strings.new_builder(32)
		h_buf.write_string('flags: ')
		h_buf.write_string('${re.flag:08x}')
		h_buf.write_string('\n')
		sss := h_buf.str()
		re.log_func(sss)
	}

	unsafe{	
		for {
			mut state := &re.states_stack[states_index]
			// println("states_index: ${states_index} PC: ${state.pc} i: ${state.i} txt_len:${in_txt_len}")

			// load the instruction
			if state.pc >= 0 && state.pc < re.prog.len {
				ist = re.prog[state.pc].ist
				group_id = re.prog[state.pc].group_id
			} else if state.pc >= re.prog.len {
				// eprintln("ERROR!! PC overflow!!")
				return regex.err_internal_error, state.i
			}

			//******************************************
			// Debug log
			//******************************************
			if re.debug >= 1 {
				mut buf2 := strings.new_builder(re.cc.len + 128)
				
				if ist == regex.ist_prog_end {
					buf2.write_string('# ${step_count:3d} PROG_END\n')
				} else {
					ch, char_len = re.get_charb(in_txt, state.i)
					buf2.write_string('# ${step_count:3d} GRP:${re.prog[state.pc].group_id:2d} SI:${states_index:2d} PC: ${state.pc:3d}=>')
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
							buf2.write_string('GROUP_START #:$tmp_gi REP:${state.rep[state.pc]} ')
						} else if ist == regex.ist_group_end {
							buf2.write_string('GROUP_END   #:${re.prog[state.pc].group_id} REP:${state.rep[state.pc]} TM:${token_match} ')
						}
					}

					if re.prog[state.pc].rep_max == regex.max_quantifier {
						buf2.write_string('{${re.prog[state.pc].rep_min},MAX}=${state.rep[state.pc]}')
					} else {
						buf2.write_string('{${re.prog[state.pc].rep_min},${re.prog[state.pc].rep_max}}=${state.rep[state.pc]}')
					}
					if re.prog[state.pc].greedy == true {
						buf2.write_string('?')
					}
					//buf2.write_string(' (#$state.group_index)')
				}

				buf2.write_string('\n')
				sss2 := buf2.str()
				re.log_func(sss2)
				step_count++
			}
			//******************************************
			
			if ist == regex.ist_prog_end {
				// println("HERE we end!")

				// NOTE: Investigate if needed in particular cases
				/*
				// try other ways
				if states_index > 0 {
					println("Restore State! End program, try other ways, restore state!")
					states_index--
					continue
				}
				*/

				re.groups[group_id].i_end = state.i
				re.groups[group_id].i_start = state.match_start
				re.groups[group_id].i_tmp_start = -1
				break
			}

			//******************************************
			// Out of Text management
			//******************************************
			out_of_text = false
			// check out of text
			// NOTE: We must have the 0 at the end of the string,
			// C Style strings!!
			// TO investigate >= vs > in this IF
			if state.i >= in_txt_len {

				// debug log
				if re.debug > 0 {
					mut buf2 := strings.new_builder(re.cc.len + 128)
					buf2.write_string('# ${step_count:3d} END OF INPUT TEXT\n')
					buf2.write_string('\n')
					sss2 := buf2.str()
					re.log_func(sss2)
				}
				
				// we are out of text
				out_of_text = state.i >= in_txt_len
				token_match = false

				// println("state.pc: ${state.pc} re.prog.len: ${re.prog_len}")
				
				// we can exit here, this is the last ist or th eprogram is ended
				if state.pc >= re.prog_len - 1 {
					// println("out_of_text BREAK!")
					break
				}

				// we have some cards to play, continue with th eold state
				if states_index > 0 {
					println("Restore State! this Out of text branch is not good, restore state!")
					states_index--
					continue
				}

				break
			}

			// load the char
			ch, char_len = re.get_charb(in_txt, state.i)

			// check new line if flag f_nl enabled
			if (re.flag & regex.f_nl) != 0 && char_len == 1 && u8(ch) in regex.new_line_list {
				if states_index > 0 {
					// println("Restore State! this EOL branch is no godd,restore state!")
					states_index--
					continue
				}
				break
			}			

			
			// group start IST
			if ist == regex.ist_group_start {
				re.groups[group_id].i_tmp_start = state.i
				// println("regex.ist_group_start g_index:${state.group_index}")	
			}

			// group end IST
			else if ist == regex.ist_group_end {
				if token_match == true {
					state.rep[state.pc]++
					re.groups[group_id].i_start = re.groups[group_id].i_tmp_start
					re.groups[group_id].i_end = state.i
					re.groups[group_id].i_tmp_start = -1
				}

				if token_match == false {
					println("regex.ist_group_end on token_match FALSE")
				}
			}

			// char class IST
			else if ist == regex.ist_char_class_pos || ist == regex.ist_char_class_neg {
				token_match = false
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
				token_match = false
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
				token_match = false
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

// TO REMOVE AFTER VERIFY!!
/*
			// we have other branches to explore, do it!
			if token_match == false && states_index > 0 {
				println("Restore State! we have other branches to explore, do it!")
				states_index--
				continue
			}
*/
			

			//******************************************
			// Check quantifier
			//******************************************
			rep        := state.rep[state.pc]
			rep_min    := re.prog[state.pc].rep_min
			rep_max    := re.prog[state.pc].rep_max
			greedy     := re.prog[state.pc].greedy
			save_state := re.prog[state.pc].save_state

			//
			// Quntifier for start group token
			// 
			if ist == regex.ist_group_start {
				// println("Quntifier start groups")
				state.pc++
				state.rep[state.pc] = 0
				continue
			}
			//
			// Quntifier for end group token
			// 
			if ist == regex.ist_group_end {
				// we have a fail in a group but enough repetitions

				println("rep: ${rep} token_match: ${token_match}")
				// println("re.prog[${state.pc}]: ${re.prog[state.pc]}")
				
				

			}

			//
			// Quantifier for tokens
			//
			mut return_pc := state.pc
			if ist == regex.ist_group_end {
				return_pc++
			}

			// println("token_match ${token_match} IST:${ist:x}")
			if token_match == true {
				// not enough token, continue
				if rep < rep_min {
					continue
				}

				// we are satisfied
				if rep >= rep_min && rep < rep_max {			
					// we need to manage the state
					// in order to keep track of the next tokens
					if save_state == true &&  
						re.prog[return_pc].ist != regex.ist_prog_end
					{
						// println("Save state!")
						// we have not this level, create it
						if states_index >= re.states_stack.len - 1 { 
							// println("Create New state!")
							re.states_stack << State {
								i:state.i,
								pc:return_pc,
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

							re.states_stack[states_index].i = state.i
							re.states_stack[states_index].pc = return_pc
							re.states_stack[states_index].match_start = state.match_start
							re.states_stack[states_index].match_start = state.match_start
						}

						re.states_stack[states_index].rep = state.rep.clone()

						// skip OR sequence if any
						tmp_pc := re.get_next_token_pc(re.states_stack[states_index].pc)
						
						re.states_stack[states_index].pc = tmp_pc
						re.states_stack[states_index].rep[tmp_pc] = 0
						// println("New state ready!")
					}
					continue
				}
				if rep == rep_max {
					// println("Here max!!")
					state.pc = re.get_next_token_pc(state.pc)
					
					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					continue
				}
			} else {
				//
				if rep == 0 && rep_min == 0 && states_index > 0 
				&& !re.prog[state.pc].greedy
				{
					states_index--
					println("Restore State!  rep == 0")
					continue
				}

				// we have enough token, continue anyway
				if rep >= rep_min && rep <= rep_max {
					state.pc = re.get_next_token_pc(state.pc)

					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					token_match = true
					continue
				}

				// not a match
				// print("HERE not a match!")

				// we have to solve precedent situations, get old status
				if states_index > 0 {
					states_index--
					println("Restore State!  states_index:${states_index}")
					continue
				}

				// we have an OR? If yes try it!
				if re.prog[state.pc].or_flag == true {
					state.pc++
					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					continue
				}

				// no alternatives, break
				break
			}
			
		}
	} // end unsafe

	//******************************************
	// Exit check
	//******************************************
	state := re.states_stack[states_index]

	// normal exit if match 
	if ist == regex.ist_prog_end {
		re.groups[0].i_start = state.match_start
		re.groups[0].i_end = state.match_end
		return state.match_start, state.match_end
	}

	// check if query is satisfied even before the ist_prog_end
	// start from the first token before the ist_prog_end and go backward
	mut tmp_pc := re.prog_len - 1 
	for tmp_pc >= 0 {
		rep := state.rep[tmp_pc]
		// println("ending check: i: ${i} rep: ${rep} rep_min: ${re.prog[i].rep_min}")
		if rep == 0 && re.prog[tmp_pc].rep_min == 0 {
			if re.prog[tmp_pc].ist != regex.ist_group_end {
				// not a ist_group_end, check previous token
				tmp_pc-- 
			} else {
				// we are at the end of a group, go at the token before the group start
				tmp_pc = re.groups[re.prog[tmp_pc].group_id].pc_start - 1
			}
			continue
		}

		// no match found exit
		if rep < re.prog[tmp_pc].rep_min {
			break
		}

		// if we exit on out_of_text the match_end = in_txt_len
		match_end := if out_of_text { in_txt_len } else {state.match_end - char_len }
		if rep >= re.prog[tmp_pc].rep_min {
			re.groups[0].i_start = state.match_start
			re.groups[0].i_end = match_end
			return state.match_start, match_end
		}
	}

	println("Temp result: ${state.match_start},${state.match_end - char_len}")
	return -1, -1
}