// 类型环境：文件内 struct 定义表 + MoonBit Type AST → jsonmbt 内部类型
// 自持校验器（D-3）的类型面——不跑 moon check 也能做「类型即 Schema」校验

///|
/// jsonmbt 认识的字段类型全集（L0 子集的类型面）。
/// Int 按 MoonBit 实测为 32 位（真实编译界 2^31-1，PLAN §6 数值边界）；
/// 界检查在值校验处做，这里只记形态。
priv enum JType {
  JTInt
  JTInt64
  JTDouble
  JTString
  JTBool
  JTOption(JType)
  JTArray(JType)
  JTMap(JType, JType) // K 仅接受 String（JSON 键即字符串；Map 逃生门适用面）
  JTStruct(String)
  JTUnsupported(String) // 表达了但 L0 不支持的类型（Unit/Arrow/Tuple/Any/未知名…）
} derive(Eq)

///|
fn JType::show(self : JType) -> String {
  match self {
    JTInt => "Int"
    JTInt64 => "Int64"
    JTDouble => "Double"
    JTString => "String"
    JTBool => "Bool"
    JTOption(t) => "\{t.show()}?"
    JTArray(t) => "Array[\{t.show()}]"
    JTMap(k, v) => "Map[\{k.show()}, \{v.show()}]"
    JTStruct(n) => n
    JTUnsupported(s) => s
  }
}

///|
priv struct StructDef {
  name : String
  fields : Array[(String, JType, @basic.Location)] // (label, 类型, 字段位置)
}

///|
/// 从顶层声明收集 struct 定义。不认识的 TypeDecl 形态（enum/alias/abstract…）
/// 不进表——引用到时按 JTUnsupported 报；顶层混入非 struct 声明由 document 层把关。
fn collect_structs(
  impls : @list.List[@syntax.Impl]
) -> Map[String, StructDef] raise Diag {
  let env : Map[String, StructDef] = Map([])
  for i in impls {
    match i {
      TopTypeDef(decl) =>
        match decl.components {
          Record(fields~, ..) => {
            let name = decl.tycon
            if env.contains(name) {
              raise Diag(
                code=JDupStruct,
                loc=decl.loc,
                message="duplicate struct definition '\{name}'",
                help=Some(
                  "rename one of the structs; .json.mbt keeps one schema per name",
                ),
                path="",
              )
            }
            let fs : Array[(String, JType, @basic.Location)] = []
            for f in fields {
              fs.push((f.name.label, parse_type(f.ty), f.loc))
            }
            env[name] = { name: name, fields: fs }
          }
          _ => () // 非 record 形态的 TypeDecl：引用到时再报
        }
      _ => ()
    }
  }
  env
}

///|
/// LongIdent → 点分名字（仅本地名合法——跨包引用不属于 L0）
fn longident_name(id : @syntax.LongIdent) -> String {
  match id {
    Ident(name~) => name
    Dot(pkg~, id~) => "\{pkg}.\{id}"
  }
}

///|
fn parse_type(t : @syntax.Type) -> JType {
  match t {
    Name(constr_id~, tys~, ..) => {
      let id = longident_name(constr_id.id)
      let params = tys.to_array() // List 构造器不公开——数组化再判 arity
      match (id, params.length()) {
        ("Int", 0) => JTInt
        ("Int64", 0) => JTInt64
        ("Double", 0) => JTDouble
        ("String", 0) => JTString
        ("Bool", 0) => JTBool
        ("Array", 1) => JTArray(parse_type(params[0]))
        ("Map", 2) => JTMap(parse_type(params[0]), parse_type(params[1]))
        ("Unit", 0) | ("Byte", 0) | ("Char", 0) | ("UInt", 0) | ("UInt64", 0) | ("Float", 0) =>
          JTUnsupported(type_show_of(t)) // 有 MoonBit 定义但 JSON 无对应/非 L0 的内建
        (_, 0) => JTStruct(id) // 自定义 struct（无参裸名）；未定义名由 lookup_struct 报
        _ => JTUnsupported(type_show_of(t))
      }
    }
    Option(ty~, ..) => JTOption(parse_type(ty))
    _ => JTUnsupported(type_show_of(t))
  }
}

///|
/// 类型源形渲染仅用于诊断展示：未支持类型给原文提示（够用即可，不追求源文本级还原）
fn type_show_of(_t : @syntax.Type) -> String {
  "unsupported type"
}
