/*
regex 2.0 alpha

Copyright (c) 2019-2022 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains regex compiler

Know limitation:

*/
module regex

/******************************************************************************
*
* General Utilities
*
******************************************************************************/

// simple_log default log function
fn simple_log(txt string) {
	print(txt)
}

// utf8util_char_len calculate the length in bytes of a utf8 char
[inline]
fn utf8util_char_len(b u8) int {
	return ((0xe5000000 >> ((b >> 3) & 0x1e)) & 3) + 1
}

// utf8_str convert and utf8 sequence to a printable string
[inline]
fn utf8_str(ch rune) string {
	mut i := 4
	mut res := ''
	for i > 0 {
		v := u8((ch >> ((i - 1) * 8)) & 0xFF)
		if v != 0 {
			res += '${v:1c}'
		}
		i--
	}
	return res
}

// get_char get a char from position i and return an u32 with the unicode code
[direct_array_access; inline]
fn (re RE) get_char(in_txt string, i int) (u32, int) {
	ini := unsafe { in_txt.str[i] }
	// ascii 8 bit
	if (re.flag & regex.f_bin) != 0 || ini & 0x80 == 0 {
		return u32(ini), 1
	}
	// unicode char
	char_len := utf8util_char_len(ini)
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | unsafe { in_txt.str[i + tmp] }
		tmp++
	}
	return ch, char_len
}

// get_charb get a char from position i and return an u32 with the unicode code
[direct_array_access; inline]
fn (re RE) get_charb(in_txt &u8, i int) (u32, int) {
	// ascii 8 bit
	if (re.flag & regex.f_bin) != 0 || unsafe { in_txt[i] } & 0x80 == 0 {
		return u32(unsafe { in_txt[i] }), 1
	}
	// unicode char
	char_len := utf8util_char_len(unsafe { in_txt[i] })
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | unsafe { in_txt[i + tmp] }
		tmp++
	}
	return ch, char_len
}

[inline]
fn is_alnum(in_char u8) bool {
	mut tmp := in_char - `A`
	if tmp <= 25 {
		return true
	}
	tmp = in_char - `a`
	if tmp <= 25 {
		return true
	}
	tmp = in_char - `0`
	if tmp <= 9 {
		return true
	}
	if in_char == `_` {
		return true
	}
	return false
}

[inline]
fn is_not_alnum(in_char u8) bool {
	return !is_alnum(in_char)
}

[inline]
fn is_space(in_char u8) bool {
	return in_char in regex.spaces
}

[inline]
fn is_not_space(in_char u8) bool {
	return !is_space(in_char)
}

[inline]
fn is_digit(in_char u8) bool {
	tmp := in_char - `0`
	return tmp <= 0x09
}

[inline]
fn is_not_digit(in_char u8) bool {
	return !is_digit(in_char)
}


[inline]
fn is_lower(in_char u8) bool {
	tmp := in_char - `a`
	return tmp <= 25
}

[inline]
fn is_upper(in_char u8) bool {
	tmp := in_char - `A`
	return tmp <= 25
}

/******************************************************************************
*
* Backslashes chars
*
******************************************************************************/
struct BslsStruct {
	ch        rune        // meta char
	validator FnValidator // validator function pointer
}

const (
	bsls_validator_array = [
		BslsStruct{`w`, is_alnum},
		BslsStruct{`W`, is_not_alnum},
		BslsStruct{`s`, is_space},
		BslsStruct{`S`, is_not_space},
		BslsStruct{`d`, is_digit},
		BslsStruct{`D`, is_not_digit},
		BslsStruct{`a`, is_lower},
		BslsStruct{`A`, is_upper},
	]

	// these chars are escape if preceded by a \
	bsls_escape_list     = [`\\`, `|`, `.`, `:`, `*`, `+`, `-`, `{`, `}`, `[`, `]`, `(`, `)`, `?`,
		`^`, `!`]
)

enum BSLS_parse_state {
	start
	bsls_found
	bsls_char
	normal_char
}

