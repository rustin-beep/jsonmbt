// 形状推断器（importer v1 核心）：Json 值树 → struct 集 + 顶层类型
// 规则全部来自 PLAN 终案：
//   形状签名判重（键集相同 = 同 struct，字段序 = 首见样本键序——输出确定性）／
//   同构数组 Array[T]／D-1 空容器两级启发（同签名组内样本 → 全文件同名字段 →
//   阻断 J4001）／D-2 跨样本无损上浮（任一样本超 Int → 全体 Int64；超 Int64
//   诚实拒绝 J4020；Int64+Double 混合拒绝——静默 Double 化 = 精度红线）／
//   键名逃生门（保留字/连字符/大写开头 → 同值类型对象转 Map[String,V]，
//   异值键阻断 J4011）／tagged-enum 单键 true/false/null 形态 hint（J4030，
//   rc 0 不阻断）／null → Option[T]（基型由其他样本聚合；全 null J4003）

///|
let reserved_labels : Array[String] = [
  "fn", "let", "mut", "const", "return", "match", "if", "else", "loop", "while",
  "for", "in", "break", "continue", "true", "false", "struct", "enum", "type", "trait",
  "impl", "pub", "priv", "package", "import", "test", "as", "extern", "raise", "try",
  "catch", "defer", "guard", "when", "view", "extenum", "async", "backed", "where",
  "is", "unit",
]

///|
fn is_reserved_label(name : String) -> Bool {
  reserved_labels.contains(name)
}

///|
/// 合法字段 label：小写字母开头（snake/驼峰）/下划线开头/非 ASCII（中文）；
/// 大写开头非法（类型名域）、保留字非法（探针①）
fn is_legal_label(name : String) -> Bool {
  if name == "" || is_reserved_label(name) {
    return false
  }
  let first = name[0] // code unit：ASCII 判定足够（非法域只有大写 ASCII）
  if first >= 'A' && first <= 'Z' {
    return false
  }
  if (first >= 'a' && first <= 'z') || first == '_' {
    return true
  }
  first.to_int() >= 0x80
}

///|
fn is_legal_type_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  let first = name[0]
  first >= 'A' && first <= 'Z'
}

///|
fn capitalize(s : String) -> String {
  if s == "" {
    return s
  }
  let first = s[0]
  if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char().to_string() + s[1:].to_owned()
  } else {
    s
  }
}

///|
priv struct FieldSamples {
  label : String
  samples : Array[SampleTy] // 同签名组内全部样本的字段贡献
}

///|
priv enum SampleTy {
  NullSample
  Ty(JType)
}

///|
priv struct ShapeGroup {
  fields : Array[FieldSamples] // 按首见样本键序
  field_index : Map[String, Int]
  mut resolved_name : String // 定名后回填（walk 期间 JTStruct 名即此）
}

///|
priv struct InferCtx {
  groups : Map[String, ShapeGroup]
  group_order : Array[String]
  used_type_names : Array[String]
  name_cache : Map[String, String] // 签名 → struct 名
  hints : Array[Diag]
  stem : String
  fname : String
}

///|
priv struct InferResult {
  structs : Array[(String, Array[(String, JType)])] // (struct 名, 字段表)
  root_ty : JType?
  hints : Array[Diag]
}

///|
fn signature_of_keys(keys : Array[String]) -> String {
  let sorted = keys.copy()
  sorted.sort()
  sorted.join("\u{1}")
}

