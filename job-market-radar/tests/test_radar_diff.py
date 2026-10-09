import json
import sys
from datetime import date
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "skill" / "scripts"))
import radar_diff as rd  # noqa: E402

TODAY = date(2026, 10, 9)
CFG = rd.DEFAULT_CONFIG


# --- identity ---------------------------------------------------------------

@pytest.mark.parametrize("a, b", [
    ("Working Student Data Science (m/f/d)", "Working Student Data Science (m/w/d)"),
    ("Werkstudent KI (all genders)", "Werkstudent KI"),
    ("Werkstudentin Energiedaten (a*)", "werkstudentin energiedaten"),
    ("Working Student – Applied AI & Automation", "Working Student Applied AI Automation"),
])
def test_job_key_ignores_gender_tags_case_and_punctuation(a, b):
    assert rd.job_key("Firma GmbH", a) == rd.job_key("firma gmbh", b)


def test_job_key_keeps_different_roles_apart():
    assert rd.job_key("X", "Working Student Data Science") != rd.job_key("X", "Working Student Data Engineering")


def test_normalize_url_drops_tracking_fragment_and_trailing_slash():
    assert rd.normalize_url("HTTPS://Jobs.Example/job/1/?utm_source=x&id=7#apply") == "https://jobs.example/job/1?id=7"


# --- ratings ----------------------------------------------------------------

def test_stale_companies_missing_and_old_but_not_fresh():
    state = {"ratings": {"Fresh": {"fetched": "2026-10-01"}, "Old": {"fetched": "2026-09-01"}}}
    assert rd.stale_companies(state, ["Fresh", "Old", "Unknown", "Old"], TODAY, 28) == ["Old", "Unknown"]


def test_stale_boundary_is_inclusive_of_max_age():
    state = {"ratings": {"A": {"fetched": "2026-09-11"}}}  # exactly 28 days
    assert rd.stale_companies(state, ["A"], TODAY, 28) == []


@pytest.mark.parametrize("rating, expected", [
    (None, ["no employer rating found"]),
    ({"not_found": True}, ["no employer rating found"]),
    ({"score": 4.1, "recommend": 85, "reviews": 300, "ceo_approval": 70}, []),
    ({"score": 3.4, "recommend": 69, "reviews": 11, "ceo_approval": 49},
     ["rating 3.4 below 3.5", "recommendation 69 % below 70 %", "CEO approval 49 % below 50 %", "small sample (11 reviews)"]),
    ({"score": 3.5, "recommend": 70, "reviews": 20, "ceo_approval": 50}, []),  # thresholds are strict
    ({"score": 4.0, "recommend": None, "reviews": None, "ceo_approval": None}, []),  # unknown is not a warning
])
def test_rating_warnings(rating, expected):
    assert rd.rating_warnings(rating, CFG) == expected


# --- postings ---------------------------------------------------------------

def test_dedupe_prefers_career_page_over_job_board():
    jobs = [
        {"url": "https://board/1", "source": "indeed", "company": "A", "title": "WS Data (m/f/d)"},
        {"url": "https://a.example/1", "source": "career_page", "company": "A", "title": "WS Data (m/w/d)"},
    ]
    assert [j["source"] for j in rd.dedupe(jobs, CFG["source_priority"])] == ["career_page"]


def test_classify_matches_by_title_when_short_link_changed():
    prev = [{"id": "https://board/s/old", "company": "A", "title": "WS KI (m/w/d)", "first_seen": "2026-10-02"}]
    cur = [{"url": "https://board/s/new", "company": "A", "title": "WS KI (all genders)"}]
    res = rd.classify(prev, cur, TODAY)
    assert res["new"] == [] and res["gone"] == []
    assert res["still_open"][0]["first_seen"] == "2026-10-02"


def test_classify_new_and_gone():
    prev = [{"id": "https://x/1", "company": "A", "title": "Old role", "first_seen": "2026-09-27"}]
    cur = [{"url": "https://x/2", "company": "B", "title": "New role"}]
    res = rd.classify(prev, cur, TODAY)
    assert [j["company"] for j in res["new"]] == ["B"] and res["new"][0]["first_seen"] == "2026-10-09"
    assert [j["company"] for j in res["gone"]] == ["A"]


def test_sort_by_rating_puts_unrated_last_and_is_stable():
    jobs = [{"company": c} for c in ["none1", "low", "high", "none2", "high2"]]
    ratings = {"low": {"score": 3.1}, "high": {"score": 4.4}, "high2": {"score": 4.4}}
    assert [j["company"] for j in rd.sort_by_rating(jobs, ratings)] == ["high", "high2", "low", "none1", "none2"]


# --- end to end on the example data -----------------------------------------

