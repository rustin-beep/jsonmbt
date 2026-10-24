// 文档层（D-7 单文档基数 + 类型头预检）
// analyze：源文本 → Doc{structs, root, root_ty}；check/build 同走这条路径（D-8）

///|
priv struct Doc {
  structs : Map[String, StructDef]
  enums : Map[String, EnumDef]
  root_expr : @syntax.Expr
  root_ty : JType? // pub let 的类型注解；缺省 = 自由值
}

///|
/// J1001：.json.mbt 语法错（parser Report 非空——转发首个报告的位置与消息）
fn syntax_diag(r : @basic.Report, path : String) -> Diag {
  Diag(
    code=JSyntax,
    loc=r.loc,
    message=r.msg,
    help=Some(
      "keep the file valid MoonBit: struct defs + one top-level pub let of literals",
    ),
    path~,
  )
}

///|
/// #44：parser 抢先拒的硬关键字字段名 → 转译 J2008（改名 + field-alias
/// 处方，与 `extend` 的现行体验对齐）——58 词中 57 个曾只拿 J1001「语法
/// 错」（可行动性分裂：同份数据 import 路径有正规改名通道、手写路径却
/// 只见语法错）。行级判定零假阳性风险：parser 已指认出错行，行首
/// `<word> :` 形态且词在硬关键字表（moon_facts 单源）才转译
fn hard_keyword_field_diag(
  src : String,
  r : @basic.Report,
  path : String,
) -> Diag {
  let lnum = r.loc.start.lnum
  let mut raw : StringView? = None
  let mut cur = 1
  for line in src.split("\n") {
    if cur == lnum {
      raw = Some(line)
      break
    }
    cur = cur + 1
  }
  if raw is Some(rv) {
    let raw = rv
    // 剥行首空白与行尾 \r（CRLF 源）
    let mut a = 0
    let n = raw.length()
    let view = raw[:]
    while a < n && (view[a] == ' ' || view[a] == '\t') {
      a = a + 1
    }
    let mut e = n
    if e > a && view[e - 1] == '\r' {
      e = e - 1
    }
    // 提取行首标识符词（[a-z_][A-Za-z0-9_]*）
    let mut b = a
    if b < e && ((view[b] >= 'a' && view[b] <= 'z') || view[b] == '_') {
      b = b + 1
      while b < e &&
            (
              (view[b] >= 'a' && view[b] <= 'z') ||
              (view[b] >= 'A' && view[b] <= 'Z') ||
              (view[b] >= '0' && view[b] <= '9') ||
              view[b] == '_'
            ) {
        b = b + 1
      }
      let word = view[a:b].to_owned()
      // 跳过词后空白再看 `:`（声明位 `where : Int32` / 构造位 `where: 1`）
      let mut c = b
      while c < e && (view[c] == ' ' || view[c] == '\t') {
        c = c + 1
      }
      // 声明位/构造位通判：词后跟 `:`（字段位形态）且词在硬表
      if c < e && view[c] == ':' && is_hard_keyword(word) {
        return Diag(
          code=JHardKeywordField,
          loc=r.loc,
          message="field label '\{word}' is a MoonBit hard keyword — moonc rejects it as a parse error",
          help=Some(
            "rename the field (e.g. '\{word}_') and add a field-alias marker: // jsonmbt: field-alias S.\{word}_ = \"\{word}\"",
          ),
          path~,
        )
      }
    }
  }
  syntax_diag(r, path)
}

///|
const FIELD_ALIAS_PREFIX : String = "// jsonmbt: field-alias "

///|
/// 行号定位（field-alias 注记诊断用——注记在注释里，parser 看不见）
fn marker_loc(path : String, lnum : Int32) -> @basic.Location {
  {
    start: { fname: path, lnum, bol: 0, cnum: 0, },
    end: { fname: path, lnum, bol: 0, cnum: 0, },
  }
}