// parse_bsls return (index, str_len) bsls_validator_array index, len of the backslash sequence if present
fn (re RE) parse_bsls(in_txt string, in_i int) (int, int) {
	mut status := BSLS_parse_state.start
	mut i := in_i

	for i < in_txt.len {
		// get our char
		char_tmp, char_len := re.get_char(in_txt, i)
		ch := u8(char_tmp)

		if status == .start && ch == `\\` {
			status = .bsls_found
			i += char_len
			continue
		}

		// check if is our bsls char, for now only one length sequence
		if status == .bsls_found {
			for c, x in regex.bsls_validator_array {
				if x.ch == ch {
					return c, i - in_i + 1
				}
			}
			status = .normal_char
			continue
		}

		// no BSLS validator, manage as normal escape char char
		if status == .normal_char {
			if ch in regex.bsls_escape_list {
				return regex.no_match_found, i - in_i + 1
			}
			return regex.err_syntax_error, i - in_i + 1
		}

		// at the present time we manage only one char after the \
		break
	}
	// not our bsls return KO
	return regex.err_syntax_error, i
}

/******************************************************************************
*
* Char class
*
******************************************************************************/
const (
	cc_null = 0 // empty cc token
	cc_char = 1 // simple char: a
	cc_int  = 2 // char interval: a-z
	cc_bsls = 3 // backslash char
	cc_end  = 4 // cc sequence terminator
)

struct CharClass {
mut:
	cc_type   int = regex.cc_null // type of cc token
	ch0       rune        // first char of the interval a-b  a in this case
	ch1       rune        // second char of the interval a-b b in this case
	validator FnValidator // validator function pointer
}

enum CharClass_parse_state {
	start
	in_char
	in_bsls
	separator
	finish
}

fn (re RE) get_char_class(pc int) string {
	buf := []u8{len: (re.cc.len)}
	mut buf_ptr := unsafe { &u8(&buf) }

	mut cc_i := re.prog[pc].cc_index
	mut i := 0
	mut tmp := 0
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != regex.cc_end {
		if re.cc[cc_i].cc_type == regex.cc_bsls {
			unsafe {
				buf_ptr[i] = `\\`
				i++
				buf_ptr[i] = u8(re.cc[cc_i].ch0)
				i++
			}
		} else if re.cc[cc_i].ch0 == re.cc[cc_i].ch1 {
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch0 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
		} else {
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch0 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
			unsafe {
				buf_ptr[i] = `-`
				i++
			}
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch1 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
		}
		cc_i++
	}
	unsafe {
		buf_ptr[i] = u8(0)
	}
	return unsafe { tos_clone(buf_ptr) }
}

fn (re RE) check_char_class(pc int, ch rune) bool {
	mut cc_i := re.prog[pc].cc_index
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != regex.cc_end {
		if re.cc[cc_i].cc_type == regex.cc_bsls {
			if re.cc[cc_i].validator(u8(ch)) {
				return true
			}
		} else if ch >= re.cc[cc_i].ch0 && ch <= re.cc[cc_i].ch1 {
			return true
		}
		cc_i++
	}
	return false
}

