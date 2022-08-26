/*
regex 2.0 alpha

Copyright (c) 2019-2022 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains regex structs and base const

Know limitation:

*/
module regex

/******************************************************************************
*
* General Constants
*
******************************************************************************/
pub const (
	v_regex_version          = '2.0 alpha' // regex module version

	max_code_len             = 256 // default small base code len for the regex programs
	max_quantifier           = 1073741824 // default max repetitions allowed for the quantifiers = 2^30

	// spaces chars (here only westerns!!) TODO: manage all the spaces from unicode
	spaces                   = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
	// new line chars for now only '\n'
	new_line_list            = [`\n`, `\r`]

	// Results
	no_match_found           = -1

	// Errors
	compile_ok               =  0 // the regex string compiled, all ok
	err_char_unknown         = -2 // the char used is unknow to the system
	err_undefined            = -3 // the compiler symbol is undefined
	err_internal_error       = -4 // Bug in the regex system!!
	err_cc_alloc_overflow    = -5 // memory for char class full!!
	err_syntax_error         = -6 // syntax error in regex compiling
	err_groups_overflow      = -7 // max number of groups reached
	err_groups_max_nested    = -8 // max number of nested group reached
	err_group_not_balanced   = -9 // group not balanced
	err_group_qm_notation    = -10 // group invalid notation
	err_invalid_or_with_cc   = -11 // invalid or on two consecutive char class
	err_neg_group_quantifier = -12 // negation groups can not have quantifier
	err_consecutive_dots     = -13 // two consecutive dots is an error
)

pub fn (re RE) get_parse_error_string(err int) string {
	match err {
		regex.compile_ok { return 'compile_ok' }
		regex.no_match_found { return 'no_match_found' }
		regex.err_char_unknown { return 'err_char_unknown' }
		regex.err_undefined { return 'err_undefined' }
		regex.err_internal_error { return 'err_internal_error' }
		regex.err_cc_alloc_overflow { return 'err_cc_alloc_overflow' }
		regex.err_syntax_error { return 'err_syntax_error' }
		regex.err_groups_overflow { return 'err_groups_overflow' }
		regex.err_groups_max_nested { return 'err_groups_max_nested' }
		regex.err_group_not_balanced { return 'err_group_not_balanced' }
		regex.err_group_qm_notation { return 'err_group_qm_notation' }
		regex.err_invalid_or_with_cc { return 'err_invalid_or_with_cc' }
		regex.err_neg_group_quantifier { return 'err_neg_group_quantifier' }
		regex.err_consecutive_dots { return 'err_consecutive_dots' }
		else { return 'err_unknown' }
	}
}

const (
	//*************************************
	// regex program instructions
	//*************************************
	ist_simple_char    = u32(0x0001) // single char instruction, 31 bit available to char
	// char classes
	ist_char_class_pos = u32(0x0002) // char class normal [abc]
	ist_char_class_neg = u32(0x0003) // char class negate [^abc]
	// dot char        
	ist_dot_char       = u32(0x0004) // match any char except \n
	// backslash chars 
	ist_bsls_char      = u32(0x0005) // backslash char
	// OR |            
	ist_or_branch      = u32(0x0006) // OR case
	// groups         
	ist_group_start    = u32(0x0007) // group start (
	ist_group_end      = u32(0x0008) // group end   )
	// control instructions
	ist_prog_end       = u32(0xFFFF) // block end
	//*************************************
)

/******************************************************************************
*
* Token Structs
*
******************************************************************************/
pub type FnValidator = fn (u8) bool

pub
struct Token {
mut:
	ist u32
	
	// char
	ch     rune // char of the token if any
	ch_len u8   // char len
	
	// Quantifiers
	rep_min int  // used also for jump next in the OR branch [no match] pc jump
	rep_max int  // used also for jump next in the OR branch [   match] pc jump
	greedy  bool // greedy quantifier flag
	
	// Char class
	cc_index int = -1

	// if true we have an OR ist as next
	or_flag bool

	// flag to enabel save state on this token if rep_max > 1
	save_state bool

	// validator function pointer
	validator FnValidator
	// groups variables
	group_id  int = -1 // id of the group
	group_start_pc int
	group_end_pc int

	// debug fields
	source_index int
}

/******************************************************************************
*
* Groups
*
******************************************************************************/
struct Group {
mut:
	// group data
	id int
	name string
	source_is int = 0
	source_ie int = 0
	pc_start int = -1
	pc_end   int = -1
	// match indexes
	i_start  int = -1
	i_end    int = -1
	i_tmp_start int = -1
	// repetitions
}

/******************************************************************************
*
* Regex struct
*
******************************************************************************/
pub const (
	f_nl  = 0x00000001 // end the match when find a new line symbol
	f_ms  = 0x00000002 // match true only if the match is at the start of the string
	f_me  = 0x00000004 // match true only if the match is at the end of the string

	f_efm = 0x00000100 // exit on first token matched, used by search
	f_bin = 0x00000200 // work only on bytes, ignore utf-8
	
	// behaviour modifier flags
	f_src = 0x00020000 // search mode enabled
)

// Log function prototype
pub type FnLog = fn (string)


pub struct RE {
pub mut:
	prog     []Token
	prog_len int // regex program len
	// char classes storage
	cc       []CharClass // char class list
	cc_index int // index

	// repetitions data array
	rep      [][]int

	// groups
	groups []Group

	// flags
	flag int // flag for optional parameters
	// Debug/log
	debug    int    // enable in order to have the unroll of the code 0 = NO_DEBUG, 1 = LIGHT 2 = VERBOSE
	log_func FnLog = simple_log // log function, can be customized by the user
	query    string // query string
}