///|
/// 主入口：值树 → struct 集 + 顶层类型（walk 收集 → 组定稿 → D-1 二级启发）
fn infer_shapes(
  root : Json,
  stem~ : String,
  fname? : String = "<json>",
) -> InferResult raise Diag {
  let ctx : InferCtx = {
    groups: Map([]),
    group_order: [],
    used_type_names: [],
    name_cache: Map([]),
    hints: [],
    stem,
    fname,
  }
  // 顶层对象组预命名 capitalize(stem)（config.json → Config——D-7 命名同源）
  prename_top_group(ctx, root)
  let root_ty = walk_value(ctx, root)
  finalize_empty_root(ctx, root_ty)
  // 组定稿（首见序 = 确定性）
  let structs : Array[(String, Array[(String, JType)])] = []
  let pending_empty : Array[(String, String)] = [] // (struct 名, 字段名)
  for sig in ctx.group_order {
    let g = ctx.groups[sig]
    let fields : Array[(String, JType)] = []
    for fs in g.fields {
      let ty = merge_samples(ctx, fs.samples, fs.label, allow_empty_arr=true)
      fields.push((fs.label, ty))
      if ty is JTArray(JTEmpty) {
        pending_empty.push((g.resolved_name, fs.label))
      }
    }
    structs.push((g.resolved_name, fields))
  }
  // D-1 第二级启发：全文件同名字段的非空数组元素类型（规则写死进锚）
  for pair in pending_empty {
    let (name, label) = pair
    let mut resolved : JType? = None
    for s in structs {
      if s.0 != name {
        for f in s.1 {
          if f.0 == label && f.1 is JTArray(t) && !(t is JTEmpty) {
            resolved = Some(t)
            break
          }
        }
      }
      if resolved is Some(_) {
        break
      }
    }
    match resolved {
      Some(t) => patch_empty_array(structs, name, label, t)
      None => raise empty_arr_diag(ctx, name, label)
    }
  }
  { structs, root_ty: Some(root_ty), hints: ctx.hints, }
}

///|
fn prename_top_group(ctx : InferCtx, root : Json) -> Unit {
  if root is Object(o) && o.length() > 0 {
    let keys : Array[String] = []
    o.each(fn(k, _) { keys.push(k) })
    let sig = signature_of_keys(keys)
    let name = alloc_type_name(ctx, capitalize(ctx.stem))
    ctx.name_cache[sig] = name
  }
}

///|
/// 顶层裸值兜底：JTNullLike/JTEmpty 出现在顶层 = 无类型可推
fn finalize_empty_root(ctx : InferCtx, root_ty : JType) -> Unit raise Diag {
  match root_ty {
    JTNullLike => raise all_null_diag(ctx, "(top level)")
    JTEmpty | JTArray(JTEmpty) =>
      raise empty_arr_diag(ctx, "(top level)", "(elements)")
    _ => ()
  }
}

///|
fn alloc_type_name(ctx : InferCtx, base : String) -> String {
  let primed = if is_legal_type_name(base) { base } else { "Root" }
  if !ctx.used_type_names.contains(primed) {
    ctx.used_type_names.push(primed)
    return primed
  }
  let mut i = 2
  let mut candidate = ""
  while true {
    let c = "\{primed}\{i}"
    if !ctx.used_type_names.contains(c) {
      candidate = c
      break
    }
    i = i + 1
  }
  ctx.used_type_names.push(candidate)
  candidate
}

///|
/// 单值类型化（walk 全树；对象按合法 label 分流：struct 组 / Map 逃生门）
fn walk_value(ctx : InferCtx, j : Json) -> JType raise Diag {
  match j {
    Null => JTNullLike // 值位 null：上层样本聚合决定 Option
    True | False => JTBool
    Number(_, repr~) =>
      match repr {
        Some(t) =>
          if t.contains(".") || t.contains("e") || t.contains("E") {
            JTDouble
          } else {
            match numeric_text(t) {
              Ok(_, v) => if in_i32_range(v) { JTInt } else { JTInt64 }
              Overflow(_) => raise big_num_diag(ctx, t)
              Illegal => JTDouble // 理论不可达（自持解析器保证纯十进制）
            }
          }
        None => JTDouble
      }
    String(_) => JTString
    Array(elems) => {
      if elems.length() == 0 {
        return JTArray(JTEmpty)
      }
      let mut elem : JType? = None
      for e in elems {
        let t = walk_value(ctx, e)
        elem = Some(
          match elem {
            None => t
            Some(prev) => lub(ctx, prev, t, in_array=true)
          },
        )
      }
      JTArray(elem.unwrap())
    }
    Object(o) => {
      let keys : Array[String] = []
      o.each(fn(k, _) { keys.push(k) })
      if keys.length() == 0 {
        raise empty_obj_diag(ctx) // D-1：空对象单独形态
      }
      register_tagged_enum_hint(ctx, keys, o)
      if keys.all(is_legal_label) {
        walk_as_struct(ctx, keys, o)
      } else {
        // 键名逃生门：非 String 值类型聚合（同构 → Map；异值键 J4011）
        let samples : Array[SampleTy] = []
        let ks : Array[String] = []
        o.each(fn(k, _) { ks.push(k) })
        for k in ks {
          let t = walk_value(ctx, o.get(k).unwrap())
          samples.push(if t is JTNullLike { NullSample } else { Ty(t) })
        }
        JTMap(
          JTString,
          merge_samples(
            ctx,
            samples,
            "(map values)",
            allow_empty_arr=false,
            at_map=true,
          ),
        )
      }
    }
  }
}

