"""Server-side quiz grading: attempts are re-graded against the stored quiz.

Clients send their own ``score`` and ``passed`` values, which are ignored for
integrity: the server reloads the quiz definition from disk and grades the
submitted answers itself, so students cannot self-report a passing score.

Both quiz layouts (course quizzes under ``uploads/courses/{course}/`` and
standalone quizzes in ``uploads/{id}.quiz``) use the same ``{"quiz": {...}}``
wrapper, so a single loader serves both.
"""
import json
import os


def load_quiz_file(path: str):
    """Read a quiz JSON file and return the inner quiz dict (or None).

    Accepts both the ``{"quiz": {...}}`` wrapper used by current quizzes and
    the legacy flat format.  Returns None when the file is missing or
    unparseable.
    """
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None
    if isinstance(data, dict) and isinstance(data.get("quiz"), dict):
        return data["quiz"]
    return data


def normalize_threshold(raw) -> float:
    """Normalize a pass threshold to a 0.0-1.0 fraction.

    ``pass_threshold`` is stored as a percent (60) by teacher endpoints and
    as a fraction (0.6) by some clients; both must grade identically.
    """
    if raw is None:
        return 0.0
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return 0.0
    return value / 100.0 if value > 1.0 else value


def grade_quiz(quiz: dict, answers_json: str):
    """Re-grade a submitted attempt against the quiz definition.

    Args:
        quiz: Inner quiz dict with ``questions`` and ``pass_threshold``.
        answers_json: Raw answers payload from the client.

    Returns:
        Tuple of (score_fraction, passed, threshold_fraction).  The client's
        own score/passed are never consulted.
    """
    score, passed, threshold, _ = grade_quiz_detailed(quiz, answers_json)
    return score, passed, threshold


def grade_quiz_detailed(quiz: dict, answers_json: str):
    """Grade an attempt and return per-question results for post-submit review.

    Quiz-serving routes strip the answer key, so the client cannot grade
    locally. This returns everything the client needs to render the review
    screen AFTER the attempt is stored: revealing the key at that point is
    safe because the score was already computed server-side.

    Args:
        quiz: Inner quiz dict with ``questions`` and ``pass_threshold``.
        answers_json: Raw answers payload from the client.

    Returns:
        Tuple of (score_fraction, passed, threshold_fraction, results) where
        results is a list of ``{"question_id", "correct", "correct_answers",
        "explanation"}`` dicts in quiz-definition order.
    """
    questions = quiz.get("questions") or []
    answers = _parse_answers(answers_json)
    results = []
    correct = 0
    for i, q in enumerate(questions):
        is_correct = _is_correct(q, answers, i)
        if is_correct:
            correct += 1
        results.append({
            "question_id": str(q.get("id", "")),
            "correct": is_correct,
            "correct_answers": _correct_answers(q),
            "explanation": str(q.get("explanation") or ""),
        })
    total = len(questions)
    score = correct / total if total else 0.0
    threshold = normalize_threshold(quiz.get("pass_threshold"))
    return score, score >= threshold, threshold, results


def find_missing_answer_keys(questions) -> list:
    """Return indexes of questions with no usable answer key.

    A question is gradeable when ``correct_answer`` is present and non-empty
    (any type: int index, numeric string, or literal text) or
    ``correct_answers`` is a non-empty list. Pure helper (no HTTP imports):
    routers turn a non-empty result into a 400 response.

    Args:
        questions: Quiz question dicts as submitted for creation.

    Returns:
        List of question indexes missing an answer key (empty = all good).
    """
    missing = []
    for i, q in enumerate(questions or []):
        if not isinstance(q, dict):
            missing.append(i)
            continue
        single = q.get("correct_answer")
        multi = q.get("correct_answers")
        has_single = single is not None and (not isinstance(single, str) or single.strip() != "")
        has_multi = isinstance(multi, list) and len(multi) > 0
        if not (has_single or has_multi):
            missing.append(i)
    return missing


def _parse_answers(raw: str) -> dict:
    """Parse answers_json into {question_id_or_index: entry}.

    Accepts both the current format (``{"answers": {"0": {"answer": ...,
    "question_id": ...}}}``: keyed by display index with the id inside,
    which survives client-side question shuffling) and the legacy list
    format (``[{"id": "q1", "selected": ...}]``).
    """
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return {}
    if isinstance(data, dict) and "answers" in data:
        data = data["answers"]
    indexed = {}
    by_id = {}
    if isinstance(data, dict):
        for key, entry in data.items():
            if not isinstance(entry, dict):
                continue
            indexed[str(key)] = entry
            qid = entry.get("question_id") or entry.get("id")
            if qid:
                by_id[str(qid)] = entry
    elif isinstance(data, list):
        for i, entry in enumerate(data):
            if isinstance(entry, dict):
                indexed[entry.get("id") or str(i)] = entry
    merged = dict(indexed)
    merged.update(by_id)
    return merged