// parse_char_class return (index, str_len, cc_type) of a char class [abcm-p], char class start after the [ char
fn (mut re RE) parse_char_class(in_txt string, in_i int) (int, int, u32) {
	mut status := CharClass_parse_state.start
	mut i := in_i

	mut tmp_index := re.cc_index
	res_index := re.cc_index

	mut cc_type := u32(regex.ist_char_class_pos)

	for i < in_txt.len {
		// check if we are out of memory for char classes
		if tmp_index >= re.cc.len {
			return regex.err_cc_alloc_overflow, 0, u32(0)
		}

		// get our char
		char_tmp, char_len := re.get_char(in_txt, i)
		ch := u8(char_tmp)

		// println("CC #${i:3d} ch: ${ch:c}")

		// negation
		if status == .start && ch == `^` {
			cc_type = u32(regex.ist_char_class_neg)
			i += char_len
			continue
		}

		// minus symbol
		if status == .start && ch == `-` {
			re.cc[tmp_index].cc_type = regex.cc_char
			re.cc[tmp_index].ch0 = char_tmp
			re.cc[tmp_index].ch1 = char_tmp
			i += char_len
			tmp_index++
			continue
		}

		// bsls
		if (status == .start || status == .in_char) && ch == `\\` {
			// println("CC bsls.")
			status = .in_bsls
			i += char_len
			continue
		}

		if status == .in_bsls {
			// println("CC bsls validation.")
			for c, x in regex.bsls_validator_array {
				if x.ch == ch {
					// println("CC bsls found [${ch:c}]")
					re.cc[tmp_index].cc_type = regex.cc_bsls
					re.cc[tmp_index].ch0 = regex.bsls_validator_array[c].ch
					re.cc[tmp_index].ch1 = regex.bsls_validator_array[c].ch
					re.cc[tmp_index].validator = regex.bsls_validator_array[c].validator
					i += char_len
					tmp_index++
					status = .in_char
					break
				}
			}
			if status == .in_bsls {
				// manage as a simple char
				// println("CC bsls not found [${ch:c}]")
				re.cc[tmp_index].cc_type = regex.cc_char
				re.cc[tmp_index].ch0 = char_tmp
				re.cc[tmp_index].ch1 = char_tmp
				i += char_len
				tmp_index++
				status = .in_char
				continue
			} else {
				continue
			}
		}

		// simple char
		if (status == .start || status == .in_char) && ch != `-` && ch != `]` {
			status = .in_char

			re.cc[tmp_index].cc_type = regex.cc_char
			re.cc[tmp_index].ch0 = char_tmp
			re.cc[tmp_index].ch1 = char_tmp

			i += char_len
			tmp_index++
			continue
		}

		// check range separator
		if status == .in_char && ch == `-` {
			status = .separator
			i += char_len
			continue
		}

		// check range end
		if status == .separator && ch != `]` && ch != `-` {
			status = .in_char
			re.cc[tmp_index - 1].cc_type = regex.cc_int
			re.cc[tmp_index - 1].ch1 = char_tmp
			i += char_len
			continue
		}

		// char class end
		if status == .in_char && ch == `]` {
			re.cc[tmp_index].cc_type = regex.cc_end
			re.cc[tmp_index].ch0 = 0
			re.cc[tmp_index].ch1 = 0
			re.cc_index = tmp_index + 1

			return res_index, i - in_i + 2, cc_type
		}

		i++
	}
	return regex.err_syntax_error, 0, u32(0)
}

/******************************************************************************
*
* Quantifiers
*
******************************************************************************/
enum Quant_parse_state {
	start
	min_parse
	comma_checked
	max_parse
	greedy
	gredy_parse
	finish
}

const(
	quntifier_chars = [rune(`+`), `*`, `?`, `{`]
)

