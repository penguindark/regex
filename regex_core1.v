module regex


// get_char get a char from position i and return an u32 with the unicode code
[direct_array_access; inline]
fn get_char(in_txt string, i int) (u32, int) {
	ini := unsafe { in_txt.str[i] }
	// ascii 8 bit
	if /*(re.flag & regex.f_bin) != 0 ||*/ ini & 0x80 == 0 {
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

const (
	// max 65355 groups
	group_start   = 0x0001_0000
	group_end     = 0x0002_0000
	concatenation = 0x0004_0000
	postfix_or    = 0x0008_0000
)

struct Paren{
mut:
	nalt i32
	natom i32
}

struct PostfixToken {
mut:
	ch rune
	fcode u32
}

pub
fn (re REcontext) re2post(in_re_str string) []PostfixToken {
	mut buf     := []PostfixToken
	mut c       := 0
	mut nalt    := 0
	mut natom   := 0
	mut paren   := []Paren{len:in_re_str.len}
	mut p_index := 0
	mut group_count := u32(0)

	for c < in_re_str.len {
		ch, ch_len := get_char(in_re_str, c)
		match u8(ch) {
			`|` {
				if natom == 0 {
					return []PostfixToken
				}
				natom--
				for natom > 0 {
					buf << PostfixToken{ch:`|`, fcode: concatenation }
					natom--
				}
				nalt++
			}
			`(` {
				group_count++
				if natom > 1 {
					natom--
					buf << PostfixToken{ch:`.`, fcode: concatenation }
				}
				buf << PostfixToken{ch:`(`, fcode: group_start | group_count}
				paren[p_index].nalt  = nalt
				paren[p_index].natom = natom
				p_index++
				nalt  = 0
				natom = 0
			}
			`)` {
				if p_index == 0 {
					return []PostfixToken
				}
				if natom == 0 {
					return []PostfixToken
				}
				natom--
				for natom > 0 {
					buf << PostfixToken{ch:`.`, fcode: concatenation | group_end | group_count}
					natom--
				}
				for nalt > 0 {
					buf << PostfixToken{ch:`|`, fcode: postfix_or | group_end | group_count}
					nalt--
				}
				buf << PostfixToken{ch:`)`, fcode: group_end | group_count}
				p_index--
				nalt  = paren[p_index].nalt
				natom = paren[p_index].natom
				natom++
				group_count--
			}
			`+`,`*`,`?` {
				if natom == 0 {
					return []PostfixToken
				}
				buf << PostfixToken{ch:ch}
			}

			// standard rune
			else {
				if natom > 1 {
					natom--
					buf << PostfixToken{ch:`.`, fcode: concatenation}
				}
				buf << PostfixToken{ch:ch}
				natom++
			}
		}
		c += ch_len
	}

	natom--
	for natom > 0 {
		buf << PostfixToken{ch:`.`, fcode: concatenation}
		natom--
	}
	for nalt > 0 {
		buf << PostfixToken{ch:`|`, fcode: concatenation }
		nalt--
	}

	return buf
}

pub fn (re REcontext) print_runes(in_rune_list []PostfixToken) {
	for x in in_rune_list {
		print(utf8_str(x.ch))
		/*
		if x.fcode & 0xFFFF_0000 > 0 {
			print("[${x.fcode >> 16:04X}|${x.fcode&0xFFF:02}]")
		}
		*/
	}
	println("")
}

/*
*
* State 
*
*/

const (
	re_match = 0x0001
	re_split = 0x0002
)

[heap]
struct MatchState {
mut:
	ch rune
	fcode u32
	out0 int = -1
	out1 int = -1
	last_list int

	list_index int = -1
}

pub
struct REcontext {
mut:
	nstate int
	frag_stack [10]int
	frag_stack_index int
	
	state_list []MatchState


}

fn (mut re REcontext) patch(index_e1 int, index_e2 int) {
	mut i := index_e1
	for re.state_list[i].out0 != -1 {
		i = re.state_list[i].out0
	}
	re.state_list[i].out0 = index_e2
}


fn (mut re REcontext) append(index_e1 int, index_e2 int) {
	mut i := index_e1
	for re.state_list[i].out0 != -1 {
		i = re.state_list[i].out0
	}
}

//
// Convert postfix regular expression to NFA.
// Return start state.
//
pub
fn (mut re REcontext) post_to_nfa(ps_list []PostfixToken) {
unsafe {
	mut s := &MatchState(nil) 
	for p in ps_list {

		// . concatenation
		if (p.fcode & concatenation) > 0 {
			re.frag_stack_index--
			ind_e2 := re.frag_stack[re.frag_stack_index]
			re.frag_stack_index--
			ind_e1 := re.frag_stack[re.frag_stack_index]
			re.patch(ind_e1, ind_e2)

			re.frag_stack[re.frag_stack_index] = re.state_list[ind_e2].list_index
			re.frag_stack_index++

			println("list concat => ${re.frag_stack} index: ${re.frag_stack_index}")
		} else

		// | operator
		if (p.fcode & postfix_or) > 0 {
			re.frag_stack_index--
			ind_e2 := re.frag_stack[re.frag_stack_index]
			re.frag_stack_index--
			ind_e1 := re.frag_stack[re.frag_stack_index]
			re.patch(ind_e1, ind_e2)
			re.state_list[ind_e1].out1 = ind_e2
			
			re.frag_stack[re.frag_stack_index] = re.state_list[ind_e2].list_index
			re.frag_stack_index++
			
		} else

		if p.fcode == 0 {
			re.nstate++
			re.state_list	<< MatchState{
				ch: p.ch,
				list_index:  re.state_list.len
			}
			re.frag_stack[re.frag_stack_index] = re.state_list.len - 1
			re.frag_stack_index++
			println("list ch     => ${re.frag_stack} index: ${re.frag_stack_index}")
		}
		
	}

	// Add the end match state
	re.nstate++
	re.state_list	<< MatchState{
		fcode: re_match,
		list_index:  re.state_list.len
	}
	re.frag_stack[re.frag_stack_index] = re.state_list.len - 1
	re.frag_stack_index++
	
	re.frag_stack_index--
	ind_e2 := re.frag_stack[re.frag_stack_index]
	re.frag_stack_index--
	ind_e1 := re.frag_stack[re.frag_stack_index]
	re.patch(ind_e1, ind_e2)

	println(re.state_list)
}
}
