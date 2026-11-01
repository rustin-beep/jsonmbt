// #51 内层锚：UTF-8 前置校验（严格 RFC 3629 口径）
// 形态面：合法全谱（ASCII/2/3/4 字节/BOM/emoji）零误伤 + 解码往返逐字节；
// 非法全族（孤立续字节/overlong/surrogate 编码/超 U+10FFFF/截断）逐类点名
// 字节与偏移——文案即层 2 断言的 contains 源（单点）。

///|
fn b2s(items : Array[Int]) -> Bytes {
  let arr : Array[Byte] = []
  for b in items {
    arr.push(b.to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 非法样本 → 错误文案首行（raise 捕获形态——层 1 断言点名字节/偏移；
/// help 行属文案细节不锚，防措辞微调翻锚）
fn expect_invalid(items : Array[Int]) -> String {
  let bytes = b2s(items)
  let msg = try {
    @src.validate_utf8(bytes)
    "NOT-RAISED"
  } catch {
    e => if e is Diag(..) { e.render() } else { "NON-DIAG" }
  }
  match msg.find("\n") {
    Some(i) => msg[:i].to_string()
    None => msg
  }
}

///|
/// 合法样本 → true（raise 即 false）
fn ok(items : Array[Int]) -> Bool {
  try {
    @src.validate_utf8(b2s(items))
    true
  } catch {
    _ => false
  }
}

///|
test "utf8 : 合法面全谱——ASCII/多字节/BOM/emoji 不误伤" {
  // ASCII
  inspect(ok([0x7B, 0x22, 0x61, 0x22, 0x7D]), content="true")
  // 2 字节（é = C3 A9）
  inspect(ok([0xC3, 0xA9]), content="true")
  // 3 字节（CJK = E4 B8 AD）
  inspect(ok([0xE4, 0xB8, 0xAD]), content="true")
  // 4 字节（emoji 😀 = F0 9F 98 80）
  inspect(ok([0xF0, 0x9F, 0x98, 0x80]), content="true")
  // BOM（EF BB BF 合法 UTF-8——剥不剥是 strip_jsonc 的事）
  inspect(ok([0xEF, 0xBB, 0xBF, 0x7B]), content="true")
  // F4 8F BF BF = U+10FFFF（上界含端点）
  inspect(ok([0xF4, 0x8F, 0xBF, 0xBF]), content="true")
  // ED 9F BF = U+D7FF（surrogate 下界之下合法）
  inspect(ok([0xED, 0x9F, 0xBF]), content="true")
  // 「校验通过 → to_utf8_string 无损」的前提事实（合法 UTF-8 上解码
  // 逐字节往返）不在此锚——它属运行时行为面，层 2 端到端锚
  // invalid-utf8-gate 的 emoji 往返臂守（cmd 侧 @unicode 在位）
}

///|
test "utf8 : 非法面——issue #51 实测字节全点名" {
  // 0x80 孤立续字节（值位静默丢弃形态的源）
  inspect(
    expect_invalid([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0x80, 0x22, 0x7D]),
    content="jsonmbt: error [J1004] :1:7 invalid UTF-8 byte 0x80 at offset 6 (line 1, column 7)",
  )
  // 0xFE（moon 解码改写形态的源；0xFE/0xFF 永不合法）
  inspect(
    expect_invalid([0xFE]),
    content="jsonmbt: error [J1004] :1:1 invalid UTF-8 byte 0xFE at offset 0 (line 1, column 1)",
  )
  // issue 原样本四连 fe fe ff ff——首个即点名
  inspect(
    expect_invalid([0x22, 0xFE, 0xFE, 0xFF, 0xFF, 0x22]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0xFE at offset 1 (line 1, column 2)",
  )
  // 0xFF
  inspect(
    expect_invalid([0x22, 0xFF, 0x22]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0xFF at offset 1 (line 1, column 2)",
  )
  // 0xC0 overlong 首字节（含 C0/C1/F5..FF 全族拒）
  inspect(
    expect_invalid([0x22, 0xC0, 0x22]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0xC0 at offset 1 (line 1, column 2)",
  )
}

///|
test "utf8 : 非法面——结构化非法（overlong/surrogate/超界/截断）逐类" {
  // E0 9F 80 = overlong 3 字节（E0 后必须 A0..）
  inspect(
    expect_invalid([0xE0, 0x9F, 0x80]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0x9F at offset 1 (line 1, column 2)",
  )
  // ED A0 80 = U+D800 surrogate 编码（ED 后必须 ..9F）
  inspect(
    expect_invalid([0xED, 0xA0, 0x80]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0xA0 at offset 1 (line 1, column 2)",
  )
  // F0 8F BF BF = overlong 4 字节（F0 后必须 90..）
  inspect(
    expect_invalid([0xF0, 0x8F, 0xBF, 0xBF]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0x8F at offset 1 (line 1, column 2)",
  )
  // F4 90 80 80 = 超 U+10FFFF（F4 后必须 ..8F）
  inspect(
    expect_invalid([0xF4, 0x90, 0x80, 0x80]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0x90 at offset 1 (line 1, column 2)",
  )
  // F5..FF 首字节直接拒
  inspect(
    expect_invalid([0xF5]),
    content="jsonmbt: error [J1004] :1:1 invalid UTF-8 byte 0xF5 at offset 0 (line 1, column 1)",
  )
  // 截断在文件尾（E4 B8 缺第三字节）——点名首字节位置
  inspect(
    expect_invalid([0x22, 0xE4, 0xB8]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0xE4 at offset 1 (line 1, column 2)",
  )
  // 后继非续字节（C3 7B——第二字节落到 ASCII）点名第二字节
  inspect(
    expect_invalid([0xC3, 0x7B]),
    content="jsonmbt: error [J1004] :1:2 invalid UTF-8 byte 0x7B at offset 1 (line 1, column 2)",
  )
}

///|
test "utf8 : 行列定位——第二行的非法字节报 line 2" {
  // {\n"\x80"——0x80 落在第二行第三字节
  inspect(
    expect_invalid([0x7B, 0x0A, 0x22, 0x80, 0x22]),
    content="jsonmbt: error [J1004] :2:2 invalid UTF-8 byte 0x80 at offset 3 (line 2, column 2)",
  )
}
