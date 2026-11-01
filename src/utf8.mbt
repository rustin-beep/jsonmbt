// #51：字节级 UTF-8 前置校验（RFC 3629 严格口径）。
// 背景：MoonBit 运行时字节→String 解码对非法 UTF-8 不 fail loud——实测
// 0x80/0xC0 被静默丢弃（值变空串）、0xFE 0xFF 被改写为别的码位、四连
// 非法字节直接 panic（rc 0xC0000409）。解码发生在自持 JSON 解析器之前，
// 损坏被烙进字符串后下游所有闸（import/check/--check）全绿——违反
// PLAN §0「解压对值无损」与 RFC 8259 §8.1。本模块把校验前移到字节层：
// 字节序列 → 校验通过 → 才允许进 String。
// 口径：严格 RFC 3629——overlong（C0/C1/E0 80..）、surrogate（ED A0..BF）、
// 超 U+10FFFF（F4 90..）、F5..FF 全拒；与「MoonBit 解码容忍多少」无关
//（对拍标准是 RFC，不是运行时行为）。

///|
fn is_cont(b : Int) -> Bool {
  b >= 0x80 && b <= 0xBF
}

///|
/// 首个非法字节的位置与字节值；合法 → None。
/// 返回 (offset, byte)：offset 为 0 起字节偏移——诊断文案「点名字节」用。
fn utf8_first_invalid(bytes : Bytes) -> (Int, Int)? {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i].to_int()
    if b <= 0x7F {
      i = i + 1
      continue
    }
    // 多字节序列首字节 → 决定后续 continuation 窗口（严格 RFC 3629 表）
    let (len, lo2, hi2) : (Int, Int, Int) = if b >= 0xC2 && b <= 0xDF {
      (2, 0x80, 0xBF)
    } else if b == 0xE0 {
      (3, 0xA0, 0xBF) // E0 后必须 A0..（拒 overlong 2 字节区）
    } else if b >= 0xE1 && b <= 0xEC {
      (3, 0x80, 0xBF)
    } else if b == 0xED {
      (3, 0x80, 0x9F) // ED 后必须 ..9F（拒 surrogate 编码）
    } else if b == 0xEE || b == 0xEF {
      (3, 0x80, 0xBF)
    } else if b == 0xF0 {
      (4, 0x90, 0xBF) // F0 后必须 90..（拒 overlong 3 字节区）
    } else if b >= 0xF1 && b <= 0xF3 {
      (4, 0x80, 0xBF)
    } else if b == 0xF4 {
      (4, 0x80, 0x8F) // F4 后必须 ..8F（拒超 U+10FFFF）
    } else {
      // 0x80..0xBF（孤立续字节）/ 0xC0 0xC1（overlong）/ 0xF5..0xFF（永不合法）
      return Some((i, b))
    }
    // 序列长度越界（截断在文件尾）→ 点名首字节位置
    if i + len > n {
      return Some((i, b))
    }
    let b2 = bytes[i + 1].to_int()
    if b2 < lo2 || b2 > hi2 {
      return Some((i + 1, b2))
    }
    // 其余 continuation 字节一律 80..BF
    let mut k = 2
    while k < len {
      let bk = bytes[i + k].to_int()
      if !is_cont(bk) {
        return Some((i + k, bk))
      }
      k = k + 1
    }
    i = i + len
  }
  None
}

///|
/// 字节偏移 → (行号, cnum, bol)：cnum/bol 为字节口径（与 jsonparse 同
/// 口径——列 = cnum - bol + 1）。
fn line_of_offset(bytes : Bytes, at : Int) -> (Int, Int, Int) {
  let mut line = 1
  let mut bol = 0
  let mut i = 0
  while i < at && i < bytes.length() {
    if bytes[i].to_int() == 0x0A {
      line = line + 1
      bol = i + 1
    }
    i = i + 1
  }
  (line, at, bol)
}

///|
/// 输入字节流的 UTF-8 合法性闸（#51）：非法 → J1004 fail loud（点名
/// 字节 + 偏移 + 行列）；合法 → Unit（调用方随后解码即无损）。
/// 键位/值位/任意位置统一（解码前拦截——比解析器更早，无从偏袒）。
pub fn validate_utf8(bytes : Bytes, path~ : String = "") -> Unit raise Diag {
  match utf8_first_invalid(bytes) {
    None => ()
    Some((at, b)) => {
      let (lnum, cnum, bol) = line_of_offset(bytes, at)
      raise Diag(
        code=JInvalidUtf8,
        loc={
          start: { fname: path, lnum, bol, cnum },
          end: { fname: path, lnum, bol, cnum },
        },
        message="invalid UTF-8 byte 0x\{hex2(b)} at offset \{at} (line \{lnum}, column \{cnum - bol + 1})",
        help=Some(
          "input must be UTF-8 (RFC 8259 §8.1) — jsonmbt refuses to silently replace or drop bytes; fix the source file encoding",
        ),
        path~,
      )
    }
  }
}

///|
fn hex2(b : Int) -> String {
  jhex_digit((b >> 4) & 0xF) + jhex_digit(b & 0xF)
}

///|
fn jhex_digit(v : Int) -> String {
  if v < 10 {
    v.to_string()
  } else {
    Char::from_int(v - 10 + 0x41).to_string()
  }
}
