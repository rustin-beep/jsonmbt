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
/// 字符串值渲染（#26 教师循环形态保真）：含 \n 的长文案产 `#|` 多行
/// （值位括号包裹 + 无前导空格规范形——moon 语义 `#| x` 空格入值，不产
/// 即不引入；回写不再把手写多行形态磨损成单行转义长串）；单行值保持
/// 转义形态。fmt 幂等（探针 2026-10-10：构造器/字段/Map 值/数组/Some
/// 位全合法，fmt 归一为值位括号 + 缩进 #|，二次 fmt 不动）。含 \r 的
/// 值不走多行——CRLF 行尾 \r 入值的语义在读取层有歧面，转义保真
fn render_string_value(s : String) -> String {
  if s.contains("\n") && !s.contains("\r") {
    let buf = StringBuilder()
    buf.write_string("(\n")
    for line in s.split("\n") {
      buf.write_string("#|")
      buf.write_string(line.to_owned())
      buf.write_string("\n")
    }
    buf.write_string(")")
    buf.to_string()
  } else {
    moonbit_escape(s)
  }
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
/// field-alias 反查表（渲染上下文，#13）：键 "Struct\u{1}json键" → 改名后
/// label——数据字面量的构造字段名与类型查表都走改名后形态
type AliasTable = Map[String, String]

///|
fn build_alias_table(aliases : Array[(String, String, String)]) -> AliasTable {
  let tab : AliasTable = Map([])
  for a in aliases {
    let (sname, label, key) = a
    tab["\{sname}\u{1}\{key}"] = label
  }
  tab
}

///|
fn alias_field_label(tab : AliasTable, sname : String, key : String) -> String {
  match tab.get("\{sname}\u{1}\{key}") {
    Some(label) => label
    None => key
  }
}

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
/// struct 的隐含 JSON 键集（label 经 alias 逆映射 = json 键；无注记则恒等）
fn implied_json_keys(
  atab : AliasTable,
  sname : String,
  labels : Array[String],
) -> Array[String] {
  // atab 键 = "sname\u{1}json键" → value = label；反查 label → json 键
  let rev : Map[String, String] = Map([])
  atab.each(fn(k, label) {
    let sep = k.find("\u{1}")
    match sep {
      Some(i) =>
        if k[:i].to_owned() == sname {
          rev[label] = k[i + 1:].to_owned()
        }
      None => ()
    }
  })
  labels.map(fn(l) {
    match rev.get(l) {
      Some(k) => k
      None => l
    }
  })
}

///|
/// fill 严格校验：JSON 键集必须与 struct 隐含键集精确一致（多余 J3005 /
/// 缺失 J3006——「按已声明类型重算」语境下静默忽略 = 数据不同步吞错）
fn strict_check_keys(
  table : StructTable,
  atab : AliasTable,
  sname : String,
  ks : Array[String],
) -> Unit raise Diag {
  let labels : Array[String] = []
  match table.get(sname) {
    Some(fs) =>
      for f in fs {
        labels.push(f.0)
      }
    None => ()
  }
  let implied = implied_json_keys(atab, sname, labels)
  // 多余
  for k in ks {
    if !implied.contains(k) {
      raise Diag(
        code=JUnknownField,
        loc=dummy_loc(),
        message="unknown field '\{k}' — struct '\{sname}' declares: \{implied.join(", ")}",
        help=Some(
          "the source JSON has keys the declared type does not cover — update the struct header or the JSON",
        ),
        path="",
      )
    }
  }
  // 缺失
  for k in implied {
    if !ks.contains(k) {
      raise Diag(
        code=JMissingField,
        loc=dummy_loc(),
        message="missing field '\{k}' in '\{sname}' — declared in the type header but absent from the source JSON",
        help=Some(
          "fill only rewrites the value body; add the key to the JSON or drop it from the struct",
        ),
        path="",
      )
    }
  }
}

///|
/// 值渲染（期望类型驱动；嵌套一律内联单行）。strict_keys（#14-2b fill）：
/// 声明类型语境——struct 键集精确校验 + enum 按键集/tag 选变体；缺省
/// false = import 主路径现行为（推断产物与数据天然一致，无需校验）
fn render_value(
  table : StructTable,
  atab : AliasTable,
  j : Json,
  ty : JType?,
  enums? : Map[String, EnumDef] = Map([]),
  strict_keys? : Bool = false,
) -> String raise Diag {
  match (j, ty) {
    (Null, _) => "None" // 自由 null；非 Option 期望在推断层不会出现（防御）
    (v, Some(JTOption(t))) =>
      "Some(\{render_value(table, atab, v, Some(t), enums~, strict_keys~)})"
    (True, _) => "true"
    (False, _) => "false"
    (Number(_, repr~), _) =>
      match repr {
        Some(t) => ensure_double_syntax(t)
        None => "0" // 自持解析器产物恒带 repr；防御
      }
    (String(s), Some(JTEnum(n))) if strict_keys =>
      // fill：JSON 值 = 变体名字符串（D-5 无参变体的降级投影）→ 裸构造器
      match enums.get(n) {
        Some(def) =>
          if def.variants.contains(s) {
            s
          } else {
            raise Diag(
              code=JFieldType,
              loc=dummy_loc(),
              message="enum '\{n}' has no variant '\{s}'",
              help=Some("variants of '\{n}': \{def.variants.join(" ")}"),
              path="",
            )
          }
        None =>
          raise Diag(
            code=JFieldType,
            loc=dummy_loc(),
            message="enum '\{n}' is not defined in this file",
            help=Some(
              ".json.mbt is single-file; declare the enum alongside the structs",
            ),
            path="",
          )
      }
    (String(s), _) => render_string_value(s)
    (Array(elems), t) => {
      let elem_ty : JType? = match t {
        Some(JTArray(et)) => Some(et)
        _ => None
      }
      let parts : Array[String] = []
      for e in elems {
        parts.push(render_value(table, atab, e, elem_ty, enums~, strict_keys~))
      }
      // #9 排版：≥2 元素逐元素折行（catalog 77 卡曾单行 13354 字符——一行
      // 改动整行 diff 换；折行后单卡行级 diff）；0/1 元素保持内联
      if parts.length() >= 2 {
        let buf = StringBuilder()
        buf.write_string("[\n")
        for p in parts {
          buf.write_string("  ")
          buf.write_string(p)
          buf.write_string(",\n")
        }
        buf.write_string("]")
        buf.to_string()
      } else {
        "[\{parts.join(", ")}]"
      }
    }
    (Object(o), Some(JTEnum(n))) if strict_keys =>
      // fill：键集漂移消歧（#14-2b）——按 tag 键（降级产物形态）或键集
      // 精确匹配选 payload 变体；无匹配 = J3004 fail loud（信息矛盾不该
      // 静默选边）
      fill_enum_variant(table, atab, enums, n, o)
    (Object(o), Some(JTStruct(name))) => {
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      if strict_keys {
        strict_check_keys(table, atab, name, ks)
      }
      for k in ks {
        let v = o.get(k).unwrap()
        let label = alias_field_label(atab, name, k)
        entries.push(
          "\{label}: \{render_value(table, atab, v, struct_field_type(table, name, label), enums~, strict_keys~)}",
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
        entries.push(
          "\{moonbit_escape(k)}: \{render_value(table, atab, v, vt, enums~, strict_keys~)}",
        )
      }
      "{ \{entries.join(", ")} }"
    }
  }
}

///|
/// fill 的 enum 变体消歧（#14-2b）：① o 含 "case" 字符串键（= 自身降级
/// 产物形态）→ 按 tag 选变体，payload = 剥 tag 后的对象；② 无 tag →
/// 键集与各 payload struct 的隐含键集精确匹配。选定后渲染
/// `Var(Px::{...})`（payload 以声明 struct 期望递归 strict 渲染）
fn fill_enum_variant(
  table : StructTable,
  atab : AliasTable,
  enums : Map[String, EnumDef],
  ename : String,
  o : Map[String, Json],
) -> String raise Diag {
  let def = match enums.get(ename) {
    Some(d) => d
    None =>
      raise Diag(
        code=JFieldType,
        loc=dummy_loc(),
        message="enum '\{ename}' is not defined in this file",
        help=Some(
          ".json.mbt is single-file; declare the enum alongside the structs",
        ),
        path="",
      )
  }
  let ks : Array[String] = []
  o.each(fn(k, _) { ks.push(k) })
  // ① tag 键指示（降级产物形态——fill 吃自己的产物，round-trip 闭环）
  let variant : String? = match o.get("case") {
    Some(String(tag)) =>
      if def.payload_variants.contains(tag) {
        Some(tag)
      } else {
        raise Diag(
          code=JFieldType,
          loc=dummy_loc(),
          message="enum '\{ename}' has no payload variant '\{tag}'",
          help=Some("payload variants: \{def.payload_variants.join(" ")}"),
          path="",
        )
      }
    _ => None
  }
  let payload_keys : Array[String] = ks.filter(fn(k) { k != "case" })
  match variant {
    Some(v) =>
      render_variant_payload(table, atab, enums, def, v, payload_keys, o)
    None => {
      // ② 键集精确匹配
      for v in def.payload_variants {
        let pty = def.payload_types.get(v)
        match pty {
          Some(JTStruct(px)) => {
            let labels : Array[String] = []
            match table.get(px) {
              Some(fs) =>
                for f in fs {
                  labels.push(f.0)
                }
              None => ()
            }
            let implied = implied_json_keys(atab, px, labels)
            let same = payload_keys.length() == implied.length() &&
              payload_keys.iter().all(fn(k) { implied.contains(k) })
            if same {
              return render_variant_payload(
                table, atab, enums, def, v, payload_keys, o,
              )
            }
          }
          _ => ()
        }
      }
      raise Diag(
        code=JFieldType,
        loc=dummy_loc(),
        message="no variant of '\{ename}' matches key set { \{payload_keys.join(", ")} }",
        help=Some(
          "payload variants: \{def.payload_variants.join(" ")} — hand-pick by adding a \"case\" tag, or extend the enum",
        ),
        path="",
      )
    }
  }
}

///|
fn render_variant_payload(
  table : StructTable,
  atab : AliasTable,
  enums : Map[String, EnumDef],
  def : EnumDef,
  v : String,
  payload_keys : Array[String],
  o : Map[String, Json],
) -> String raise Diag {
  let pty = def.payload_types.get(v)
  match pty {
    Some(JTStruct(px)) => {
      // payload 对象（剥 tag 键）以声明 struct 期望 strict 递归
      let inner : Map[String, Json] = Map([])
      for k in payload_keys {
        inner[k] = o.get(k).unwrap()
      }
      "\{v}(\{render_value(table, atab, Json::object(inner), pty, enums~, strict_keys=true)})"
    }
    Some(other) => {
      // 审 P1-c：标量 payload 的源对象剥 tag 后无余键（缺 value 键）——
      // 数据与声明不同步，fail loud（曾 payload_keys[0] 越界 panic 且
      // 绕过校验先行——D-8 ①）
      if payload_keys.length() == 0 {
        raise Diag(
          code=JMissingField,
          loc=dummy_loc(),
          message="variant '\{v}' has a scalar payload but the source JSON carries no 'value' key",
          help=Some(
            "fill only rewrites the value body; add the payload key to the JSON or use a payload-less variant",
          ),
          path="",
        )
      }
      "\{v}(\{render_value(table, atab, o.get(payload_keys[0]).unwrap(), Some(strip_option_shallow(other)), enums~, strict_keys=true)})"
    }
    None => "\{v}"
  }
}

///|
fn strip_option_shallow(t : JType) -> JType {
  match t {
    JTOption(x) => x
    other => other
  }
}

///|
/// 顶层值：struct record 多行（可读性）；其余形态内联。
/// enums/strict_keys（#14-2b fill）透传——顶层 record 的键集校验同 strict 语义
fn render_top_value(
  table : StructTable,
  atab : AliasTable,
  j : Json,
  ty : JType?,
  enums? : Map[String, EnumDef] = Map([]),
  strict_keys? : Bool = false,
) -> String raise Diag {
  match (j, ty) {
    (Object(o), Some(JTStruct(name))) => {
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      if strict_keys {
        strict_check_keys(table, atab, name, ks)
      }
      for k in ks {
        let v = o.get(k).unwrap()
        let label = alias_field_label(atab, name, k)
        entries.push(
          "\{label}: \{render_value(table, atab, v, struct_field_type(table, name, label), enums~, strict_keys~)}",
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
    _ => render_value(table, atab, j, ty, enums~, strict_keys~)
  }
}

///|
/// 生成 .json.mbt 全文（import 主出口；无时间/版本戳——确定性）。
/// field-alias 注记（#13）紧随源行：原始 JSON 键 → 改名后字段的映射表，
/// build 侧据此还原键名（合法 MoonBit 注释——fmt 幂等，探针实锚）
fn generate_source(
  result : InferResult,
  root : Json,
  stem~ : String,
  src_name~ : String,
) -> String raise Diag {
  let table = build_struct_table(result.structs)
  let atab = build_alias_table(result.aliases)
  let buf = StringBuilder()
  buf.write_string(
    "// @generated by jsonmbt import —— 禁手改（再生成：jsonmbt import \{src_name}）。\n",
  )
  buf.write_string("// 源：\{src_name}\n")
  for a in result.aliases {
    let (sname, label, key) = a
    buf.write_string("// jsonmbt: field-alias \{sname}.\{label} = \"\{key}\"\n")
  }
  buf.write_string("\n")
  // #14-2a：空容器 Never 底型定义（直接产 fmt 归一形态 `{}`——探针实锚
  // `{ }` 会被 fmt 收敛，生成器出终态；零构造器 = 免费护栏）
  if result.uses_never {
    buf.write_string("pub enum Never {}\n\n")
  }
  for s in result.structs {
    buf.write_string(render_struct_def(s.0, s.1))
    buf.write_string("\n")
  }
  match result.root_ty {
    Some(t) => {
      buf.write_string("pub let \{stem} : \{t.show()} = ")
      buf.write_string(render_top_value(table, atab, root, Some(t)))
      buf.write_string("\n")
    }
    None => {
      buf.write_string("pub let \{stem} = ")
      buf.write_string(render_top_value(table, atab, root, None))
      buf.write_string("\n")
    }
  }
  buf.to_string()
}
