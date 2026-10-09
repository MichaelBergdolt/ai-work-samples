#!/usr/bin/env python3
"""Deterministic half of the job-market radar.

The model searches, judges whether a posting fits and writes one sentence on why.
Everything that is a comparison lives here, so it is testable and cannot be
"forgotten" by a model on a long run:

  * which employers need a fresh rating (cache older than N days, or none),
  * deduplication of the same posting found through several sources,
  * matching this week's postings against last week's (new / still open / gone),
  * warning flags from rating thresholds,
  * sorting and the Markdown report.

Standard library only. Usage:

  radar_diff.py stale-ratings --state STATE --candidates CANDIDATES [--config CONFIG] [--today YYYY-MM-DD]
  radar_diff.py diff --state STATE --candidates CANDIDATES [--ratings NEW_RATINGS]
                     [--config CONFIG] [--today YYYY-MM-DD] --out NEW_STATE
                     [--report REPORT_MD] [--result RESULT_JSON]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

DEFAULT_CONFIG = {
    "rating_max_age_days": 28,
    "warn_score_below": 3.5,
    "warn_recommend_below": 70,
    "warn_ceo_below": 50,
    "small_sample_below": 20,
    # Lower number wins when the same posting comes from several sources.
    "source_priority": {"career_page": 0, "ba": 1, "indeed": 2, "web": 3},
}

TRACKING_PARAMS = re.compile(r"^(utm_|gclid$|fbclid$|ref$|source$|trk)", re.I)
GENDER_TAG = re.compile(r"\((?:[mwfdxa]\s*[/|,]?\s*)+\*?\)|\(all genders\)|\(a\*\)", re.I)


# --------------------------------------------------------------------------- keys

def normalize_url(url: str) -> str:
    """Lower-case host, drop fragment, tracking parameters and trailing slash."""
    parts = urlsplit(url.strip())
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
             if not TRACKING_PARAMS.match(k)]
    path = parts.path.rstrip("/") or "/"
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, urlencode(query), ""))


def _fold(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", " ", text.casefold()).strip()


def job_key(company: str, title: str) -> str:
    """Identity of a posting independent of the link it was found under.

    Job boards hand out a different short link for the same posting on every call,
    so the URL alone cannot tell "new" from "seen last week".
    """
    title = GENDER_TAG.sub(" ", title)
    return f"{_fold(company)}|{_fold(title)}"


# ----------------------------------------------------------------------- ratings

def _age_days(fetched: str | None, today: date) -> int | None:
    if not fetched:
        return None
    return (today - date.fromisoformat(fetched)).days


def stale_companies(state: dict, companies: list[str], today: date, max_age: int) -> list[str]:
    """Employers whose rating is missing or older than max_age days, in input order."""
    ratings = state.get("ratings", {})
    out: list[str] = []
    for company in companies:
        age = _age_days(ratings.get(company, {}).get("fetched"), today)
        if (age is None or age > max_age) and company not in out:
            out.append(company)
    return out


def rating_warnings(rating: dict | None, cfg: dict) -> list[str]:
    if not rating or rating.get("not_found"):
        return ["no employer rating found"]
    warns = []
    score, rec, ceo, n = (rating.get(k) for k in ("score", "recommend", "ceo_approval", "reviews"))
    if score is not None and score < cfg["warn_score_below"]:
        warns.append(f"rating {score} below {cfg['warn_score_below']}")
    if rec is not None and rec < cfg["warn_recommend_below"]:
        warns.append(f"recommendation {rec} % below {cfg['warn_recommend_below']} %")
    if ceo is not None and ceo < cfg["warn_ceo_below"]:
        warns.append(f"CEO approval {ceo} % below {cfg['warn_ceo_below']} %")
    if n is not None and n < cfg["small_sample_below"]:
        warns.append(f"small sample ({n} reviews)")
    # Optional second platform: recommendation and CEO approval often disagree with the first.
    second = rating.get("second_source") or {}
    label = second.get("name", "second source")
    if second.get("recommend") is not None and second["recommend"] < cfg["warn_recommend_below"]:
        warns.append(f"{label}: recommendation {second['recommend']} % below {cfg['warn_recommend_below']} %")
    if second.get("ceo_approval") is not None and second["ceo_approval"] < cfg["warn_ceo_below"]:
        warns.append(f"{label}: CEO approval {second['ceo_approval']} % below {cfg['warn_ceo_below']} %")
    return warns


RATING_FIELDS = ("score", "recommend", "reviews", "ceo_approval", "awards")


def merge_ratings(cached: dict, fetched: dict) -> dict:
    """Merge this run's ratings into the cache, field by field per employer.

    A run may refresh only the second platform; that must not erase or re-date the cached
    primary rating. A fresh "not found" clears the old primary values instead of keeping them.
    """
    merged = {k: dict(v) for k, v in cached.items()}
    for company, new in fetched.items():
        old = merged.get(company, {})
        rec = {**old, **new}
        if new.get("not_found"):
            for f in RATING_FIELDS:
                rec[f] = [] if f == "awards" else None
        elif "score" in new:
            rec.pop("not_found", None)
        merged[company] = rec
    return merged


# --------------------------------------------------------------------- postings

def dedupe(jobs: list[dict], priority: dict[str, int]) -> list[dict]:
    """One entry per job_key, keeping the source with the best priority."""
    best: dict[str, dict] = {}
    order: list[str] = []
    for job in jobs:
        key = job_key(job["company"], job["title"])
        rank = priority.get(job.get("source", "web"), 99)
        if key not in best:
            order.append(key)
            best[key] = job
        elif rank < priority.get(best[key].get("source", "web"), 99):
            best[key] = job
    return [best[k] for k in order]


def classify(previous: list[dict], current: list[dict], today: date) -> dict:
    """Split into new / still_open / gone. A previous posting matches by URL or by job_key."""
    prev_by_url = {normalize_url(p["id"]): p for p in previous}
    prev_by_key = {job_key(p["company"], p["title"]): p for p in previous}
    matched: set[str] = set()
    new, still_open = [], []
    for job in current:
        hit = prev_by_url.get(normalize_url(job["url"])) or prev_by_key.get(job_key(job["company"], job["title"]))
        if hit:
            matched.add(hit["id"])
            still_open.append({**job, "first_seen": hit["first_seen"]})
        else:
            new.append({**job, "first_seen": today.isoformat()})
    gone = [p for p in previous if p["id"] not in matched]
    return {"new": new, "still_open": still_open, "gone": gone}


def sort_by_rating(jobs: list[dict], ratings: dict) -> list[dict]:
    """Highest employer rating first; unrated employers last; stable otherwise."""
    def score(job):
        s = ratings.get(job["company"], {}).get("score")
        return (s is None, -(s or 0))
    return sorted(jobs, key=score)


def job_warnings(job: dict, rating: dict | None, cfg: dict) -> list[str]:
    """Rating warnings, then the hours flag, then the model's own notes about the posting."""
    warns = rating_warnings(rating, cfg)
    if job.get("fixed_hours"):
        warns.append(f"asks for {job['fixed_hours']} h/week")
    return warns + list(job.get("notes") or [])


