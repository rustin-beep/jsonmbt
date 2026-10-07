// AST 面快照锚（R1b-L1）：parser@0.4.3 非公开 AST 面对冲——
// 自投影签名（本仓定义的紧凑 AST 投影，跨 parser 版本语义稳定）锚死
// 「此样本 → 此 AST 结构」；升级红 = diff 投影逐节点定责（R1b 对冲流程）
// 覆盖面：L0 白名单全部 AST 变体（Record 带名/裸、五 Constant 细类含
// 负号与 Int64、Array、Map、Some、None）

///|
/// AST 投影：Expr → 紧凑签名（节点种类 + 定责所需参数；不锚调试 repr）
fn ast_sig(e : @syntax.Expr) -> String {
  match e {
    Record(type_name~, fields~, ..) => {
      let name = match type_name {
        Some(tn) => longident_name(tn.name)
        None => "-"
      }
      let fs : Array[String] = []
      for f in fields {
        fs.push("\{f.label.name}:\{ast_sig(f.expr)}")
      }
      "R[\{name}](\{fs.join(", ")})"
    }
    Array(exprs~, ..) => {
      let es : Array[String] = []
      for x in exprs {
        es.push(ast_sig(x))
      }
      "A[\{es.join(", ")}]"
    }
    Map(elems~, ..) => {
      let es : Array[String] = []
      for el in elems {
        es.push("k:\{constant_sig(el.key)}:\{ast_sig(el.expr)}")
      }
      "M[\{es.join(", ")}]"
    }
    Apply(func~, args~, ..) => {
      let inner : String = match args.head() {
        Some({ value, kind: Positional, }) => ast_sig(value)
        _ => "?"
      }
      let fname = if func is Constr(constr~, ..) {
        constr.name.name
      } else {
        "call"
      }
      "F(\{fname}, \{inner})"
    }
    Constr(constr~, ..) => "C(\{constr.name.name})"
    Constant(c~, ..) => "K(\{constant_sig(c)})"
    _ => "OTHER"
  }
}

///|
fn constant_sig(c : @syntax.Constant) -> String {
  match c {
    Int(raw) => "i:\{raw}"
    Int64(raw) => "i64:\{raw}"
    Double(raw) => "d:\{raw}"
    Bool(b) => "b:\{b}"
    String(raw) => "s:\{raw}"
    Char(_) => "char"
    _ => "other"
  }
}

///|
test "R1b-L1 : AST 面快照（L0 白名单全变体，锚死 parser@0.4.3 行为）" {
  let src =
    #|pub let t : T = T::{
    #|  a: 1,
    #|  b: -2,
    #|  c: 3L,
    #|  d: 1.5e3,
    #|  e: "s",
    #|  f: true,
    #|  g: [1, "x"],
    #|  h: { "k": 1 },
    #|  i: Some(4),
    #|  j: None,
    #|  k: { n: 5 },
    #|}
  let (impls, reports) = @parser.parse_string(src, name="snap.json.mbt")
  inspect(reports.length(), content="0")
  let sig = match impls.head() {
    Some(TopLetDef(expr~, ..)) => ast_sig(expr)
    _ => "NO-ROOT"
  }
  inspect(
    sig,
    content="R[T](a:K(i:1), b:K(i:-2), c:K(i64:3), d:K(d:1.5e3), e:K(s:s), f:K(b:true), g:A[K(i:1), K(s:x)], h:M[k:s:k:K(i:1)], i:F(Some, K(i:4)), j:C(None), k:R[-](n:K(i:5)))",
  )
}