///|
/// tagged-enum hint：恰一键、大写开头、值 true/false/null（{Void: true} 家族）
fn register_tagged_enum_hint(
  ctx : InferCtx,
  keys : Array[String],
  o : Map[String, Json],
) -> Unit {
  if keys.length() != 1 {
    return
  }
  let k = keys[0]
  let first = k[0]
  let looks_tag = first >= 'A' &&
    first <= 'Z' &&
    o.get(k) is Some(True | False | Null)
  if looks_tag {
    ctx.hints.push(
      Diag(
        code=JTaggedEnumHint,
        loc=dummy_loc(),
        message="object looks like a tagged-enum constructor ('\{k}': ...)",
        help=Some(
          "consider hand-writing a MoonBit enum instead; jsonmbt imported it as-is",
        ),
        path=ctx.fname,
      ),
    )
  }
}

///|
fn walk_as_struct(
  ctx : InferCtx,
  keys : Array[String],
  o : Map[String, Json],
) -> JType raise Diag {
  let sig = signature_of_keys(keys)
  if !ctx.groups.contains(sig) {
    let g : ShapeGroup = {
      fields: [],
      field_index: Map([]),
      resolved_name: "",
    }
    for k in keys {
      g.field_index[k] = g.fields.length()
      g.fields.push({ label: k, samples: [], })
    }
    ctx.groups[sig] = g
    ctx.group_order.push(sig)
    // 命名：预命名（顶层）优先；否则组首字段 capitalize（中文/不可大写化 → Root 系）
    if !ctx.name_cache.contains(sig) {
      let base = if g.fields.length() > 0 {
        capitalize(g.fields[0].label)
      } else {
        capitalize(ctx.stem)
      }
      ctx.name_cache[sig] = alloc_type_name(ctx, base)
    }
    ctx.groups[sig].resolved_name = ctx.name_cache[sig]
  }
  let g = ctx.groups[sig]
  let ks : Array[String] = []
  o.each(fn(k, _) { ks.push(k) })
  for k in ks {
    let t = walk_value(ctx, o.get(k).unwrap())
    g.fields[g.field_index[k]].samples.push(
      if t is JTNullLike {
        NullSample
      } else {
        Ty(t)
      },
    )
  }
  JTStruct(g.resolved_name)
}

///|
/// 样本聚合 → 字段类型（null → Option；全 null J4003；空数组可容忍项待二级启发）
fn merge_samples(
  ctx : InferCtx,
  samples : Array[SampleTy],
  label : String,
  allow_empty_arr~ : Bool,
  at_map~ : Bool = false,
) -> JType raise Diag {
  let mut acc : JType? = None
  let mut nulls = 0
  for s in samples {
    match s {
      NullSample => nulls = nulls + 1
      Ty(t) =>
        acc = Some(
          match acc {
            None => t
            Some(prev) => lub(ctx, prev, t, in_array=false, at_map~)
          },
        )
    }
  }
  let base = match acc {
    None => raise all_null_diag(ctx, label)
    Some(t) => t
  }
  let with_opt = if nulls > 0 { JTOption(base) } else { base }
  if !allow_empty_arr && with_opt is JTArray(JTEmpty) {
    raise empty_arr_diag(ctx, "(map)", label)
  }
  with_opt
}

