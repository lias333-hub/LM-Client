"""Which generationConfig.thinkingConfig really turns Gemini thinking off (or down)?

Runs the same small question on a few Gemini models with several thinkingConfig variants and prints only HTTP codes,
error messages and token counts (never the key, never the model's text). One annotation at exit.
Used to choose the mapping for the app's thinking level 0 ("off") before changing the adapter."""
import json, os, sys, time, atexit, urllib.request, urllib.error

BASE = os.environ.get("GEMINI_BASE", "https://generativelanguage.googleapis.com/v1beta")
KEY = os.environ.get("GEMINI_KEY", "")
PAUSE = float(os.environ.get("KC_PAUSE", "8"))
MODELS = [m for m in os.environ.get("TC_MODELS", "gemini-3.5-flash,gemini-3.1-flash-lite").split(",") if m]

REPORT = []


def note(msg):
    line = msg.replace("\n", " ")[:1500]
    REPORT.append(line)
    print(line)


def _esc(t):
    return t.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


atexit.register(lambda: print("::notice title=thinkcheck-report::" + _esc("\n".join(REPORT))[:60000]))


def call(model, body):
    req = urllib.request.Request("%s/models/%s:generateContent" % (BASE, model), method="POST")
    req.add_header("x-goog-api-key", KEY)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data=json.dumps(body).encode(), timeout=120) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:300]}
    except Exception as e:
        return 0, {"exception": type(e).__name__}


if not KEY:
    note("secret LM_EVAL_GEMINI_KEY is empty or missing")
    sys.exit(0)

PROMPT = ("How many times does the letter r appear in 'strawberry raspberry'? "
          "Then give the first five prime numbers after 100. Answer in two short lines.")
TOOL = [{"functionDeclarations": [{"name": "read_file", "description": "Read a text file.",
                                   "parameters": {"type": "OBJECT", "properties": {"path": {"type": "STRING"}}, "required": ["path"]}}]}]

VARIANTS = [
    ("none (no thinkingConfig)", None),
    ("level=minimal", {"thinkingLevel": "minimal"}),
    ("level=low", {"thinkingLevel": "low"}),
    ("level=minimal+includeThoughts", {"thinkingLevel": "minimal", "includeThoughts": True}),
    ("budget=0", {"thinkingBudget": 0}),
]

note("thinkcheck: key present, length=%d, models=%s" % (len(KEY), ",".join(MODELS)))
for model in MODELS:
    for label, tc in VARIANTS:
        body = {"contents": [{"role": "user", "parts": [{"text": PROMPT}]}]}
        if tc is not None:
            body["generationConfig"] = {"thinkingConfig": tc}
        code, j = call(model, body)
        if code == 200:
            u = j.get("usageMetadata", {}) if isinstance(j, dict) else {}
            parts = []
            try:
                parts = j["candidates"][0]["content"]["parts"]
            except Exception:
                pass
            thought_parts = sum(1 for p in parts if isinstance(p, dict) and p.get("thought"))
            note("%s | %s | 200 | thoughts=%s out=%s prompt=%s | thought_parts=%d parts=%d" % (
                model, label, u.get("thoughtsTokenCount", "-"), u.get("candidatesTokenCount", "-"),
                u.get("promptTokenCount", "-"), thought_parts, len(parts)))
        else:
            err = j.get("error", {}) if isinstance(j, dict) else {}
            note("%s | %s | HTTP %s | %s" % (model, label, code, str(err.get("message", j))[:220]))
        time.sleep(PAUSE)
    # tool calling still answers with the lowest thinking level
    body = {"contents": [{"role": "user", "parts": [{"text": "Read the file todo.sh and tell me its first line."}]}],
            "tools": TOOL, "generationConfig": {"thinkingConfig": {"thinkingLevel": "minimal"}}}
    code, j = call(model, body)
    if code == 200:
        parts = []
        try:
            parts = j["candidates"][0]["content"]["parts"]
        except Exception:
            pass
        fc = [p["functionCall"]["name"] for p in parts if isinstance(p, dict) and "functionCall" in p]
        u = j.get("usageMetadata", {})
        note("%s | tool call with level=minimal | 200 | functionCalls=%s thoughts=%s" % (model, fc, u.get("thoughtsTokenCount", "-")))
    else:
        err = j.get("error", {}) if isinstance(j, dict) else {}
        note("%s | tool call with level=minimal | HTTP %s | %s" % (model, code, str(err.get("message", j))[:220]))
    time.sleep(PAUSE)