///|
/// field-alias 注记预扫描（#13）：moon 解析器剥注释，注记必须在原始源文本
/// 上收。严格行文法：`// jsonmbt: field-alias <Struct>.<label> = "<json键>"`
/// （合法 MoonBit 注释——fmt 幂等，探针实锚；畸形行 J3009 fail loud 不猜）
fn scan_field_aliases(
  src : String,
  path : String,
) -> Array[(String, String, String, Int32)] raise Diag {
  let out : Array[(String, String, String, Int32)] = []
  let mut lnum = 0
  for raw_line in src.split("\n") {
    lnum = lnum + 1
    // 行首空白跳过 + 行尾 \r 剥离（CRLF 源）
    let v = raw_line[:]
    let n = v.length()
    let mut s = 0
    while s < n && (v[s] == ' ' || v[s] == '\t') {
      s = s + 1
    }
    let mut e = n
    if e > s && v[e - 1] == '\r' {
      e = e - 1
    }
    let t = v[s:e]
    if !t.has_prefix("// jsonmbt: field-alias") {
      continue
    }
    let bad = fn(msg : String) -> Diag {
      Diag(
        code=JBadAlias,
        loc=marker_loc(path, lnum),
        message="malformed field-alias marker (want '\{FIELD_ALIAS_PREFIX}<Struct>.<label> = \"<json-key>\"'): \{msg}",
        help=Some(
          "example: // jsonmbt: field-alias Rule.where_ = \"where\" — one marker per line, at the top of the file",
        ),
        path~,
      )
    }
    if !t.has_prefix(FIELD_ALIAS_PREFIX) {
      raise bad("stray text inside the marker prefix")
    }
    let rest = t[FIELD_ALIAS_PREFIX.length():]
    let eq = rest.find(" = ")
    let (left, right) = match eq {
      Some(i) => (rest[:i].to_owned(), rest[i + 3:])
      None => raise bad("missing ' = '")
    }
    let dot = left.find(".")
    let (sname, label) = match dot {
      Some(i) => (left[:i].to_owned(), left[i + 1:].to_owned())
      None => raise bad("want <Struct>.<label>")
    }
    if sname == "" || label == "" || left[dot.unwrap() + 1:].contains(".") {
      raise bad("want exactly one '.' in <Struct>.<label>")
    }
    if right.length() < 2 || right[0] != '"' || right[right.length() - 1] != '"' {
      raise bad("json key must be a double-quoted string")
    }
    let key = right[1:right.length() - 1].to_owned()
    if key == "" || key.contains("\"") {
      raise bad("json key must be non-empty and quote-free")
    }
    out.push((sname, label, key, lnum))
  }
  out
}

///|
/// 注记语义校验 + 附着到 struct 表（#13）：struct/字段须存在、恒等注记拒收、
/// 隐含 JSON 键集须无碰撞——防手滑，fail loud
fn attach_field_aliases(
  structs : Map[String, StructDef],
  marks : Array[(String, String, String, Int32)],
  path : String,
) -> Unit raise Diag {
  for m in marks {
    let (sname, label, key, lnum) = m
    let d = match structs.get(sname) {
      Some(d) => d
      None =>
        raise Diag(
          code=JBadAlias,
          loc=marker_loc(path, lnum),
          message="field-alias names struct '\{sname}' which is not defined in this file",
          help=Some("declare the struct, or fix the name in the marker"),
          path~,
        )
    }
    let has_field = d.fields.iter().find_first(fn(f) { f.0 == label })
      is Some(_)
    if !has_field {
      raise Diag(
        code=JBadAlias,
        loc=marker_loc(path, lnum),
        message="field-alias names field '\{label}' which struct '\{sname}' does not have",
        help=Some("struct '\{sname}' has fields: \{field_names(d)}"),
        path~,
      )
    }
    if key == label {
      raise Diag(
        code=JBadAlias,
        loc=marker_loc(path, lnum),
        message="identity field-alias ('\{label}' = \"\{key}\") — remove the marker",
        help=Some(
          "markers are only for fields whose JSON key differs from the label",
        ),
        path~,
      )
    }
    if d.aliases.contains(label) {
      raise Diag(
        code=JBadAlias,
        loc=marker_loc(path, lnum),
        message="duplicate field-alias for '\{sname}.\{label}'",
        help=Some("keep exactly one marker per field"),
        path~,
      )
    }
    for f in d.fields {
      if f.0 != label {
        let implied = match d.aliases.get(f.0) {
          Some(k) => k
          None => f.0
        }
        if implied == key {
          raise Diag(
            code=JBadAlias,
            loc=marker_loc(path, lnum),
            message="two fields of '\{sname}' map to the same JSON key \"\{key}\"",
            help=Some("each field must degrade to a distinct JSON key"),
            path~,
          )
        }
      }
    }
    d.aliases[label] = key
  }
}