def build_result(result: dict, ratings: dict, rejected: list[dict], cfg: dict, today: date) -> dict:
    """Everything a renderer needs, already sorted and with warnings attached."""
    def enrich(job):
        r = ratings.get(job["company"])
        return {**job, "rating": r, "warnings": job_warnings(job, r, cfg)}
    return {
        "date": today.isoformat(),
        "counts": {"new": len(result["new"]), "still_open": len(result["still_open"]),
                   "rejected": len(rejected), "gone": len(result["gone"])},
        "new": [enrich(j) for j in result["new"]],
        "still_open": [enrich(j) for j in result["still_open"]],
        "rejected": rejected,
        "gone": result["gone"],
    }


# ----------------------------------------------------------------------- report

def _rating_line(rating: dict | None) -> str:
    if not rating or rating.get("not_found"):
        return "rating: not found"
    bits = [f"rating {rating['score']}" if rating.get("score") is not None else "rating: not found"]
    if rating.get("recommend") is not None:
        bits.append(f"{rating['recommend']} % recommend")
    if rating.get("reviews") is not None:
        bits.append(f"{rating['reviews']} reviews")
    bits.append(f"fetched {rating.get('fetched', 'n/a')}")
    return " · ".join(bits)


def render_report(result: dict, ratings: dict, rejected: list[dict], cfg: dict, today: date) -> str:
    lines = [f"# Job radar, {today.isoformat()}", "",
             f"**{len(result['new'])} new · {len(result['still_open'])} still open · "
             f"{len(rejected)} filtered out · {len(result['gone'])} gone**", ""]
    for heading, jobs in (("New this week", result["new"]), ("Still open", result["still_open"])):
        lines += [f"## {heading}", ""]
        if not jobs:
            lines += ["_None._", ""]
        for job in jobs:
            r = ratings.get(job["company"])
            hours = f" · fixed {job['fixed_hours']} h/week" if job.get("fixed_hours") else ""
            lines.append(f"### [{job['title']}]({job['url']})")
            lines.append(f"{job['company']} · posted {job.get('posted') or 'not found'} · "
                         f"source: {job['source']}{hours}  ")
            lines.append(_rating_line(r) + "  ")
            for w in job_warnings(job, r, cfg):
                lines.append(f"⚠ {w}  ")
            lines += [job.get("why", ""), ""]
    lines += ["## Filtered out", ""]
    lines += [f"- {j['company']}: {j['title']} ({j['reason']})" for j in rejected] or ["_None._"]
    lines += ["", "## Gone since last run", ""]
    lines += [f"- {j['company']}: {j['title']}" for j in result["gone"]] or ["_None._"]
    return "\n".join(lines) + "\n"


