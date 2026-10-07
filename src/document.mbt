// 文档层（D-7 单文档基数 + 类型头预检）
// analyze：源文本 → Doc{structs, root, root_ty}；check/build 同走这条路径（D-8）

///|
priv struct Doc {
  structs : Map[String, StructDef]
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
fn analyze(
  src : String,
  path? : String = "",
  expected_name? : String,
) -> Doc raise Diag {
  let (impls, reports) = @parser.parse_string(src, name=path)
  if reports.length() > 0 {
    raise syntax_diag(reports[0], path)
  }
  // 顶层白名单：struct 定义 + 恰好一个 pub let（D-7；其余顶层 = J2005，
  // L2 落地时再放内部 let）
  let structs = collect_structs(impls)
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
      scan_supported_type(f.1, f.2)
    }
  }
  let root_ty : JType? = match ty {
    Some(t) => {
      scan_supported_type(parse_type(t), loc)
      Some(parse_type(t))
    }
    None => None
  }
  { structs, root_expr: expr, root_ty, }
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
          "supported field types: Int/Int64/Double/String/Bool/Option[T]/Array[T]/Map[String,T]/struct",
        ),
        path="",
      )
    JTOption(t) | JTArray(t) => scan_supported_type(t, loc)
    JTMap(k, v) => {
      scan_supported_type(k, loc)
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
