"""诊断有道词典抓取问题 — 同时测试 HTML 和 jsonapi 两条路径"""
import sys
import re
import json
import gzip
import urllib.request
import urllib.error

WORD = sys.argv[1] if len(sys.argv) > 1 else "crops"

def fetch(url, headers=None):
    """返回 (body_str, final_url) 或 (None, None)"""
    if headers is None:
        headers = {}
    headers.setdefault("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    headers.setdefault("Accept-Language", "zh-CN,zh;q=0.9")
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        raw = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            raw = gzip.decompress(raw)
        return raw.decode("utf-8", errors="ignore"), resp.url
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}")
        return None, None
    except Exception as e:
        print(f"  请求失败: {e}")
        return None, None

def strip_tags(s):
    return re.sub(r'<[^>]+>', '', s).strip()


# ============================================================
# 1. HTML 路径诊断
# ============================================================
print(f"\n{'='*60}")
print(f"  HTML 抓取测试: {WORD}")
print(f"{'='*60}")

html, final_url = fetch(f"https://dict.youdao.com/w/{WORD}")
if html:
    print(f"  HTML 长度: {len(html)}")

    # 1a) 找到 trans-container 区域
    idx = html.find("trans-container")
    if idx >= 0:
        snippet = html[max(0, idx-80):idx+600]
        print(f"\n  [trans-container 附近 HTML ({idx})]:")
        print(f"  {snippet[:400]}")
    else:
        print("\n  >>> HTML 中根本没有 'trans-container'！")

    # 1b) 用现有正则匹配
    m = re.search(
        r'<div\s+class="trans-container"[^>]*>(.*?)</div>\s*<!--\s*trans-container',
        html, re.DOTALL,
    )
    if m:
        print(f"\n  [正则匹配成功] 内容: {m.group(1)[:300]}")
    else:
        print("\n  [正则匹配失败] 尝试不带注释后缀...")
        m = re.search(r'<div\s+class="trans-container"[^>]*>(.*?)</div>', html, re.DOTALL)
        if m:
            print(f"  [宽松匹配成功] 内容: {m.group(1)[:300]}")
        else:
            print("  [宽松匹配也失败]")
            # 看 class 名是否变了
            for cls in re.findall(r'class="([^"]*trans[^"]*)"', html):
                print(f"  发现可能的 class: {cls}")

    # 1c) 检查是否被 Cloudflare/验证码拦截
    if "cf-browser-verify" in html.lower() or "captcha" in html.lower():
        print("\n  >>> 可能被 Cloudflare 拦截！")
    if "请输入验证码" in html:
        print("\n  >>> 需要验证码！")

else:
    print("  HTML 抓取失败")


# ============================================================
# 2. jsonapi 路径诊断
# ============================================================
print(f"\n{'='*60}")
print(f"  jsonapi 测试: {WORD}")
print(f"{'='*60}")

body, _ = fetch(f"https://dict.youdao.com/jsonapi?q={WORD}&le=eng")
if body:
    try:
        data = json.loads(body)
    except json.JSONDecodeError as e:
        print(f"  JSON 解析失败: {e}")
        print(f"  原始响应前 500 字符: {body[:500]}")
        sys.exit(0)

    print(f"  顶层 keys: {list(data.keys())}")

    ec = data.get("ec")
    if ec is None:
        print("  >>> ec 字段不存在!")
    else:
        print(f"  ec.keys: {list(ec.keys())}")
        word_list = ec.get("word")
        if not word_list:
            print("  >>> ec.word 为空!")
        else:
            w = word_list[0]
            print(f"  wordEntry.keys: {list(w.keys())}")
            trs = w.get("trs")
            if trs is None:
                print("  >>> wordEntry 中无 'trs' 字段!")
            elif len(trs) == 0:
                print("  >>> trs 是空列表!")
            else:
                print(f"  trs ({len(trs)} 条):")
                for t in trs[:6]:
                    print(f"    pos={t.get('pos','')!r}  tran={t.get('tran','')!r}")

            # 看看有没有其他释义字段
            for k in w.keys():
                if k not in ("source", "usphone", "ukphone", "trs", "word"):
                    val = w[k]
                    if isinstance(val, str) and len(val) < 200:
                        print(f"  其他字段 {k}: {val!r}")
                    elif isinstance(val, list):
                        print(f"  其他字段 {k}: list({len(val)}) first={val[0] if val else 'empty'}")
                    else:
                        print(f"  其他字段 {k}: type={type(val).__name__}")

    # 2b) 检查 simple 字段（部分单词释义在这里）
    simple = data.get("simple")
    if simple:
        print(f"\n  simple.keys: {list(simple.keys())}")
        sw = simple.get("word")
        if sw and isinstance(sw, list) and sw:
            print(f"  simple.word[0].keys: {list(sw[0].keys())}")
            simple_trs = sw[0].get("trs")
            if simple_trs:
                print(f"  simple trs: {simple_trs}")

    # 2c) 检查 ee 字段（英英释义）
    ee = data.get("ee")
    if ee:
        print(f"\n  ee 存在, keys={list(ee.keys())}")
else:
    print("  jsonapi 抓取失败")

print()