///|
/// J2010 形态判定（#42 案例 A，裁定口径）：顶层值为 **Record 变体**（裸
/// 花括号对象 / 具名构造 M::{...} 无标注）→ 真——moon [4074]/[4033]（no
/// record definition）对齐。**Map 字面量（带引号键）与数组/Some 自由值
/// 保留合法**（既有正样本能力，api_test 锚成体系；moon 侧同形态 [4074]
/// = 已知有意差集「moon 严于 jsonmbt」，#16「不比 moon 严」的反向不违
/// 承诺——扩展拒收另议留痕 issue）。标量/Tuple/Constr 可推断为假。
/// Group(Paren) 递归剥（#25——圆括号不改形态）
fn expr_needs_header(e : @syntax.Expr) -> Bool {
  match e {
    Record(..) => true
    Group(expr~, group~, ..) =>
      match group {
        Paren => expr_needs_header(expr)
        Brace => false
      }
    _ => false
  }
}

///|
fn analyze(
  src : String,
  path~ : String = "",
  expected_name? : String,
) -> Doc raise Diag {
  let (impls, reports) = @parser.parse_string(src, name=path)
  if reports.length() > 0 {
    raise hard_keyword_field_diag(src, reports[0], path)
  }
  // field-alias 注记（#13）：预扫描（注释层——parser 剥掉）+ 语义校验附着
  let alias_marks = scan_field_aliases(src, path)
  // 顶层白名单：struct 定义 + 恰好一个 pub let（D-7；其余顶层 = J2005，
  // L2 落地时再放内部 let）
  let tyenv = collect_tyenv(impls)
  attach_field_aliases(tyenv.structs, alias_marks, path)
  let structs = tyenv.structs
  let mut root_opt : @syntax.Impl? = None
  for i in impls {
    match i {
      TopTypeDef(_) => () // collect_structs 已收
      TopLetDef(vis~, ..) =>
        match vis {
          Pub(..) =>
            if root_opt is None {
              root_opt = Some(i)
            } else {
              raise Diag(
                code=JMultiDoc,
                loc=impl_loc(i),
                message="multiple top-level pub let bindings",
                help=Some(
                  "one .json.mbt file degrades to exactly one JSON document (D-7)",
                ),
                path~,
              )
            }
          _ =>
            raise Diag(
              code=JBadTop,
              loc=impl_loc(i),
              message="non-pub top-level let",
              help=Some(
                "internal bindings arrive with L2; today the file is one pub let of literals",
              ),
              path~,
            )
        }
      other =>
        raise Diag(
          code=JBadTop,
          loc=impl_loc(other),
          message="top-level \{impl_kind(other)} declaration",
          help=Some(
            "a .json.mbt file contains struct definitions and one pub let — nothing else",
          ),
          path~,
        )
    }
  }
  let root = match root_opt {
    Some(r) => r
    None =>
      raise Diag(
        code=JNoDoc,
        loc=dummy_loc(),
        message="no top-level pub let binding",
        help=Some(
          "add `pub let <file-stem> = ...` — the file degrades to one JSON document",
        ),
        path~,
      )
  }
  // D-7 stem 命名：config.json.mbt → pub let config（stdin 免检——无文件名）
  guard! root is TopLetDef(binder~, ty~, expr~, loc~, ..)

  match expected_name {
    Some(expect) =>
      if binder.name != expect {
        raise Diag(
          code=JStemMismatch,
          loc~,
          message="top-level binding is '\{binder.name}' but the file stem is '\{expect}'",
          help=Some(
            "rename the binding (or the file) so they match — this keeps one name per document",
          ),
          path~,
        )
      }
    None => ()
  }
  // 类型头预检（J2007）：struct 字段与 root 注解中不受支持的类型先于值校验报出
  let defs : Array[StructDef] = []
  structs.each(fn(_, v) { defs.push(v) })
  for sd in defs {
    for f in sd.fields {
      // J2008（#38 D-14③）：字段名硬关键字自持判定——mooncakes parser 库
      // 对字段位 `extend` 等放行（与 moonc 两份代码关键字行为有缝，
      // PITFALLS #49），不补判定则「check 通过 ≈ 可编译」承诺破洞。
      // 只拒 58 硬词（moonc Parse error 分级）；21 保留词字段照旧放行
      // （moonc 警告级 [0035] 合法——非「比 moon 严」）
      if is_hard_keyword(f.0) {
        raise Diag(
          code=JHardKeywordField,
          loc=f.2,
          message="field label '\{f.0}' is a MoonBit hard keyword — moonc rejects it as a parse error",
          help=Some(
            "rename the field (e.g. '\{f.0}_') and add a field-alias marker: // jsonmbt: field-alias \{sd.name}.\{f.0}_ = \"\{f.0}\"",
          ),
          path~,
        )
      }
      scan_supported_type(f.1, f.2)
    }
  }
  // enum payload 同面预检（#32-10）：payload 位 T?? 曾绕过——值层 payload_case
  // 直接使用期望类型，None 与 Some(None) 降级静默压平成同一 null（struct 字段
  // 位有预检、payload 位漏 = 同族臂不对称）；变体级 loc 未入表，借用顶层绑定 loc
  let eds : Array[EnumDef] = []
  tyenv.enums.each(fn(_, v) { eds.push(v) })
  for ed in eds {
    let pts : Array[JType] = []
    ed.payload_types.each(fn(_, pt) { pts.push(pt) })
    for pt in pts {
      scan_supported_type(pt, loc)
    }
  }
  let root_ty : JType? = match ty {
    Some(t) => {
      scan_supported_type(parse_type(t), loc)
      Some(parse_type(t))
    }
    None => {
      // J2010（#42 案例 A）：顶层复合字面量无类型标注——moon [4074]
      // Cannot infer（探针实锚：record/Map/数组/Some 无标注一律红，仅
      // 标量/Tuple 可推断）——jsonmbt 曾全绿照常产出，真相源在 moon
      // 编译面是坏的。括号剥（#25）后内层仍是复合形态即命中
      if expr_needs_header(expr) {
        raise Diag(
          code=JNoTypeHeader,
          loc~,
          message="top-level binding has no type annotation — moonc cannot infer record/map/array/option literals ([4074])",
          help=Some(
            "add `: <Type>` to the binding — the type header is part of the document, not decoration",
          ),
          path~,
        )
      }
      None
    }
  }
  { structs, enums: tyenv.enums, root_expr: expr, root_ty, }
}

