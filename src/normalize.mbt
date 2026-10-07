// D-11 规范化器 N：值语义等价的比较底座（往返锚 N(build(import(J))) == N(J) 的 N）
// 语义分工（实测校准）：N 只做值语义——RFC 8259 数字是抽象数值，1 ≡ 1.0，
//   Double 值比；大数（超 Double 范围）core/json 走 out-of-range fallback 保留
//   源文本 repr（core 实测：repr 仅此场景 Some）——大数按 repr 文本比。
// 「1 vs 1.0 保留」属降级输出侧（raw 直传，build 已实现）——两维度分立。
// 其余维度：字符串按解码码点（输出转义统一走 stringify 的 write_escaped——
//   控制字符 \u00XX 全族，对齐陷阱 #27）；键序=源序（Map 插入序）不排序——
//   输出确定性维度，值语义相等本身键序不敏感（RFC 8259 对象无序）；
//   null/空容器直译（空容器语义属 importer D-1，降级侧 [] / {} 原样）
// 已知不可逐字节面（D-11 登记）：整数尾数指数（1e2 在 .json.mbt 层写不出）/
//   超 Int64 / 超 17 位有效数字浮点 / JSON 层重复键=拒绝

///|
/// canon = 值语义等价文本：repr 缺失 → to_string（ryu 短表示）；
/// repr 存在（core 超范围 fallback / 降级器自产的源文本）——纯整数经
/// numeric_text 归一十进制（与降级器同一数值管线，单源），超 Int64 保留文本
fn canon_number_text(n : Double, repr~ : String?) -> String {
  match repr {
    None => n.to_string()
    Some(r) => {
      let is_plain_int = !(r.contains(".") || r.contains("e") || r.contains("E"))
      if is_plain_int {
        match numeric_text(r) {
          Ok(t, _) => t
          Overflow(_) | Illegal => r // 超 Int64：文本即身份（十进制唯一）
        }
      } else {
        n.to_string() // 浮点形态：Double 短表示归一（1.0 → "1"）
      }
    }
  }
}

///|
/// N：递归规范化（Number 的 repr 改写为规范文本，结构原样保序）
pub fn normalize_json(j : Json) -> Json {
  match j {
    Number(n, repr~) => {
      let canon = canon_number_text(n, repr~)
      Json::number(n, repr=canon)
    }
    Array(a) => {
      let out : Array[Json] = []
      for e in a {
        out.push(normalize_json(e))
      }
      Json::array(out)
    }
    Object(o) => {
      let out : Map[String, Json] = Map([])
      o.each(fn(k, v) { out[k] = normalize_json(v) })
      Json::object(out)
    }
    other => other
  }
}

///|
/// Number → 规范文本（避免同 match 双 labeled 绑定撞名的中转）
fn canon_of(j : Json) -> String {
  if j is Number(n, repr~) {
    canon_number_text(n, repr~)
  } else {
    abort("unreachable: canon_of only accepts Number")
  }
}

///|
/// 值语义相等（规范化后比较；Number 按 repr 规范文本——整型 -0 与 0 经
/// numeric_text 归一后相等（实测 N(-0)==N(0)=="0"，与 JS stringify 同款），
/// 对象键序不敏感、数组顺序敏感）
pub fn json_value_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (String(x), String(y)) => x == y
    (Number(_), Number(_)) => canon_of(a) == canon_of(b)
    (Array(x), Array(y)) => {
      if x.length() != y.length() {
        return false
      }
      for i, e in x {
        if !json_value_equal(e, y[i]) {
          return false
        }
      }
      true
    }
    (Object(x), Object(y)) => {
      if x.length() != y.length() {
        return false
      }
      let mut all_eq = true
      x.each(fn(k, v) {
        match y.get(k) {
          Some(v2) => if !json_value_equal(v, v2) { all_eq = false }
          None => all_eq = false
        }
      })
      all_eq
    }
    _ => false
  }
}

///|
/// N 的文本形态：JSON 文本 → 规范化紧凑文本（对拍锚与人工检视用）。
/// 解析走自持 json_parse（审 P3 单源化：原 core/json 路径参数 deprecated、
/// 重复键静默、错误无行列——D-11 全语义归一到自家解析器）
pub fn normalize_json_text(text : String) -> String raise Diag {
  let j = json_parse(text, fname="<json>")
  normalize_json(j).stringify()
}
