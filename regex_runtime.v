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
	states_stack[0].rep = []int{len:re.prog_len, init:0} // create the first state

	mut ist := u32(0) // actual instruction
	mut group_id := 0
	
	mut token_match := false
	mut out_of_text := false

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

			out_of_text = false
			// check out of text
			if state.i >= in_txt_len {
				println("out_of_text!")
				// we are out of text
				out_of_text = state.i >= in_txt_len
				token_match = false

				// println("state.pc: ${state.pc} re.prog.len: ${re.prog_len}")
				// we can exit here, this is the last ist
				if state.pc == re.prog_len - 1 {
					break
				}

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
				group_id = re.prog[state.pc].group_id
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
				if out_of_text {
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
									
								if re.prog[state.pc].rep_max == regex.max_quantifier {
									buf2.write_string('{${re.prog[state.pc].rep_min},MAX}:${state.rep[state.pc]}')
								} else {
									buf2.write_string('{${re.prog[state.pc].rep_min},${re.prog[state.pc].rep_max}}:${state.rep[state.pc]}')
								}
								if re.prog[state.pc].greedy == true {
									buf2.write_string('?')
								}
								//buf2.write_string(' (#$state.group_index)')

							}
							buf2.write_string('\n')
							sss2 := buf2.str()
							re.log_func(sss2)
						}
					}

					step_count++
				}
			}
			//******************************************
			
			if ist == regex.ist_prog_end {
				// println("HERE we end!")
				re.groups[group_id].i_end = state.i
				re.groups[group_id].i_start = state.match_start
				re.groups[group_id].i_tmp_start = -1
				break
			}

			//if !out_of_text {
			if true {
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

			} // end if !out_of_text

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
				
				if token_match == false // && re.prog[state.pc + 1].ist != regex.ist_prog_end
				{
					if rep >= rep_min && rep <= rep_max {
						println("*************** we can continue! ***************")
						if re.prog[state.pc].or_flag == true {
							state.pc++
						}
						state.pc++
						if re.prog[state.pc].ist != regex.ist_group_end {
							state.rep[state.pc] = 0
						}
						continue
					}
				}

				group_start_pc := re.prog[state.pc].group_start_pc
				if state.rep[state.pc] < re.prog[state.pc].rep_max {
					state.pc = group_start_pc
					continue
				}

				state.pc++
				if re.prog[state.pc].ist != regex.ist_group_end {
					state.rep[state.pc] = 0
				}
				continue

			}


			//
			// Quntifier for tokens
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
						println("Save state!")
						// we have not this level, create it
						if states_index >= states_stack.len - 1 { 
							// println("Create New state!")
							states_stack << State {
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

							states_stack[states_index].i = state.i
							states_stack[states_index].pc = return_pc
							states_stack[states_index].match_start = state.match_start
							states_stack[states_index].match_start = state.match_start
						}

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
					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					continue
				}
			} else {
				// we have enough token, continue anyway
				if rep >= rep_min && rep <= rep_max {
					//skip OR token
					if re.prog[state.pc].or_flag == true {
						state.pc++
					}
					state.pc++
					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					token_match = true
					continue
				}

				// not a match

				// we have to solve precedent situations, get old status
				if states_index > 0 {
					states_index--
					println("Restore state: ${states_index}")
					continue
				}

				// we have an OR try it
				if re.prog[state.pc].or_flag == true {
					state.pc++
					if re.prog[state.pc].ist != regex.ist_group_end {
						state.rep[state.pc] = 0
					}
					continue
				}

/*
				// we are in a group
				if group_id > 0 {
					token_match = false
					
					mut tmp_pc := re.groups[group_id].pc_end
					
					println("We are in group failed match! group_index:${group_id} states_index:${states_index}")
					println("tmp_pc: $tmp_pc rep_min:${re.prog[tmp_pc].rep_min} rep: ${state.rep[tmp_pc]}")
					
					println("OK we can continue, go after ist_group_end!")
					print(re.prog[tmp_pc])
					
					if re.prog[tmp_pc].or_flag == true {
						tmp_pc++
					}
					
					state.i = re.groups[group_id].i_end
					if state.match_end > state.i {
						state.match_end = state.i
					}

					
					
					state.pc = tmp_pc + 1
					continue
					
				}
*/				
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
			//print("Here!")
			return state.match_start, state.match_end - char_len
	}

	// check if last token has enough rep to exit with a match
	if re.prog[state.pc].ist != regex.ist_prog_end {
		tmp_pc := re.prog_len - 1
		rep := state.rep[tmp_pc]
		// println("tmp_pc: ${tmp_pc} rep: ${rep}")
		if rep > re.prog[tmp_pc].rep_min {
			// return state.match_start, state.match_end - char_len
			return state.match_start, state.match_end
		}
	}


	println("Temp result: ${state.match_start},${state.match_end - char_len}")
	return -1, -1
}