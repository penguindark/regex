import regex
import rand
import strings

/******************************************************************************
*
* Test section
*
******************************************************************************/
struct TestItem {
	src string
	q   string
	s   int
	e   int
}

const(
match_test_suite = [
	// simple tests
	TestItem{'a', r'a', 0, 1},
	TestItem{'', r'a', -1, -1},
	TestItem{'abc', r'abc', 0, 3},
	TestItem{"d.def",r"abc.\.[\w\-]{,100}",-1,-1},
	TestItem{"abc12345.asd",r"abc.\.[\w\-]{,100}",-1,-1},
	TestItem{"abca.exe",r"abc.\.[\w\-]{,100}",0,8},
	TestItem{"abc2.exe-test_12",r"abc.\.[\w\-]{,100}",0,16},
	TestItem{"abcdefGHK",r"[a-f]+\A+",0,9},
	TestItem{"ab-cd-efGHK",r"[a-f\-g]+\A+",0,11},

	// dot char
	//TestItem{"cpapaz ole. pippo,",r".*c.+ole.*pi",0,14},

	// base OR
	TestItem{"a",r"a|b",0,1},
	TestItem{"a",r"b|a",0,1},
	TestItem{"b",r"a|b",0,1},
	TestItem{"b",r"b|a",0,1},
	TestItem{"c",r"b|a",-1,-1},
	TestItem{"c",r"b|a|c",0,1},
	TestItem{"ca",r"b|a|c",0,1},
	TestItem{"ca",r"b|a|ca",0,2},
	TestItem{"ca",r"b|a|ca#?",0,2},
	TestItem{"ca#",r"b|a|ca#?",0,3},
	TestItem{"ca# ",r"b|a|ca#?",0,3},

	// test base
	TestItem{"[ciao]",r"(.)ciao(.)",0,6},
	TestItem{"[ciao] da me",r"(.)ciao(.)",0,6},
]
)
fn test_match_test_suite(){
	for count, pattern in match_test_suite {
		println("#: $count")
		mut re := regex.regex_opt(pattern.q) or { panic(err) }
		start, end := re.match_base(pattern.src.str, pattern.src.len)
		assert (start == pattern.s) && (end == pattern.e), "error: $pattern"
	}
}