def test_example_end_to_end(tmp_path, capsys):
    ex = ROOT / "examples"
    args = ["--state", str(ex / "state.json"), "--candidates", str(ex / "candidates.json"), "--today", "2026-10-09"]

    assert rd.main(["stale-ratings", *args]) == 0
    assert json.loads(capsys.readouterr().out) == ["Hafenblick Analytics GmbH"]

    out, report = tmp_path / "state.json", tmp_path / "report.md"
    # Without the missing rating the diff refuses to render a report with gaps.
    assert rd.main(["diff", *args, "--out", str(out), "--report", str(report)]) == 2
    assert not report.exists()

    assert rd.main(["diff", *args, "--ratings", str(ex / "ratings_new.json"),
                    "--out", str(out), "--report", str(report)]) == 0
    assert json.loads(capsys.readouterr().out.strip().splitlines()[-1]) == {"new": 1, "still_open": 2, "gone": 1}

    state = json.loads(out.read_text())
    ids = {j["company"]: j for j in state["jobs"]}
    assert ids["Nordlicht Energie GmbH"]["id"].startswith("https://jobs.nordlicht-energie.example/")
    assert ids["Kranich Pay GmbH"]["first_seen"] == "2026-10-02"
    assert ids["Hafenblick Analytics GmbH"]["first_seen"] == "2026-10-09"

    text = report.read_text()
    assert text == (ex / "report.md").read_text(), "examples/report.md is out of date; regenerate it"


def test_model_notes_become_warnings_after_rating_and_hours():
    job = {"fixed_hours": 20, "notes": ["mostly data entry in Excel"]}
    rating = {"score": 3.2, "reviews": 300}
    assert rd.job_warnings(job, rating, CFG) == ["rating 3.2 below 3.5", "asks for 20 h/week", "mostly data entry in Excel"]


def test_result_json_for_custom_renderer(tmp_path):
    ex = ROOT / "examples"
    out, result = tmp_path / "state.json", tmp_path / "result.json"
    assert rd.main(["diff", "--state", str(ex / "state.json"), "--candidates", str(ex / "candidates.json"),
                    "--ratings", str(ex / "ratings_new.json"), "--today", "2026-10-09",
                    "--out", str(out), "--result", str(result)]) == 0
    res = json.loads(result.read_text())
    assert res["counts"] == {"new": 1, "still_open": 2, "rejected": 2, "gone": 1}
    assert [j["company"] for j in res["still_open"]] == ["Nordlicht Energie GmbH", "Kranich Pay GmbH"]
    assert res["new"][0]["warnings"] == ["no employer rating found", "asks for 20 h/week"]
    assert res["still_open"][0]["rating"]["score"] == 4.2


def test_diff_requires_an_output_format(tmp_path):
    ex = ROOT / "examples"
    with pytest.raises(SystemExit):
        rd.main(["diff", "--state", str(ex / "state.json"), "--candidates", str(ex / "candidates.json"),
                 "--out", str(tmp_path / "s.json")])


def test_second_rating_source_is_checked_too():
    rating = {"score": 3.9, "recommend": 84, "reviews": 585,
              "second_source": {"name": "Indeed", "recommend": 49, "ceo_approval": 53}}
    assert rd.rating_warnings(rating, CFG) == ["Indeed: recommendation 49 % below 70 %"]


def test_merge_ratings_second_source_only_keeps_primary_and_its_date():
    cached = {"A": {"score": 4.0, "recommend": 78, "reviews": 507, "fetched": "2026-09-24"}}
    fetched = {"A": {"second_source": {"name": "Indeed", "recommend": 60, "fetched": "2026-10-11"}}}
    merged = rd.merge_ratings(cached, fetched)
    assert merged["A"]["score"] == 4.0 and merged["A"]["fetched"] == "2026-09-24"
    assert merged["A"]["second_source"]["recommend"] == 60
    assert cached["A"].get("second_source") is None  # cache input is not mutated


def test_merge_ratings_not_found_clears_old_values_and_refresh_clears_flag():
    cached = {"A": {"score": 3.1, "reviews": 9, "awards": ["x"], "fetched": "2026-08-01"},
              "B": {"not_found": True, "score": None, "fetched": "2026-08-01"}}
    fetched = {"A": {"not_found": True, "fetched": "2026-10-09"},
               "B": {"score": 4.2, "reviews": 40, "fetched": "2026-10-09"}}
    merged = rd.merge_ratings(cached, fetched)
    assert merged["A"]["score"] is None and merged["A"]["awards"] == [] and merged["A"]["fetched"] == "2026-10-09"
    assert "not_found" not in merged["B"] and merged["B"]["score"] == 4.2


def test_missing_ratings_file_means_nothing_fetched(tmp_path):
    ex = ROOT / "examples"
    state = json.loads((ex / "state.json").read_text())
    state["ratings"]["Hafenblick Analytics GmbH"] = {"not_found": True, "fetched": "2026-10-08"}
    (tmp_path / "state.json").write_text(json.dumps(state))
    assert rd.main(["diff", "--state", str(tmp_path / "state.json"), "--candidates", str(ex / "candidates.json"),
                    "--ratings", str(tmp_path / "does_not_exist.json"), "--today", "2026-10-09",
                    "--out", str(tmp_path / "out.json"), "--result", str(tmp_path / "r.json")]) == 0