///|
/// 类型合流（lub）：D-2 跨样本上浮；Int64+Double 拒绝（精度红线）；异构 J4010/J4012
fn lub(
  ctx : InferCtx,
  a : JType,
  b : JType,
  in_array~ : Bool,
  at_map~ : Bool = false,
) -> JType raise Diag {
  match (a, b) {
    (JTInt, JTInt) => JTInt
    (JTInt, JTInt64) | (JTInt64, JTInt) | (JTInt64, JTInt64) => JTInt64
    (JTDouble, JTDouble) => JTDouble
    (JTInt, JTDouble) | (JTDouble, JTInt) => JTDouble
    (JTInt64, JTDouble) | (JTDouble, JTInt64) =>
      raise Diag(
        code=JBigNum,
        loc=dummy_loc(),
        message="Int64 and Double in the same aggregate: widening would silently lose precision",
        help=Some("store the numbers consistently, or hand-model the field"),
        path=ctx.fname,
      )
    (JTString, JTString) => JTString
    (JTBool, JTBool) => JTBool
    (JTEmpty, t) | (t, JTEmpty) => t // 空容器贡献无约束（D-1 启发链前置）
    (JTArray(t1), JTArray(t2)) => JTArray(lub(ctx, t1, t2, in_array~, at_map~))
    (JTStruct(s1), JTStruct(s2)) =>
      if s1 == s2 {
        JTStruct(s1)
      } else {
        raise hetero_diag(ctx, in_array, "\{s1} vs \{s2}", at_map~)
      }
    (JTMap(_, v1), JTMap(_, v2)) => JTMap(JTString, lub(ctx, v1, v2, in_array~))
    (JTNullLike, t) | (t, JTNullLike) => t // null 由上层聚合 Option
    _ => raise hetero_diag(ctx, in_array, "\{a.show()} vs \{b.show()}", at_map~)
  }
}

///|
fn hetero_diag(
  ctx : InferCtx,
  in_array : Bool,
  what : String,
  at_map~ : Bool = false,
) -> Diag raise Diag {
  raise Diag(
    code=
      if in_array {
        JHeteroArr
      } else if at_map {
        JMixedKeys // 异值键：Map 逃生门不适用（PLAN §6 键名逃生门适用面写死）
      } else {
        JHeteroField
      },
    loc=dummy_loc(),
    message="incompatible types across samples: \{what}",
    help=Some("split the data, or hand-write a struct with a precise type"),
    path=ctx.fname,
  )
}

///|
fn empty_arr_diag(
  ctx : InferCtx,
  sname : String,
  label : String,
) -> Diag raise Diag {
  raise Diag(
    code=JEmptyArr,
    loc=dummy_loc(),
    message="empty array with no element-type clue (struct '\{sname}', field '\{label}')",
    help=Some(
      "provide one non-empty sample for this field in the JSON (or hand-write the struct)",
    ),
    path=ctx.fname,
  )
}

///|
fn empty_obj_diag(ctx : InferCtx) -> Diag raise Diag {
  raise Diag(
    code=JEmptyObj,
    loc=dummy_loc(),
    message="empty object: no fields to infer a struct from",
    help=Some("give the object at least one field, or model it by hand"),
    path=ctx.fname,
  )
}

///|
fn all_null_diag(ctx : InferCtx, label : String) -> Diag raise Diag {
  raise Diag(
    code=JAllNull,
    loc=dummy_loc(),
    message="all samples are null: Option base type unknown ('\{label}')",
    help=Some(
      "provide one non-null sample, or hand-model the field as Option[T]",
    ),
    path=ctx.fname,
  )
}

///|
fn big_num_diag(ctx : InferCtx, text : String) -> Diag raise Diag {
  raise Diag(
    code=JBigNum,
    loc=dummy_loc(),
    message="integer '\{text}' exceeds Int64",
    help=Some(
      "jsonmbt degrades numbers losslessly; to keep >Int64 digits, store a JSON string and import it as String",
    ),
    path=ctx.fname,
  )
}

///|
fn patch_empty_array(
  structs : Array[(String, Array[(String, JType)])],
  sname : String,
  label : String,
  t : JType,
) -> Unit {
  for s in structs {
    if s.0 == sname {
      for i, f in s.1 {
        if f.0 == label && f.1 is JTArray(JTEmpty) {
          s.1[i] = (label, JTArray(t))
        }
      }
    }
  }
}
