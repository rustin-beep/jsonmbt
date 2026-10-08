// pages 样例矩阵全量冒烟（一次性勘探，勿入防线）——与 index.html 样例矩阵同步：
// 绿区应 ok、红区应报对应 J 码、build 侧断言降级产物特征
import { js_import, js_build } from './ffi.js';

const EAT = [
  '{"id": 1, "name": "demo", "cfg": {"debug": true, "ratio": 0.5}}',
  '{"tags": ["api", "web"], "matrix": [[1, 2], [3, 4]]}',
  '{"users": [{"nickname": null, "id": 1}, {"nickname": "x", "id": 2}]}',
  '{\n  // 用户配置\n  "port": 8080,\n  "hosts": ["a", "b"]\n}',
  '{"Content-Type": "application/json", "x_custom": "v"}',
  '{"actions": [{"Void": true}, {"Copy": true}]}',
  '{"id": 9007199254740993}',
  '{"pi": 3.14159, "neg": -0.5, "exp": 1e10}',
  '{"list": [], "nested": {"list": [1, 2]}}',
  '{"emoji": "🚀 中文"}',
];
const REJECT = [
  ['{"rows": [1, "a"]}', 'J4010'],
  ['{"id": 1, "u": null}', 'J4003'],
  ['{"big": 123456789012345678901234567890}', 'J4020'],
  ['{"k": 1, "k": 2}', 'J1003'],
  ['{"empty": {}, "id": 1}', 'J4002'],
  ['{"items": []}', 'J4001'],
  ['{"Content-Type": "text/html", "Content-Length": 123}', 'J4011'],
];
const BUILD = [
  ['enum tag 展开', 'struct Pt {\n  x : Int\n  y : Int\n}\nenum Shape {\n  Dot(Pt)\n  Unit\n}\npub let shapes : Array[Shape] = [Dot(Pt::{ x: 1, y: 2 }), Unit]', r => r.ok && r.json.includes('"case":"Dot"') && r.json.includes('"Unit"')],
  ['Option None→null', 'struct S {\n  nick : String?\n}\npub let s : S = S::{ nick: None }', r => r.ok && r.json === '{"nick":null}'],
  ['多行字符串', 'pub let doc : String = #|\n#| 第一行\n#| 第二行', r => r.ok && r.json.includes('第一行')],
  ['注释尾逗号丢弃', 'pub let s = {\n  "a": 1, // 会消失\n}', r => r.ok && r.json === '{"a":1}'],
];

let bad = 0;
for (const s of EAT) {
  const r = JSON.parse(js_import(s, 'demo'));
  if (!r.ok) { bad++; console.log('EAT 应绿却红:', r.error.split('\n')[0]); }
}
for (const [s, jcode] of REJECT) {
  const r = JSON.parse(js_import(s, 'demo'));
  if (r.ok || !r.error.includes(jcode)) { bad++; console.log('REJECT 应含', jcode, 'got:', r.ok ? 'ok!' : r.error.split('\n')[0]); }
}
for (const [name, s, ok] of BUILD) {
  const r = JSON.parse(js_build(s));
  if (!ok(r)) { bad++; console.log('BUILD', name, 'FAIL:', JSON.stringify(r).slice(0, 160)); }
}
// repr 保真专断（两段式：import content → build json）
const i64 = JSON.parse(js_build(JSON.parse(js_import('{"id": 9007199254740993}', 'demo')).content));
if (!(i64.ok && i64.json === '{"id":9007199254740993}')) { bad++; console.log('Int64 repr FAIL:', JSON.stringify(i64).slice(0, 120)); }
console.log(bad === 0 ? 'SMOKE ALL OK (eat 10 + reject 7 + build 4 + i64 1)' : 'SMOKE BAD=' + bad);
