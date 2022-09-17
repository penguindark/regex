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
	group_start = 0x1000_0000
	group_end   = 0x2000_0000
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
fn re2post(in_re_str string) []PostfixToken {
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
			`(` {
				group_count++
				if natom > 1 {
					natom--
					buf << PostfixToken{ch:`.`, fcode: group_start | group_count}
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
					buf << PostfixToken{ch:`.`, fcode: group_end | group_count}
					natom--
				}
				for nalt > 0 {
					buf << PostfixToken{ch:`|`, fcode: group_end | group_count}
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
					buf << PostfixToken{ch:`.`}
				}
				buf << PostfixToken{ch:ch}
				natom++
			}
		}
		c += ch_len
	}
	return buf
}

pub fn print_runes(in_rune_list []PostfixToken) {
	for x in in_rune_list {
		print(utf8_str(x.ch))
		/*
		if x.fcode & 0xFF00_0000 > 0 {
			print("[${x.fcode >> 24:02X}|${x.fcode&0xFFF:02}]")
		}
		*/
	}
	println("")
}