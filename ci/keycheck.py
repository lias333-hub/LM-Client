import json, os, sys, time, urllib.request, urllib.error

BASE = os.environ.get("GEMINI_BASE", "https://generativelanguage.googleapis.com/v1beta")
KEY = os.environ.get("GEMINI_KEY", "")
PAUSE = float(os.environ.get("KC_PAUSE", "7"))


import atexit

# GitHub keeps only 10 notice + 10 warning annotations per step, so collect everything and emit ONE annotation at exit.
REPORT = []
HAS_PROBLEM = []


def note(msg, level="notice"):
    line = ("[%s] " % level.upper() if level != "notice" else "") + msg.replace("\n", " ")[:1500]
    REPORT.append(line)
    print(line)


def _esc(t):
    return t.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _flush():
    print("::notice title=keycheck-report::" + _esc("\n".join(REPORT))[:60000])


atexit.register(_flush)


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("x-goog-api-key", KEY)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=data, timeout=90) as r:
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
# skip retired 2.x models (404 "no longer available to new users"), media/preview variants; always include Gemma (weak-model candidates)
cands = [n for n, i, o in models if n.startswith("gemini-3") and not any(x in n for x in ("preview", "exp", "image", "tts", "live", "audio", "thinking", "omni"))][:10]
cands += [n for n, i, o in models if n.startswith("gemma")][:3]
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

# ---- Interactions API probe (discovery: prints the real shapes so an adapter is built from data, not guesses)
def interactions_probe(names):
    seen = list(names)
    ftool = {"type": "function", "name": "get_weather", "description": "Get the current weather of a city", "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}
    sysi = "You are a concise assistant."
    for n in seen[:2]:
        code, r = call("POST", "/interactions", {"model": n, "system_instruction": sysi, "tools": [ftool], "input": "What is the weather in Paris right now? Use the tool."})
        if code != 200:
            err = r.get("error", {}) if isinstance(r, dict) else {}
            note("INTERACTIONS model=%s http=%s status=%s message=%s" % (n, code, err.get("status"), str(err.get("message", r))[:300]), "warning")
            time.sleep(PAUSE)
            continue
        steps = [x for x in (r.get("steps") or []) if isinstance(x, dict)]
        note("INTERACTIONS model=%s http=200 top_keys=%s id=%s status=%s step_types=%s usage=%s" % (n, sorted(r.keys()), bool(r.get("id")), r.get("status"), [x.get("type") for x in steps], json.dumps(r.get("usage", {}))[:400]))
        fcs = [x for x in steps if "function_call" in str(x.get("type", ""))]
        if not fcs:
            time.sleep(PAUSE)
            continue
        note("INTERACTIONS function_call step=%s" % json.dumps(fcs[0])[:500])
        cid = fcs[0].get("id") or fcs[0].get("call_id")
        time.sleep(PAUSE)
        code2, r2 = call("POST", "/interactions", {"model": n, "system_instruction": sysi, "tools": [ftool], "previous_interaction_id": r.get("id"),
                                                     "input": [{"type": "function_result", "name": fcs[0].get("name"), "call_id": cid, "result": "sunny, 18 C"}]})
        if code2 == 200:
            st2 = [x for x in (r2.get("steps") or []) if isinstance(x, dict)]
            note("INTERACTIONS follow-up (stateful function_result) http=200 step_types=%s text=%s" % ([x.get("type") for x in st2], json.dumps(st2)[:400]))
        else:
            err2 = r2.get("error", {}) if isinstance(r2, dict) else {}
            note("INTERACTIONS follow-up (stateful function_result) http=%s status=%s message=%s" % (code2, err2.get("status"), str(err2.get("message", r2))[:400]), "warning")
        time.sleep(PAUSE)


# Interactions probe on models that answered the tool call above (3.8-flash timed out in the first real run)
interactions_probe(ok[:2] if ok else [n for n, i, o in models if n.startswith("gemini-3")][:2])
note("DONE")
