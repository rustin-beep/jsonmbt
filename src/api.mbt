// 对外门面：check/build 同一条路径（D-8 check = build 的 dry-run——两套校验语义必漂移）
// CLI 与 moon test 内层锚都只经由此面；产物 = 紧凑 JSON（键序=源序、转义=core 全族）

///|
/// 校验 .json.mbt 源（失败 raise Diag，成功 Unit；无任何写副作用）
pub fn check_source(
  src : String,
  path? : String = "",
  expected_name? : String,
) -> Unit raise Diag {
  let doc = analyze(src, path~, expected_name?)
  let _ = build_value_of(doc)
  ()
}

///|
/// 降级：.json.mbt 源 → JSON 文本（默认紧凑；pretty 形态与 Go
/// json.Encoder SetIndent("", "  ") 在「键序=源序」前提下逐字节一致
/// 含尾换行（Go struct 序列化字段声明序=源序的场景，Vitro 门禁实测）；
/// Go map 序列化走字典序、任意手写基线不承诺逐字节——那些场景的承诺
/// 是值语义等价（审 P1 勘误：原表述缺前提限定））
pub fn build_source(
  src : String,
  path? : String = "",
  expected_name? : String,
  pretty? : Bool = false,
) -> String raise Diag {
  let doc = analyze(src, path~, expected_name?)
  if pretty {
    build_value_of(doc).stringify(indent=2) + "\n"
  } else {
    build_value_of(doc).stringify()
  }
}

///|
/// 值树形态（import→build 往返锚与未来工具消费）
pub fn build_value(
  src : String,
  path? : String = "",
  expected_name? : String,
) -> Json raise Diag {
  let doc = analyze(src, path~, expected_name?)
  build_value_of(doc)
}

///|
fn build_value_of(doc : Doc) -> Json raise Diag {
  l0_expr(doc.structs, doc.root_expr, doc.root_ty, 0)
}

///|
/// import 产物（hints 为 rc-0 提示——tagged-enum 识别等，CLI 走 stderr 通道）
pub(all) struct ImportOutcome {
  content : String // 生成的 .json.mbt 全文
  hints : Array[Diag]
}

///|
/// stem → 合法 binding（label 域标识符）：非法字符→下划线、大写→小写、
/// 数字/非法开头→x_ 前缀、空→x。类型命名（capitalize）共用此基。
pub fn sanitize_stem(name : String) -> String {
  if name == "" {
    return "x"
  }
  let buf = StringBuilder()
  for ch in name {
    let c = ch.to_int()
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      c >= 0x80 {
      buf.write_char(ch)
    } else if ch >= 'A' && ch <= 'Z' {
      buf.write_char(Char::from_int(c + 32))
    } else {
      buf.write_char('_')
    }
  }
  let out = buf.to_string()
  let first = out[0]
  let legal_head = (first >= 'a' && first <= 'z') ||
    first == '_' ||
    first.to_int() >= 0x80
  if legal_head {
    out
  } else {
    "x_" + out
  }
}

///|
/// 摄取：JSON/JSONC 文本 → .json.mbt 全文
/// 管线：字符串感知剥离（D-9）→ 自持 RFC 8259 解析（保 number repr/键序/
/// 重复键拒绝）→ 形状推断（D-1/D-2/逃生门）→ fmt-canonical 生成
/// stem：D-7 命名（pub let stem；struct 名 capitalize(stem)）
pub fn import_source(
  json_text : String,
  path? : String = "<json>",
  stem~ : String,
  taken_names? : Array[String] = [],
) -> ImportOutcome raise Diag {
  // stem 前置清洗（化石批量实锤："array_address.c" 文件名直接作 stem 产
  // 非法 binding/类型名——曾靠生成保险丝兜底成 internal 错，现正名）
  let stem = sanitize_stem(stem)
  let stripped = strip_jsonc(json_text)
  let root = json_parse(stripped, fname=path)
  let result = infer_shapes(root, stem=stem, fname=path, taken=taken_names)
  let content = generate_source(result, root, stem~, src_name=path)
  // 保险丝（审 P1-1 处方）：产物丢回自家校验器回吃——生成器任何非法输出
  // 在落盘前 fail loud（import 产物承诺 = 合法 .json.mbt，PLAN §1.3）
  check_source(content, path=path + ".mbt", expected_name=stem) catch {
    e => {
      // 原始诊断透出（自证可诊断：说清产物哪一行非法）
      let detail : String = if e is Diag(..) {
        e.render()
      } else {
        "non-Diag error"
      }
      raise Diag(
        code=JIO,
        loc=dummy_loc(),
        message="internal: import produced an invalid .json.mbt (generator bug); failing check says: \{detail}",
        help=Some(
          "please report this with the input JSON — the generator must never emit invalid output",
        ),
        path~,
      )
    }
  }
  { content, hints: result.hints, }
}