///|
/// JType 递归扫描：L0 类型面之外的形态带位置报 J2007（类型头问题先于值问题）
fn scan_supported_type(t : JType, loc : @basic.Location) -> Unit raise Diag {
  match t {
    JTUnsupported(_) =>
      raise Diag(
        code=JBadFieldType,
        loc~,
        message="field type is outside the L0 subset",
        help=Some(
          "supported field types: Int/Int64/Double/String/Bool/T? (Option)/Array[T]/Map[String,T]/struct",
        ),
        path="",
      )
    JTOption(inner) => {
      // 嵌套 Option（T??）收窄（#14 批次1）：实测 None 与 Some(None) 都降级
      // null——静默压平违反 §0 无损与 D-8 ②。三态编码（缺席/null/值）走
      // §8 评审；此前一律拒（递归口径：任意深度嵌套都在此拦下）
      if inner is JTOption(_) {
        raise Diag(
          code=JBadFieldType,
          loc~,
          message="nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null",
          help=Some(
            "use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
          ),
          path="",
        )
      }
      scan_supported_type(inner, loc)
    }
    JTArray(t) => scan_supported_type(t, loc)
    JTMap(k, v) => {
      // #32-20：Map 键位非 String 先于值层报（曾落值层 J3004——层/码漂移：
      // 类型头问题该走 J2007 预检通道）
      if !(k is JTString) {
        raise Diag(
          code=JBadFieldType,
          loc~,
          message="map key type must be String, got '\{k.show()}' (JSON objects only have string keys)",
          help=Some(
            "supported field types: Int/Int64/Double/String/Bool/T? (Option)/Array[T]/Map[String,T]/struct",
          ),
          path="",
        )
      }
      scan_supported_type(v, loc)
    }
    _ => ()
  }
}

///|
fn impl_kind(i : @syntax.Impl) -> String {
  match i {
    TopExpr(..) => "expression"
    TopTest(..) => "test"
    TopTypeDef(_) => "type"
    TopFuncDef(..) => "fn"
    TopLetDef(..) => "let"
    TopTrait(_) => "trait"
    TopImpl(..) => "impl"
    TopView(..) => "view"
    TopImplRelation(..) => "impl relation"
    _ => "unsupported"
  }
}

///|
fn impl_loc(i : @syntax.Impl) -> @basic.Location {
  match i {
    TopExpr(loc~, ..) => loc
    TopTest(loc~, ..) => loc
    TopTypeDef(d) => d.loc
    TopFuncDef(loc~, ..) => loc
    TopLetDef(loc~, ..) => loc
    TopTrait(d) => d.loc
    TopImpl(loc~, ..) => loc
    TopView(loc~, ..) => loc
    TopImplRelation(loc~, ..) => loc
    _ => dummy_loc()
  }
}

///|
fn dummy_loc() -> @basic.Location {
  {
    start: { fname: "", lnum: 1, bol: 0, cnum: 0, },
    end: { fname: "", lnum: 1, bol: 0, cnum: 0, },
  }
}
