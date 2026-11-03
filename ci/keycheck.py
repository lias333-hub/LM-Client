import json, os, sys, time, urllib.request, urllib.error

BASE = os.environ.get("GEMINI_BASE", "https://generativelanguage.googleapis.com/v1beta")
KEY = os.environ.get("GEMINI_KEY", "")
PAUSE = float(os.environ.get("KC_PAUSE", "7"))


def note(msg, level="notice"):
    print("::%s title=keycheck::%s" % (level, msg.replace("\n", " ")[:900]))


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("x-goog-api-key", KEY)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=data, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            j = json.loads(raw)
        except Exception:
            j = {"raw": raw[:300]}
        return e.code, j
    except Exception as e:
        return 0, {"exception": type(e).__name__}


if not KEY:
    note("secret LM_EVAL_GEMINI_KEY is empty or missing (add it under Settings > Secrets and variables > Actions)")
    sys.exit(0)

note("key present, length=%d" % len(KEY))
code, j = call("GET", "/models?pageSize=200")
if code != 200:
    err = j.get("error", {}) if isinstance(j, dict) else {}
    note("list models failed http=%s status=%s message=%s" % (code, err.get("status"), str(err.get("message", j))[:300]), "error")
    sys.exit(0)

models = []
for m in j.get("models", []):
    name = m.get("name", "").replace("models/", "")
    if "generateContent" in m.get("supportedGenerationMethods", []) and ("flash" in name or "gemma" in name):
        models.append((name, m.get("inputTokenLimit"), m.get("outputTokenLimit")))
models.sort()
note("generateContent models with flash/gemma in the name: %d: %s" % (len(models), ", ".join("%s(in=%s)" % (n, i) for n, i, o in models[:40])))

tool = {"functionDeclarations": [{"name": "get_weather", "description": "Get the current weather of a city", "parameters": {"type": "OBJECT", "properties": {"city": {"type": "STRING"}}, "required": ["city"]}}]}
body = {"contents": [{"role": "user", "parts": [{"text": "What is the weather in Paris right now? Use the tool."}]}], "tools": [tool]}

# stable-looking candidates first (not previews/experimental/image/tts), capped to respect ~10 requests per minute
cands = [n for n, i, o in models if not any(x in n for x in ("preview", "exp", "image", "tts", "live", "audio", "thinking", "latest-"))]
cands = cands[:8]
ok = []
for n in cands:
    code, r = call("POST", "/models/%s:generateContent" % n, body)
    if code == 200:
        parts = (((r.get("candidates") or [{}])[0].get("content") or {}).get("parts") or [])
        fc = [p["functionCall"] for p in parts if isinstance(p, dict) and "functionCall" in p]
        u = r.get("usageMetadata", {})
        note("model=%s http=200 function_call=%s args=%s tokens(prompt=%s,out=%s,total=%s)" % (n, bool(fc), json.dumps(fc[0].get("args")) if fc else "-", u.get("promptTokenCount"), u.get("candidatesTokenCount"), u.get("totalTokenCount")))
        if fc:
            ok.append(n)
    else:
        err = r.get("error", {}) if isinstance(r, dict) else {}
        note("model=%s http=%s status=%s message=%s" % (n, code, err.get("status"), str(err.get("message", r))[:220]), "warning")
    time.sleep(PAUSE)
note("RESULT: models that answered with a tool call: %s" % (", ".join(ok) if ok else "none"))
