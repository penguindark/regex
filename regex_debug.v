module regex

import strings

// get_code return the compiled code as regex string, note: may be different from the source!
pub fn (re RE) get_code() string {
	mut pc1 := 0
	mut res := strings.new_builder(re.cc.len * 2 * re.prog.len)
	res.write_string('========================================\nv RegEx compiler v ${regex.v_regex_version} output:\n')
	
	mut stop_flag := false

	for pc1 <= re.prog.len {
		tk := re.prog[pc1]
		res.write_string('PC:${pc1:3d}')

		res.write_string(' ist: ')
		res.write_string('${tk.ist:8x}'.replace(' ', '0'))
		res.write_string(' ')
		ist := tk.ist
		if ist == regex.ist_bsls_char {
			res.write_string('[\\${tk.ch:1c}]     BSLS')
		} else if ist == regex.ist_prog_end {
			res.write_string('PROG_END')
			stop_flag = true
		} else if ist == regex.ist_or_branch {
			res.write_string('OR      ')
		} else if ist == regex.ist_char_class_pos {
			res.write_string('[${re.get_char_class(pc1)}]     CHAR_CLASS_POS')
		} else if ist == regex.ist_char_class_neg {
			res.write_string('[^${re.get_char_class(pc1)}]    CHAR_CLASS_NEG')
		} else if ist == regex.ist_dot_char {
			res.write_string('.        DOT_CHAR')
		} 
/*
		else if ist == regex.ist_group_start {
			res.write_string('(        GROUP_START #:$tk.group_id')
			if tk.group_id == -1 {
				res.write_string(' ?:')
			} else {
				for x in re.group_map.keys() {
					if re.group_map[x] == (tk.group_id + 1) {
						res.write_string(' ?P<$x>')
						break
					}
				}
			}
		} else if ist == regex.ist_group_end {
			res.write_string(')        GROUP_END   #:$tk.group_id')
		} 
*/
		else if ist == regex.ist_simple_char {
			res.write_string('[${tk.ch:1c}]      query_ch')
		}

		if tk.rep_max == regex.max_quantifier {
			res.write_string(' {${tk.rep_min:3d},MAX}')
		} else {
			if ist == regex.ist_or_branch {
				res.write_string(' if false go: ${tk.rep_min:3d} if true go: ${tk.rep_max:3d}')
			} else {
				res.write_string(' {${tk.rep_min:3d},${tk.rep_max:3d}}')
			}
			if tk.greedy == true {
				res.write_string('?')
			}
		}

		res.write_string('\n')
		if stop_flag {
			break
		}
		pc1++
	}

	res.write_string('========================================\n')
	return res.str()
}

// get_query return a string with a reconstruction of the query starting from the regex program code
pub fn (re RE) get_query() string {
	mut res := strings.new_builder(re.query.len * 2)

	if (re.flag & regex.f_ms) != 0 {
		res.write_string('^')
	}

	mut i := 0
	for i < re.prog.len && re.prog[i].ist != regex.ist_prog_end && re.prog[i].ist != 0 {
		tk := unsafe { &re.prog[i] }
		ch := tk.ist
/*
		// GROUP start
		if ch == regex.ist_group_start {
			if re.debug > 0 {
				res.write_string('#$tk.group_id')
			}
			res.write_string('(')

			if tk.group_neg == true {
				res.write_string('?!') // negation group
			} else if tk.group_id == -1 {
				res.write_string('?:') // non capturing group
			}

			for x in re.group_map.keys() {
				if re.group_map[x] == (tk.group_id + 1) {
					res.write_string('?P<$x>')
					break
				}
			}

			i++
			continue
		}

		// GROUP end
		if ch == regex.ist_group_end {
			res.write_string(')')
		}

		// OR branch
		if ch == regex.ist_or_branch {
			res.write_string('|')
			if re.debug > 0 {
				res.write_string('{$tk.rep_min,$tk.rep_max}')
			}
			i++
			continue
		}
*/
		// char class
		if ch == regex.ist_char_class_neg || ch == regex.ist_char_class_pos {
			res.write_string('[')
			if ch == regex.ist_char_class_neg {
				res.write_string('^')
			}
			res.write_string('${re.get_char_class(i)}')
			res.write_string(']')
		}

		// bsls char
		if ch == regex.ist_bsls_char {
			res.write_string('\\${tk.ch:1c}')
		}

		// ist_dot_char
		if ch == regex.ist_dot_char {
			res.write_string('.')
		}

		// char alone
		if ch == regex.ist_simple_char {
			if u8(ch) in regex.bsls_escape_list {
				res.write_string('\\')
			}
			res.write_string('${tk.ch:c}')
		}

		// quantifier
		// if !(tk.rep_min == 1 && tk.rep_max == 1) && tk.group_neg == false {
		if !(tk.rep_min == 1 && tk.rep_max == 1) {
			if tk.rep_min == 0 && tk.rep_max == 1 {
				res.write_string('?')
			} else if tk.rep_min == 1 && tk.rep_max == regex.max_quantifier {
				res.write_string('+')
			} else if tk.rep_min == 0 && tk.rep_max == regex.max_quantifier {
				res.write_string('*')
			} else {
				if tk.rep_max == regex.max_quantifier {
					res.write_string('{$tk.rep_min,MAX}')
				} else {
					res.write_string('{$tk.rep_min,$tk.rep_max}')
				}
				if tk.greedy == true {
					res.write_string('?')
				}
			}
		}
		i++
	}
	if (re.flag & regex.f_me) != 0 {
		res.write_string('$')
	}

	return res.str()
}