// parse_quantifier return (min, max, str_len, greedy_flag) of a {min,max}? quantifier starting after the { char
fn (re RE) parse_quantifier(in_txt string, in_i int) (int, int, int, bool) {
	mut status := Quant_parse_state.start
	mut i := in_i

	mut q_min := 0 // default min in a {} quantifier is 1
	mut q_max := 0 // deafult max in a {} quantifier is max_quantifier

	mut ch := u8(0)

	for i < in_txt.len {
		unsafe {
			ch = in_txt.str[i]
		}
		// println("${ch:c} status: $status")

		// exit on no compatible char with {} quantifier
		if utf8util_char_len(ch) != 1 {
			return regex.err_syntax_error, i, 0, false
		}

		// min parsing skip if comma present
		if status == .start && ch == `,` {
			q_min = 0 // default min in a {} quantifier is 0
			status = .comma_checked
			i++
			continue
		}

		if status == .start && is_digit(ch) {
			status = .min_parse
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		if status == .min_parse && is_digit(ch) {
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		// we have parsed the min, now check the max
		if status == .min_parse && ch == `,` {
			status = .comma_checked
			i++
			continue
		}

		// single value {4}
		if status == .min_parse && ch == `}` {
			q_max = q_min
			status = .greedy
			continue
		}

		// end without max
		if status == .comma_checked && ch == `}` {
			q_max = regex.max_quantifier
			status = .greedy
			continue
		}

		// start max parsing
		if status == .comma_checked && is_digit(ch) {
			status = .max_parse
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// parse the max
		if status == .max_parse && is_digit(ch) {
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// finished the quantifier
		if status == .max_parse && ch == `}` {
			status = .greedy
			continue
		}

		// check if greedy flag char ? is present
		if status == .greedy {
			if i + 1 < in_txt.len {
				i++
				status = .gredy_parse
				continue
			}
			return q_min, q_max, i - in_i + 2, false
		}

		// check the greedy flag
		if status == .gredy_parse {
			if ch == `?` {
				return q_min, q_max, i - in_i + 2, true
			} else {
				i--
				return q_min, q_max, i - in_i + 2, false
			}
		}

		// not  a {} quantifier, exit
		return regex.err_syntax_error, i, 0, false
	}

	// not a conform {} quantifier
	return regex.err_syntax_error, i, 0, false
}

/******************************************************************************
*
* Groups
*
******************************************************************************/
enum Group_parse_state {
	start
	q_mark // (?
	q_mark1 // (?:|P  checking
	p_status // (?P
	p_start // (?P<
	p_end // (?P<...>
	p_in_name // (?P<...
	finish
}

// parse_groups parse a group for ? (question mark) syntax, if found, return (error, capture_flag, negate_flag, name_of_the_group, next_index)
fn (re RE) parse_groups(in_txt string, in_i int) (int, bool, bool, string, int) {
	mut status := Group_parse_state.start
	mut i      := in_i
	mut name   := ''

	for i < in_txt.len && status != .finish {
		// get our char
		char_tmp, char_len := re.get_char(in_txt, i)
		ch := u8(char_tmp)

		// start
		if status == .start && ch == `(` {
			status = .q_mark
			i += char_len
			continue
		}

		// check for question marks
		if status == .q_mark && ch == `?` {
			status = .q_mark1
			i += char_len
			continue
		}

		// negate group
		if status == .q_mark1 && ch == `!` {
			i += char_len
			return 0, false, true, name, i
		}

		// non capturing group
		if status == .q_mark1 && ch == `:` {
			i += char_len
			return 0, false, false, name, i
		}

		// enter in P section
		if status == .q_mark1 && ch == `P` {
			status = .p_status
			i += char_len
			continue
		}

		// not a valid q mark found
		if status == .q_mark1 {
			// println("NO VALID Q MARK")
			return -2, true, false, name, i
		}

		if status == .p_status && ch == `<` {
			status = .p_start
			i += char_len
			continue
		}

		if status == .p_start && ch != `>` {
			status = .p_in_name
			name += '${ch:1c}' // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// colect name
		if status == .p_in_name && ch != `>` && is_alnum(ch) {
			name += '${ch:1c}' // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// end name
		if status == .p_in_name && ch == `>` {
			i += char_len
			return 0, true, false, name, i
		}

		// error on name group
		if status == .p_in_name {
			return -2, true, false, name, i
		}

		// normal group, nothig to do, exit
		return 0, true, false, name, i
	}
	// UNREACHABLE
	// println("ERROR!! NOT MEANT TO BE HERE!!1")
	return -2, true, false, name, i
}

/******************************************************************************
*
* Regex Compiler
*
******************************************************************************/
// compile return (return code, index) where index is the index of the error in the query string 
// if return code is an error code
fn (mut re RE) impl_compile(in_txt string) (int, int) {
	mut i  := 0 // input string index
	mut pc := 0 // program counter

	re.query = in_txt // save the query string

	// groups
	mut group_count       := 0
	mut group_index       := 0
	mut group_stack       := []int{}

	re.groups << Group{
		id : 0,
	}
	group_stack << 0

	i = 0
	for i < in_txt.len {
		mut char_tmp := u32(0)
		mut char_len := 0

		// println("i: ${i:3d} ch: ${in_txt.str[i]:c}")
		char_tmp, char_len = re.get_char(in_txt, i)

		//
		// check special cases: $ ^
		//
		if i == 0 && char_len == 1 && u8(char_tmp) == `^` {
			re.flag = regex.f_ms
			i = i + char_len
			continue
		}
		if i == (in_txt.len - 1) && char_len == 1 && u8(char_tmp) == `$` {
			re.flag = regex.f_me
			i = i + char_len
			continue
		}

		//
		// Group start
		//
		if char_len == 1 && pc >= 0 && u8(char_tmp) == `(` {
			tmp_res, cgroup_flag, negate_flag, cgroup_name, next_i := re.parse_groups(in_txt, i)

			// manage question mark format error
			if tmp_res < -1 {
				return regex.err_group_qm_notation, next_i
			}

			// println("Parse group: [$tmp_res, $cgroup_flag, ($i,$next_i), '${in_txt[i..next_i]}' ]")

			group_index++
			if cgroup_flag == true {
				group_count++
			}
			group_stack << group_count

			re.prog[pc].ist = regex.ist_group_start
			re.prog[pc].rep_min = 0
			re.prog[pc].rep_max = 1
			re.prog[pc].source_index = i
			re.prog[pc].group_id = group_count
			//re.prog[pc].save_state = true
			re.groups << Group{
				id:group_count,
				pc_start:pc,
				source_is:i
			}
			
			pc = pc + 1
			i = next_i
			continue
		}

		//
		// Group end
		//
		if char_len == 1 && pc > 0 && u8(char_tmp) == `)` {
			if group_index <= 0 {
				return regex.err_group_not_balanced, i
			}

			group_id := group_stack[group_index]
			
			re.prog[pc].ist = regex.ist_group_end
			re.prog[pc].rep_min = 1
			re.prog[pc].rep_max = 1
			re.prog[pc].source_index = i
			re.prog[pc].group_id = group_id
			
			re.prog[pc].group_start_pc = re.groups[group_id].pc_start
			re.prog[pc].group_end_pc = pc

			re.groups[group_id].pc_end = pc
			re.groups[group_id].source_ie = i

			//group_count--
			group_index--
			pc = pc + 1
			i = i + char_len
			continue
		}

		//
		// Quantifiers
		//
		if char_len == 1 && pc > 0 {
			mut char_next := rune(0)
			mut char_next_len := 0
			if (char_len + i) < in_txt.len {
				char_next, char_next_len = re.get_char(in_txt, i + char_len)
			}
			mut quant_flag := true

			match u8(char_tmp) {
				`?` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					re.prog[pc - 1].rep_min = 0
					re.prog[pc - 1].rep_max = 1
				}
				`+` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					re.prog[pc - 1].rep_min = 1
					re.prog[pc - 1].rep_max = regex.max_quantifier
				}
				`*` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					re.prog[pc - 1].rep_min = 0
					re.prog[pc - 1].rep_max = regex.max_quantifier
				}
				`{` {
					min, max, tmp, greedy := re.parse_quantifier(in_txt, i + 1)
					// it is a quantifier
					if min >= 0 {
						// println("{$min,$max}\n str:[${in_txt[i..i+tmp]}] greedy:$greedy")
						i = i + tmp
						re.prog[pc - 1].rep_min = min
						re.prog[pc - 1].rep_max = max
						re.prog[pc - 1].greedy = greedy
						// check illegal quantifier sequences
						if i <= in_txt.len {
							char_next, char_next_len = re.get_char(in_txt, i)
							if char_next_len == 1 && char_next in regex.quntifier_chars {
								return regex.err_syntax_error, i
							}
						}
						continue
					} else {
						return min, i
					}

					// TODO: decide if the open bracket can be conform without the close bracket
					/*
					// no conform, parse as normal char
					else {
						quant_flag = false
					}
					*/
				}
				else {
					quant_flag = false
				}
			}

			if quant_flag {
				i = i + char_len
				continue
			}
		}

		//
		// OR branch
		//
		if char_len == 1 && pc > 0 && u8(char_tmp) == `|` {
			char_next, char_next_len := re.get_char(in_txt, i + char_len)
			if char_next_len == 1 && !(char_next in quntifier_chars) && char_next != `|` {
				re.prog[pc - 1].or_flag = true
				i = i + char_len
				continue
			}
			return regex.err_syntax_error, i + char_next_len
		}

		//
		// ist_dot_char
		//
		if char_len == 1 && pc >= 0 && u8(char_tmp) == `.` {
			re.prog[pc].ist = u32(0) | regex.ist_dot_char
			re.prog[pc].rep_min = 1
			re.prog[pc].rep_max = 1
			re.prog[pc].source_index = i
			re.prog[pc].group_id = group_count
			pc = pc + 1
			i = i + char_len
			continue
		}

		//
		// ist_char_class
		//
		if char_len == 1 && pc >= 0 {
			if u8(char_tmp) == `[` {
				cc_index, tmp, cc_type := re.parse_char_class(in_txt, i + 1)
				if cc_index >= 0 {
					// println("index: $cc_index str:${in_txt[i..i+tmp]}")
					i = i + tmp
					re.prog[pc].ist = u32(0) | cc_type
					re.prog[pc].cc_index = cc_index
					re.prog[pc].rep_min = 1
					re.prog[pc].rep_max = 1
					re.prog[pc].source_index = i
					re.prog[pc].group_id = group_count
					pc = pc + 1
					continue
				}
				// cc_class vector memory full
				else if cc_index < 0 {
					return cc_index, i
				}
			}
		}

		//
		// ist_bsls_char
		//
		if char_len == 1 && pc >= 0 {
			if u8(char_tmp) == `\\` {
				bsls_index, tmp := re.parse_bsls(in_txt, i)
				// println("index: $bsls_index str:${in_txt[i..i+tmp]}")
				if bsls_index >= 0 {
					i = i + tmp
					re.prog[pc].ist = regex.ist_bsls_char
					re.prog[pc].rep_min = 1
					re.prog[pc].rep_max = 1
					re.prog[pc].validator = regex.bsls_validator_array[bsls_index].validator
					re.prog[pc].ch = regex.bsls_validator_array[bsls_index].ch
					re.prog[pc].source_index = i
					re.prog[pc].group_id = group_count
					pc = pc + 1
					continue
				}
				// this is an escape char, skip the bsls and continue as a normal char
				else if bsls_index == regex.no_match_found {
					i += char_len
					char_tmp, char_len = re.get_char(in_txt, i)
					// continue as simple char
				}
				// if not an escape or a bsls char then it is an error (at least for now!)
				else {
					return bsls_index, i + tmp
				}
			}
		}

		//
		// ist_simple_char
		//
		re.prog[pc].ist = regex.ist_simple_char
		re.prog[pc].ch = char_tmp
		re.prog[pc].ch_len = u8(char_len)
		re.prog[pc].rep_min = 1
		re.prog[pc].rep_max = 1
		re.prog[pc].source_index = i
		re.prog[pc].group_id = group_count
		// println("char: ${char_tmp:c}")
		pc = pc + 1

		i += char_len
	}

	// add END OF THE PROGRAM token
	re.prog[pc].ist = regex.ist_prog_end
	re.prog_len = pc

	// manage error for group not closed
	if group_index > 0 {
		// println("group_count: ${group_count}")
		src_i := re.groups[re.groups.len - group_index - 2].source_is
		return regex.err_group_not_balanced, src_i
	}

	//******************************************
	// Post processing
	//******************************************
	
	// add save_state flag to all token with more then 1 repetitions
	pc = 0
	mut last_save_state_pc := -1
	mut save_state_count := 0
	for pc < re.prog_len {
		// if the next token is a token that doesn't require save state
		// avoid to save the state
		if re.prog[pc].rep_max > 1 
		//&& !(re.prog[pc + 1].ist in [regex.ist_group_end, regex.ist_prog_end])
		{
			re.prog[pc].save_state = true
			last_save_state_pc = pc
			save_state_count++
		}
		pc++
	}

	// with only one have no sense to store the state
	if save_state_count > 1 {
		re.prog[last_save_state_pc].save_state = false
	}
	
	//******************************************
	// DEBUG PRINT REGEX GENERATED CODE
	//******************************************
	if re.debug > 0 {
		gc := re.get_code()
		re.log_func(gc)
	}
	//******************************************

	return compile_ok, 0
}