// .json.mbt 生成器（importer 出口）：InferResult + 值树 → 源文件全文
// 格式 = moon fmt canonical（全部形态 fmt-stable 实测锚定，PLAN §9）：
//   struct 头字段每行 / 顶层 record 多行 / 嵌套 record 与数组元素内联单行 /
//   长行不折（fmt 不折 >84 宽的单行值体）
// 头部 @generated 标注（纪律 11，Vitro 形态）：不写时间/版本——确定性硬锚
// （同输入两次 import 逐字节一致）的前提

///|
/// MoonBit 浮点字面量文法适配（探针⑥：纯整数尾数接指数解析错，须带小数点——
/// 陷阱 #13 勘误）：JSON 合法的 1e2 / 1E6 / -1e3 在 .json.mbt 层写不成——
/// 最小改写 = 尾数补 ".0"（审 P1-1）
fn ensure_double_syntax(repr : String) -> String {
  let view = repr[:]
  let n = view.length()
  let mut e_at = -1
  for i = 0; i < n; i = i + 1 {
    if view[i] == 'e' || view[i] == 'E' {
      e_at = i
      break
    }
  }
  if e_at < 0 {
    return repr
  }
  // e 之前的尾数若不含 '.'：在 e 前插入（符号/整数尾数均可）
  if view[0:e_at].contains(".") {
    return repr
  }
  repr[:e_at].to_owned() + ".0" + repr[e_at:].to_owned()
}

///|
/// 解码值 → MoonBit 字面量转义（unescape 的逆向；\u{XX} 小写 hex 惯例）
fn moonbit_escape(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      other =>
        if other.to_int() < 0x20 {
          // 三段运行时拼接：MoonBit 字符串里 \\ 会吃掉紧随的 \{ 插值——
          // 写成单串插值会整段源码落盘（审 P1-2 根因）
          buf.write_string("\\u{")
          buf.write_string(other.to_int().to_string())
          buf.write_string("}")
        } else {
          buf.write_char(other) // 非 ASCII 按 UTF-8 原样（源文件即 UTF-8）
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// struct 定义段（字段每行——fmt canonical）
fn render_struct_def(name : String, fields : Array[(String, JType)]) -> String {
  let buf = StringBuilder()
  // pub struct（审 P2-5）：priv struct 每字段一条 unused_field 警告噪音，
  // 且 moon info 对 priv 只给不透明 type——schema 出口（P1.5 余项）依赖 pub
  buf.write_string("pub struct ")
  buf.write_string(name)
  buf.write_string(" {\n")
  for f in fields {
    buf.write_string("  ")
    buf.write_string(f.0)
    buf.write_string(" : ")
    buf.write_string(f.1.show())
    buf.write_string("\n")
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
/// struct 字段类型表（渲染上下文）
type StructTable = Map[String, Array[(String, JType)]]

///|
fn build_struct_table(
  structs : Array[(String, Array[(String, JType)])],
) -> StructTable {
  let table : StructTable = Map([])
  for s in structs {
    table[s.0] = s.1
  }
  table
}

///|
fn struct_field_type(
  table : StructTable,
  sname : String,
  label : String,
) -> JType? {
  match table.get(sname) {
    Some(fields) =>
      match fields.iter().find_first(fn(f) { f.0 == label }) {
        Some((_, t)) => Some(t)
        None => None
      }
    None => None
  }
}

///|
/// 值渲染（期望类型驱动；嵌套一律内联单行）
fn render_value(
  table : StructTable,
  j : Json,
  ty : JType?,
) -> String raise Diag {
  match (j, ty) {
    (Null, _) => "None" // 自由 null；非 Option 期望在推断层不会出现（防御）
    (v, Some(JTOption(t))) => "Some(\{render_value(table, v, Some(t))})"
    (True, _) => "true"
    (False, _) => "false"
    (Number(_, repr~), _) =>
      match repr {
        Some(t) => ensure_double_syntax(t)
        None => "0" // 自持解析器产物恒带 repr；防御
      }
    (String(s), _) => moonbit_escape(s)
    (Array(elems), t) => {
      let elem_ty : JType? = match t {
        Some(JTArray(et)) => Some(et)
        _ => None
      }
      let parts : Array[String] = []
      for e in elems {
        parts.push(render_value(table, e, elem_ty))
      }
      "[\{parts.join(", ")}]"
    }
    (Object(o), Some(JTStruct(name))) => {
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      for k in ks {
        let v = o.get(k).unwrap()
        entries.push(
          "\{k}: \{render_value(table, v, struct_field_type(table, name, k))}",
        )
      }
      "\{name}::{ \{entries.join(", ")} }"
    }
    (Object(o), t) => {
      // Map 逃生门形态（推断产物的对象位只剩 Map 上下文）
      let vt : JType? = match t {
        Some(JTMap(_, v)) => Some(v)
        _ => None
      }
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      for k in ks {
        let v = o.get(k).unwrap()
        entries.push("\{moonbit_escape(k)}: \{render_value(table, v, vt)}")
      }
      "{ \{entries.join(", ")} }"
    }
  }
}

///|
/// 顶层值：struct record 多行（可读性）；其余形态内联
fn render_top_value(
  table : StructTable,
  j : Json,
  ty : JType?,
) -> String raise Diag {
  match (j, ty) {
    (Object(o), Some(JTStruct(name))) => {
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      for k in ks {
        let v = o.get(k).unwrap()
        entries.push(
          "\{k}: \{render_value(table, v, struct_field_type(table, name, k))}",
        )
      }
      let buf = StringBuilder()
      buf.write_string(name)
      buf.write_string("::{\n")
      for e in entries {
        buf.write_string("  ")
        buf.write_string(e)
        buf.write_string(",\n")
      }
      buf.write_string("}")
      buf.to_string()
    }
    _ => render_value(table, j, ty)
  }
}

///|
/// 生成 .json.mbt 全文（import 主出口；无时间/版本戳——确定性）
fn generate_source(
  result : InferResult,
  root : Json,
  stem~ : String,
  src_name~ : String,
) -> String raise Diag {
  let table = build_struct_table(result.structs)
  let buf = StringBuilder()
  buf.write_string(
    "// @generated by jsonmbt import —— 禁手改（再生成：jsonmbt import \{src_name}）。\n",
  )
  buf.write_string("// 源：\{src_name}\n\n")
  for s in result.structs {
    buf.write_string(render_struct_def(s.0, s.1))
    buf.write_string("\n")
  }
  match result.root_ty {
    Some(t) => {
      buf.write_string("pub let \{stem} : \{t.show()} = ")
      buf.write_string(render_top_value(table, root, Some(t)))
      buf.write_string("\n")
    }
    None => {
      buf.write_string("pub let \{stem} = ")
      buf.write_string(render_top_value(table, root, None))
      buf.write_string("\n")
    }
  }
  buf.to_string()
}
