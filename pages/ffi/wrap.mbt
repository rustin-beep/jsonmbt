// js 出口三件：返回 JSON 编码结果（{ok:true,...} / {ok:false,error}）——
// 诊断文本经 Json::stringify 转义，避免跨边界拼接的转义地狱
// Json API 与 src 同款（Json::boolean/string/array/object，object 接 Map）

///|
fn err_json(e : @src.Diag) -> String {
  let obj : Map[String, Json] = Map([])
  obj["ok"] = Json::boolean(false)
  obj["error"] = Json::string(e.render())
  Json::object(obj).stringify()
}

///|
/// JSON/JSONC 文本 → .json.mbt 全文（stem = 绑定名来源）
pub fn js_import(text : String, stem : String) -> String {
  let outcome = @src.import_source(text, path="input.json", stem~) catch {
    e => return err_json(e)
  }
  let hints : Array[Json] = []
  for h in outcome.hints {
    hints.push(Json::string(h.render()))
  }
  let obj : Map[String, Json] = Map([])
  obj["ok"] = Json::boolean(true)
  obj["content"] = Json::string(outcome.content)
  obj["hints"] = Json::array(hints)
  Json::object(obj).stringify()
}

///|
/// .json.mbt 源 → JSON 文本（紧凑形态）
pub fn js_build(src : String) -> String {
  let out = @src.build_source(src, path="input.json.mbt") catch {
    e => return err_json(e)
  }
  let obj : Map[String, Json] = Map([])
  obj["ok"] = Json::boolean(true)
  obj["json"] = Json::string(out)
  Json::object(obj).stringify()
}

///|
/// .json.mbt 源校验（check 语义：校验 + 内存构造，无降级 codegen）
pub fn js_check(src : String) -> String {
  @src.check_source(src, path="input.json.mbt") catch {
    e => return err_json(e)
  }
  let obj : Map[String, Json] = Map([])
  obj["ok"] = Json::boolean(true)
  Json::object(obj).stringify()
}

///|
fn main {
  // js 后端 release 会 tree-shake main 不可达的导出——显式引用保活
  ignore(js_import)
  ignore(js_build)
  ignore(js_check)
}
