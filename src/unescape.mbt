// MoonBit 字符串字面量解码器（探针实测：Constant::String 的 raw 未解码——
// 转义序列原样保留在源文本里；值树必须存解码值，输出侧由 stringify 统一转义）
// 转义集（MoonBit 语言面）：\' \" \\ \n \r \t \b \f \0 \xHH \u{1..6 位十六进制}

///|
fn unescape_string(raw : String, loc : @basic.Location) -> String raise Diag {
  let buf = StringBuilder()
  let view = raw.to_array() // code-unit 索引会撞 surrogate——Char 级访问
  let n = view.length()
  let mut i = 0
  while i < n {
    let ch = view[i]
    if ch == '\\' {
      i = i + 1
      if i >= n {
        raise malformed_string(raw, loc)
      }
      match view[i] {
        '\'' => buf.write_char('\'')
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'b' => buf.write_char('\b')
        'f' => buf.write_char('\f')
        '0' => buf.write_char('\u0000')
        'x' => {
          // \xHH：恰好两位十六进制
          if i + 2 >= n {
            raise malformed_string(raw, loc)
          }
          match hex_pair(view[i + 1], view[i + 2]) {
            Some(b) => {
              buf.write_char(b.to_int().unsafe_to_char())
              i = i + 2
            }
            None => raise malformed_string(raw, loc)
          }
        }
        'u' => {
          // \u{...}：花括号内 1..6 位十六进制（MoonBit 无 \uXXXX 定长形态）
          if i + 1 >= n || view[i + 1] != '{' {
            raise malformed_string(raw, loc)
          }
          let mut j = i + 2
          let mut acc : UInt = 0U
          let mut digits = 0
          let mut closed = false
          while j < n {
            let c = view[j]
            if c == '}' {
              closed = true
              break
            }
            match hex_digit(c) {
              Some(d) => {
                acc = acc * 16U + d.reinterpret_as_uint()
                digits = digits + 1
                j = j + 1
              }
              None => raise malformed_string(raw, loc)
            }
          }
          if !(closed) || digits == 0 || digits > 6 || acc > 0x10FFFFU {
            raise malformed_string(raw, loc)
          }
          buf.write_char(acc.reinterpret_as_int().unsafe_to_char())
          i = j
        }
        _ => raise malformed_string(raw, loc)
      }
      i = i + 1
    } else {
      buf.write_char(ch)
      i = i + 1
    }
  }
  buf.to_string()
}

///|
fn hex_digit(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn hex_pair(hi : Char, lo : Char) -> Byte? {
  match (hex_digit(hi), hex_digit(lo)) {
    (Some(a), Some(b)) => Some((a * 16 + b).to_byte())
    _ => None
  }
}

///|
fn malformed_string(raw : String, loc : @basic.Location) -> Diag {
  Diag(
    code=JBadLiteral,
    loc=loc,
    message="malformed escape sequence in string literal \"\{raw}\"",
    help=None,
    path="",
  )
}
