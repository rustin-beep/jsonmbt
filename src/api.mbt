// 对外门面：check/build 同一条路径（D-8 check = build 的 dry-run——两套校验语义必漂移）
// CLI 与 moon test 内层锚都只经由此面；产物 = 紧凑 JSON（键序=源序、转义=core 全族）

///|
/// 校验 .json.mbt 源（失败 raise Diag，成功 Unit；无任何写副作用）
pub fn check_source(
  src : String,
  path~ : String = "",
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
  path~ : String = "",
  expected_name? : String,
) -> String raise Diag {
  let doc = analyze(src, path~, expected_name?)
  build_value_of(doc).stringify()
}

///|
/// 值树形态（import→build 往返锚与未来工具消费）
pub fn build_value(
  src : String,
  path~ : String = "",
  expected_name? : String,
) -> Json raise Diag {
  let doc = analyze(src, path~, expected_name?)
  build_value_of(doc)
}

///|
fn build_value_of(doc : Doc) -> Json raise Diag {
  l0_expr(doc.structs, doc.root_expr, doc.root_ty, 0)
}
