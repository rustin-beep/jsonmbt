// jsonmbt CLI 的 native FFI 桩：stdin 读全量 / stderr 写 / 原子 rename
// （x/fs 无此三件——最小自持桩，UTF-8 路径 Windows 侧转宽字符）

#include "moonbit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#endif

MOONBIT_FFI_EXPORT moonbit_bytes_t jsonmbt_read_stdin(void) {
  size_t cap = 1 << 16;
  size_t len = 0;
  char *buf = (char *)malloc(cap);
  for (;;) {
    if (len == cap) {
      cap *= 2;
      char *nb = (char *)realloc(buf, cap);
      if (nb == NULL) {
        free(buf);
        return moonbit_make_bytes(0, 0);
      }
      buf = nb;
    }
    size_t n = fread(buf + len, 1, cap - len, stdin);
    if (n == 0) {
      break;
    }
    len += n;
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, buf, len);
  free(buf);
  return out;
}

MOONBIT_FFI_EXPORT void jsonmbt_write_stdout(moonbit_bytes_t data, int32_t len) {
#ifdef _WIN32
  // binary mode: no CRLF translation - product bytes must be stable across
  // platforms (stdout sibling of issue #1 stderr fix; caught by L2 pretty case)
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  fwrite(data, 1, (size_t)len, stdout);
  fflush(stdout);
}

MOONBIT_FFI_EXPORT void jsonmbt_write_stderr(moonbit_bytes_t data, int32_t len) {
#ifdef _WIN32
  // binary mode: no CRLF translation - diagnostics channel (D-10) must be
  // byte-identical across platforms (first drift caught by layer-2 golden)
  _setmode(_fileno(stderr), _O_BINARY);
#endif
  fwrite(data, 1, (size_t)len, stderr);
  fflush(stderr);
}

#ifdef _WIN32
static wchar_t *jsonmbt_utf8_to_wchar(const char *s, int32_t len) {
  int wlen = MultiByteToWideChar(CP_UTF8, 0, s, len, NULL, 0);
  wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)(wlen + 1));
  MultiByteToWideChar(CP_UTF8, 0, s, len, w, wlen);
  w[wlen] = 0;
  return w;
}
#endif

MOONBIT_FFI_EXPORT int jsonmbt_rename(moonbit_bytes_t from, int32_t from_len,
                                      moonbit_bytes_t to, int32_t to_len) {
#ifdef _WIN32
  // MSVC 的 rename 不覆盖已存在目标：先 remove 再 rename（微小窗口期登记为
  // 平台限制——POSIX 侧 rename 天然原子覆盖）
  wchar_t *wto = jsonmbt_utf8_to_wchar((const char *)to, to_len);
  _wremove(wto);
  wchar_t *wfrom = jsonmbt_utf8_to_wchar((const char *)from, from_len);
  int r = _wrename(wfrom, wto);
  free(wfrom);
  free(wto);
  return r;
#else
  char *f = (char *)malloc((size_t)from_len + 1);
  memcpy(f, from, (size_t)from_len);
  f[from_len] = 0;
  char *t = (char *)malloc((size_t)to_len + 1);
  memcpy(t, to, (size_t)to_len);
  t[to_len] = 0;
  int r = rename(f, t);
  free(f);
  free(t);
  return r;
#endif
}
