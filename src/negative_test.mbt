// J 系负样本锚（每码至少一条；红→绿纪律的绿面固化）
// 锚的期望文本 = 诊断 render 的机器可读前缀形态（D-10 契约）
// 行列值以 parser 实测为准锚死——工具链升级若动位置，此锚即红（R1 对冲）

///|
fn expect_diag(
  src : String,
  expected : String,
  path? : String = "t.json.mbt",
) -> Unit {
  let d = try {
    let _ = @src.build_source(src, path~, expected_name="t")
    // 走到这里说明本应失败——inspect 用占位串保证红
    "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("unexpected error type") }
  }
  if d != expected {
    println("MISMATCH\nexpected: \{expected}\nactual:   \{d}")
    abort("diagnostic mismatch")
  }
}

///|
test "J1001 : 语法错转发 parser 报告" {
  let src = "pub let t = {"
  expect_diag(
    src, "jsonmbt: error [J1001] t.json.mbt:1:14 Unexpected end of file, missing simple expression here.\n  help: keep the file valid MoonBit: struct defs + one top-level pub let of literals",
  )
}

///|
test "J2001 : 缺顶层 pub let" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
  expect_diag(
    src, "jsonmbt: error [J2001] t.json.mbt:1:1 no top-level pub let binding\n  help: add `pub let <file-stem> = ...` — the file degrades to one JSON document",
  )
}

///|
test "J2002 : 多个顶层 pub let" {
  let src =
    #|pub let t = 1
    #|pub let u = 2
  expect_diag(
    src, "jsonmbt: error [J2002] t.json.mbt:2:1 multiple top-level pub let bindings\n  help: one .json.mbt file degrades to exactly one JSON document (D-7)",
  )
}

///|
test "J2003 : stem 不符（stdin 免检由 CLI 面覆盖）" {
  let src = "pub let other = 1"
  expect_diag(
    src, "jsonmbt: error [J2003] t.json.mbt:1:1 top-level binding is 'other' but the file stem is 't'\n  help: rename the binding (or the file) so they match — this keeps one name per document",
  )
}

///|
test "J2004 : 嵌套深度超预算" {
  // 129 层嵌套数组（预算 128）
  let mut src = "pub let t = "
  let mut tail = ""
  for i = 0; i < 129; i = i + 1 {
    src = src + "["
    tail = tail + "]"
  }
  src = src + "1" + tail
  expect_diag(
    src, "jsonmbt: error [J2004] t.json.mbt:1:142 nesting exceeds the depth budget of 128\n  help: flatten the data or split it into several .json.mbt files",
  )
}

///|
test "J2005 : 顶层非 struct/pub let 声明" {
  let src =
    #|fn f() -> Int {
    #|  1
    #|}
    #|
    #|pub let t = 1
  expect_diag(
    src, "jsonmbt: error [J2005] t.json.mbt:1:1 top-level fn declaration\n  help: a .json.mbt file contains struct definitions and one pub let — nothing else",
  )
}

///|
test "J2006 : 重复 struct 定义" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|struct T {
    #|  b : Int
    #|}
    #|
    #|pub let t : T = T::{ a: 1 }
  expect_diag(
    src, "jsonmbt: error [J2006] t.json.mbt:5:1 duplicate struct definition 'T'\n  help: rename one of the structs; .json.mbt keeps one schema per name",
  )
}

///|
test "J2007 : 字段类型超出 L0 支持面" {
  let src =
    #|struct T {
    #|  a : (Int, Int)
    #|}
    #|
    #|pub let t : T = T::{ a: (1, 2) }
  expect_diag(
    src, "jsonmbt: error [J2007] t.json.mbt:2:3 field type is outside the L0 subset\n  help: supported field types: Int/Int64/Double/String/Bool/T? (Option)/Array[T]/Map[String,T]/struct",
  )
}

///|
test "J3002 : Map 键非字符串" {
  let src = "pub let t = { 1: \"a\" }"
  expect_diag(
    src, "jsonmbt: error [J3002] t.json.mbt:1:15 map key must be a string literal, got Int\n  help: JSON object keys are strings; quote the key",
  )
}

///|
test "J3003 : Char 字面量无 JSON 对应" {
  let src = "pub let t = 'x'"
  expect_diag(
    src, "jsonmbt: error [J3003] t.json.mbt:1:13 Char literal has no JSON counterpart\n  help: JSON values are null/bool/number/string/array/object only",
  )
}

///|
test "J3004 : 字段类型不匹配（PLAN §4 的原型例）" {
  let src =
    #|struct T {
    #|  port : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  port: "443",
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:9 expects Int, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}

///|
test "J3004 : Int 界外上浮提示（D-2）" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 3000000000,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:6 expects Int (32-bit), got 3000000000\n  help: change the field type to Int64, or use a value within ±2147483647",
  )
}

///|
test "J3004 : 超 Int64 诚实拒绝（D-2）" {
  let src =
    #|struct T {
    #|  a : Int64
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 99999999999999999999,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:6 expects Int64, got 99999999999999999999\n  help: the value exceeds Int64; keep exact digits by storing a String explicitly",
  )
}

///|
test "J3005 : 未知字段" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 1,
    #|  b: 2,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3005] t.json.mbt:7:3 unknown field 'b'\n  help: struct 'T' has fields: a",
  )
}

///|
test "J3006 : 缺必填字段" {
  let src =
    #|struct T {
    #|  a : Int
    #|  b : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 1,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3006] t.json.mbt:6:17 missing field 'b' in 'T'\n  help: provide the field explicitly; T? (Option) fields use None",
  )
}

///|
test "J3007 : Map 重复键拒绝（D-11：JSON 层重复键是病态输入）" {
  let src = "pub let t = { \"k\": 1, \"k\": 2 }"
  expect_diag(
    src, "jsonmbt: error [J3007] t.json.mbt:1:23 duplicate key \"k\"\n  help: merge the two entries; a degraded object never carries duplicate keys",
  )
}

///|
test "J1002 : JSON 输入语法错（normalize_json_text）" {
  let d = try {
    let _ = @src.normalize_json_text("{,}")
    "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("unexpected error type") }
  }
  let ok = d != "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED" && d.contains("J1002")
  inspect(ok, content="true")
}

///|
test "P2-6② : Some(v) 内层期望类型校验判别（Int? 字段给 Some(\"x\")）" {
  let src =
    #|struct T {
    #|  opt : Int?
    #|}
    #|
    #|pub let t : T = T::{
    #|  opt: Some("x"),
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:13 expects Int, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}

///|
test "J2007 : 嵌套 Option（T??）收窄——静默压平是无损红线违例（#14-1 批次1）" {
  // 现状实测：String?? 下 None 与 Some(None) 都降级 "a":null——信息静默
  // 压平（§0 解压无损 + D-8② 违例）。三态定义（缺席/null/值）走 §8 正式
  // 评审；在此之前嵌套 Option 一律 J2007 fail loud（递归拒任意深度——
  // 推断链只加一层 Option，此面纯手写，现存绿文件零影响）
  // 形态①：直接 T??
  expect_diag(
    "struct S {\n  a : String??\n}\npub let t : S = S::{ a: None }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
  // 形态②：容器位嵌套（Array 元素类型——JSON 容器位结构上无法缺席，
  // 三态评审落地前一并收窄）
  expect_diag(
    "struct S {\n  b : Array[Int??]\n}\npub let t : S = S::{ b: [] }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
  // 形态③：三层（递归口径一次说清）
  expect_diag(
    "struct S {\n  c : Int???\n}\npub let t : S = S::{ c: None }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
}
