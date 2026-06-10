"""
Smoke tests - run against live environment post-deployment.
Called from CodeDeploy AfterInstall hook and buildspec.
"""
import sys
import time
import urllib.request
import urllib.error
import json

ALB_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3000"
MAX_RETRIES = 5
RETRY_DELAY = 10


def check_endpoint(path: str, expected_status: int = 200) -> dict:
    url = f"{ALB_URL}{path}"
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                body = json.loads(resp.read())
                assert resp.status == expected_status, f"Expected {expected_status}, got {resp.status}"
                print(f"  PASS [{resp.status}] {url}")
                return body
        except (urllib.error.URLError, AssertionError) as e:
            print(f"  Attempt {attempt}/{MAX_RETRIES} failed: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
    raise SystemExit(f"FAIL: {url} did not respond after {MAX_RETRIES} attempts")


def run_smoke_tests():
    print(f"\n=== Smoke Tests: {ALB_URL} ===\n")
    failures = []

    tests = [
        ("/health", 200),
        ("/api/items", 200),
    ]

    for path, expected_status in tests:
        try:
            check_endpoint(path, expected_status)
        except SystemExit as e:
            failures.append(str(e))

    if failures:
        print(f"\n{len(failures)} smoke test(s) FAILED:")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)

    print(f"\nAll smoke tests PASSED")


if __name__ == "__main__":
    run_smoke_tests()
