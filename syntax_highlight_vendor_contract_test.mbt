///|
extern "C" fn syntax_highlight_vendor_contract_ffi() -> Int =
  "pumd_syntax_highlight_vendor_contract"

///|
test "bundled syntax highlighter vendor contract has every canonical parser asset" {
  assert_eq(syntax_highlight_vendor_contract_ffi(), 16)
}
