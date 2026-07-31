from payment_reminders.stages import DEFAULT_STAGES, Stage, select_stage


def test_stage_matches_ranges():
    s = Stage("x", days_from=1, days_to=7, subject="", template="")
    assert not s.matches(0)
    assert s.matches(1)
    assert s.matches(7)
    assert not s.matches(8)


def test_open_ended_stage():
    s = Stage("final", days_from=31, days_to=None, subject="", template="")
    assert s.matches(31)
    assert s.matches(999)
    assert not s.matches(30)


def test_select_stage_picks_most_severe():
    stages = [
        Stage("a", -3, -1, "", ""),
        Stage("b", 0, 0, "", ""),
        Stage("c", 1, 7, "", ""),
    ]
    assert select_stage(stages, -2).name == "a"
    assert select_stage(stages, 0).name == "b"
    assert select_stage(stages, 5).name == "c"
    assert select_stage(stages, 100) is None


def test_default_stages_cover_expected_days():
    assert select_stage(DEFAULT_STAGES, -2).name == "proximo_vencimiento"
    assert select_stage(DEFAULT_STAGES, 0).name == "vence_hoy"
    assert select_stage(DEFAULT_STAGES, 3).name == "vencido_reciente"
    assert select_stage(DEFAULT_STAGES, 20).name == "vencido"
    assert select_stage(DEFAULT_STAGES, 60).name == "aviso_final"
    # Fuera de rango preventivo (muy anticipado) no dispara nada.
    assert select_stage(DEFAULT_STAGES, -10) is None
