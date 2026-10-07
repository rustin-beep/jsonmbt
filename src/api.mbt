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
/// 降级：.json.mbt 源 → 紧凑 JSON 文本（确定性投影；类型名剥除、字面量直译）
pub fn build_source(
  src : String,
  path? : String = "",
  expected_name? : String,
) -> String raise Diag {
  let doc = analyze(src, path~, expected_name?)
  build_value_of(doc).stringify()
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
/// 摄取：JSON/JSONC 文本 → .json.mbt 全文
/// 管线：字符串感知剥离（D-9）→ 自持 RFC 8259 解析（保 number repr/键序/
/// 重复键拒绝）→ 形状推断（D-1/D-2/逃生门）→ fmt-canonical 生成
/// stem：D-7 命名（pub let stem；struct 名 capitalize(stem)）
pub fn import_source(
  json_text : String,
  path? : String = "<json>",
  stem~ : String,
) -> ImportOutcome raise Diag {
  let stripped = strip_jsonc(json_text)
  let root = json_parse(stripped, fname=path)
  let result = infer_shapes(root, stem~, fname=path)
  let content = generate_source(result, root, stem~, src_name=path)
  { content, hints: result.hints, }
}
