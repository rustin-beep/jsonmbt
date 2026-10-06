// 探针 C：.json.mbt 字面量 → JSON（节点名从 parser@0.4.3 mbti 校准：
// struct 字面量 = Expr::Record(type_name~, fields~)；字面量 = Constant）
// 形态：递归 expr → JSON String（最小验证：能对 Record/Array/Constant 出合法 JSON）

///|
fn json_escape(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn expr_to_json(e : @syntax.Expr) -> String {
  match e {
    @syntax.Expr::Record(fields~, ..) => {
      // 类型名剥除（Server { ... } → { ... }）——.json.mbt 的核心降级语义
      let buf = StringBuilder()
      buf.write_string("{")
      let n = fields.length()
      let mut i = 0
      for f in fields {
        buf.write_string("\"")
        buf.write_string(f.label.name)
        buf.write_string("\":")
        buf.write_string(expr_to_json(f.expr))
        if i < n - 1 {
          buf.write_string(",")
        }
        i += 1
      }
      buf.write_string("}")
      buf.to_string()
    }
    @syntax.Expr::Array(exprs~, ..) => {
      let buf = StringBuilder()
      buf.write_string("[")
      let n = exprs.length()
      let mut i = 0
      for e2 in exprs {
        buf.write_string(expr_to_json(e2))
        if i < n - 1 {
          buf.write_string(",")
        }
        i += 1
      }
      buf.write_string("]")
      buf.to_string()
    }
    @syntax.Expr::Constant(c~, ..) =>
      match c {
        @syntax.Constant::Int(raw) => raw
        @syntax.Constant::Double(raw) => raw
        @syntax.Constant::Bool(b) => if b { "true" } else { "false" }
        @syntax.Constant::String(raw) => "\"" + json_escape(raw) + "\""
        @syntax.Constant::Int64(raw) => raw
        _ => "null"
      }
    // 非字面量子集的表达式（函数调用等）→ null 占位（探针口径；正式版报诊断）
    _ => "null"
  }
}
