"""Root pytest configuration.

This repository currently ships no Python test suite, so a bare ``pytest``
run collects zero items and exits with code 5 (``NO_TESTS_COLLECTED``).
The CI workflow (.github/workflows/python-package.yml) runs ``pytest`` with
no arguments, and that exit code is reported as a build failure even though
nothing is actually broken.

Until real Python tests are added, treat "no tests collected" as success so
the pipeline stays green. Once actual tests exist and are collected, this
hook becomes a no-op (it only acts on the empty-collection exit code).
"""


def pytest_sessionfinish(session, exitstatus):
    # pytest.ExitCode.NO_TESTS_COLLECTED == 5
    if exitstatus == 5:
        session.exitstatus = 0