# -------------------------------------------------------------------------- CLI

def _load(path: str | None, default, required: bool = True):
    if not path:
        return default
    p = Path(path)
    if not p.exists() and not required:
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["stale-ratings", "diff"])
    ap.add_argument("--state", required=True)
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--ratings", help="ratings fetched in this run, same shape as state['ratings']")
    ap.add_argument("--config")
    ap.add_argument("--today", default=date.today().isoformat())
    ap.add_argument("--out")
    ap.add_argument("--report", help="Markdown report")
    ap.add_argument("--result", help="JSON result for a custom renderer (e.g. an HTML page)")
    a = ap.parse_args(argv)

    cfg = {**DEFAULT_CONFIG, **_load(a.config, {})}
    today = date.fromisoformat(a.today)
    state = _load(a.state, {})
    cand = _load(a.candidates, {})
    accepted = dedupe(cand.get("accepted", []), cfg["source_priority"])

    if a.command == "stale-ratings":
        companies = [j["company"] for j in accepted]
        print(json.dumps(stale_companies(state, companies, today, cfg["rating_max_age_days"]), ensure_ascii=False))
        return 0

    if not a.out or not (a.report or a.result):
        ap.error("diff needs --out and at least one of --report / --result")
    # A run that fetched nothing new may not have written the file at all.
    ratings = merge_ratings(state.get("ratings", {}), _load(a.ratings, {}, required=False))
    missing = stale_companies({"ratings": ratings}, [j["company"] for j in accepted], today, cfg["rating_max_age_days"])
    if missing:
        # Fail loudly instead of rendering a report with silent gaps.
        print(f"ratings missing or stale for: {', '.join(missing)}. Fetch them, or record "
              f'{{"not_found": true, "fetched": "{today}"}}.', file=sys.stderr)
        return 2

    result = classify(state.get("jobs", []), accepted, today)
    result["new"] = sort_by_rating(result["new"], ratings)
    result["still_open"] = sort_by_rating(result["still_open"], ratings)

    new_state = {
        **state,
        "ratings": ratings,
        "jobs": [{"id": j["url"], "title": j["title"], "company": j["company"], "first_seen": j["first_seen"]}
                 for j in result["new"] + result["still_open"]],
    }
    Path(a.out).write_text(json.dumps(new_state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    rejected = cand.get("rejected", [])
    if a.report:
        Path(a.report).write_text(render_report(result, ratings, rejected, cfg, today), encoding="utf-8")
    if a.result:
        Path(a.result).write_text(json.dumps(build_result(result, ratings, rejected, cfg, today),
                                             ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: len(v) for k, v in result.items()}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