def _correct_answers(q: dict) -> list:
    """Resolve a question's correct answer(s) to option text.

    ``correct_answer``/``correct_answers`` are stored as option indexes (int)
    or literal strings; both resolve to the option text the client submits.
    Numeric strings are ambiguous (the web form stringifies indexes, but an
    option's text can itself be numeric): a value that exactly matches an
    option is treated as literal text, otherwise a valid index resolves
    positionally. This keeps ``correct_answer: "1"`` with options
    ``["1", "2"]`` literal while ``correct_answer: "0"`` with options
    ``["Correct", "Wrong"]`` resolves to ``"Correct"``.
    """
    options = q.get("options") or []
    raw = q.get("correct_answers")
    if raw is None:
        raw = q.get("correct_answer")
    if raw is None:
        return []
    if isinstance(raw, list):
        return [_resolve_answer(options, item) for item in raw]
    return [_resolve_answer(options, raw)] if _resolve_answer(options, raw) is not None else []


def _resolve_answer(options: list, raw):
    """Resolve one answer-key value to option text, or None when empty."""
    if isinstance(raw, int):
        if 0 <= raw < len(options):
            return options[raw]
        return None
    if isinstance(raw, str):
        if raw in options:
            return raw
        try:
            idx = int(raw.strip())
        except (ValueError, TypeError):
            return str(raw)
        if 0 <= idx < len(options):
            return options[idx]
        return str(raw)
    if raw is None:
        return None
    return str(raw)


def _is_correct(q: dict, answers: dict, index: int) -> bool:
    """Grade one question: True when the student's answer matches the key.

    Answers are compared after normalization (trimmed, lowercased, internal
    whitespace collapsed) and must be exact matches; substring matching
    would let overlapping option texts (e.g. "Photosynthesis" vs
    "Photosynthesis in plants") both grade correct.  Multi-select uses
    exact set equality.
    """
    entry = answers.get(str(q.get("id", ""))) or answers.get(str(index))
    if not entry:
        return False
    correct = _correct_answers(q)
    if not correct:
        return False
    if str(q.get("type", "")).lower() in ("multi_select", "multi"):
        selected = {str(s) for s in (entry.get("multi_answers") or [])}
        return selected == {str(c) for c in correct}
    answer = entry.get("answer")
    if answer is None:
        answer = entry.get("selected")
    if answer is None:
        return False
    return _normalize_answer(answer) == _normalize_answer(correct[0])


def _normalize_answer(raw) -> str:
    """Normalize an answer for comparison: trimmed, lowercased, whitespace-collapsed."""
    return " ".join(str(raw).strip().lower().split())


if __name__ == "__main__":
    assert _normalize_answer("  Photosynthesis \n in Plants ") == "photosynthesis in plants"
    assert _is_correct({"id": "q1", "type": "mcq", "correct_answer": "Photosynthesis",
                        "options": ["Photosynthesis", "Photosynthesis in plants"]},
                       {"q1": {"answer": "Photosynthesis in plants"}}, 0) is False
    assert _is_correct({"id": "q1", "type": "mcq", "correct_answer": "1", "options": ["1", "2"]},
                       {"q1": {"answer": "1"}}, 0) is True
    assert _is_correct({"id": "q2", "type": "multi_select", "correct_answers": ["a", "b"]},
                       {"q2": {"multi_answers": ["b", "a"]}}, 1) is True
    # Stringified indexes from the web form resolve positionally unless the
    # literal text matches an option (production hub quiz shape).
    assert _is_correct({"id": "q3", "type": "mcq", "correct_answer": "0",
                        "options": ["Correct", "Wrong"]},
                       {"q3": {"answer": "Correct"}}, 2) is True
    assert _is_correct({"id": "q3", "type": "mcq", "correct_answer": "0",
                        "options": ["Correct", "Wrong"]},
                       {"q3": {"answer": "Wrong"}}, 2) is False
    assert find_missing_answer_keys([
        {"id": "q1", "correct_answer": 0},
        {"id": "q2", "correct_answers": ["a", "b"]},
        {"id": "q3", "correct_answer": "  "},
        {"id": "q4"},
    ]) == [2, 3]
    print("quiz_grading self-check OK")  # noqa: T201
