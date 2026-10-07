// D-9 JSONC 注释剥离：字符串字面量感知（裸正则必误伤 "http://x" / "a//b"——
// 三形态负样本锚钉死）；注释替换为等长空格（不含换行）——诊断行列不漂移；
// 纯函数 = 剥离字节确定性（同输入恒同输出）；无注释输入零改动（内容探测
// 的实质：剥离后走同一条 parse 路径，不看扩展名）

///|
pub fn strip_jsonc(src : String) -> String {
  let view = src.to_array() // code-unit 索引会撞 surrogate——Char 级访问
  let n = view.length()
  let buf = StringBuilder()
  let mut i = 0
  while i < n {
    let c = view[i]
    // 字符串字面量：原样透传直到闭合引号（\" 转义跳过）——感知的核心
    if c == '"' {
      buf.write_char('"')
      i = i + 1
      let mut closed = false
      while i < n {
        let sc = view[i]
        if sc == '\\' && i + 1 < n {
          buf.write_char(sc)
          buf.write_char(view[i + 1])
          i = i + 2
        } else if sc == '"' {
          buf.write_char('"')
          i = i + 1
          closed = true
          break
        } else {
          buf.write_char(sc)
          i = i + 1
        }
      }
      if !closed {
        // 未闭合字符串：交给 JSON 解析器报错（这里只保透传）
        return buf.to_string()
      }
      continue
    }
    // 行注释 //...：替换到行尾（不含换行符——等长空格保行列）
    if c == '/' && i + 1 < n && view[i + 1] == '/' {
      while i < n && view[i] != '\n' {
        buf.write_char(' ')
        i = i + 1
      }
      continue
    }
    // 块注释 /* ... */：等长空格（换行保留原位——行列不漂）
    if c == '/' && i + 1 < n && view[i + 1] == '*' {
      buf.write_char(' ')
      buf.write_char(' ')
      i = i + 2
      while i < n {
        if view[i] == '*' && i + 1 < n && view[i + 1] == '/' {
          buf.write_char(' ')
          buf.write_char(' ')
          i = i + 2
          break
        }
        if view[i] == '\n' {
          buf.write_char('\n')
        } else {
          buf.write_char(' ')
        }
        i = i + 1
      }
      continue
    }
    buf.write_char(c)
    i = i + 1
  }
  buf.to_string()
}
