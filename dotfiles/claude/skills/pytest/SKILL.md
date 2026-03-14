# Pytest High-Quality Tests Skill

This skill provides standards and patterns for writing high-quality pytest tests. Apply these rules whenever writing, reviewing, or modifying tests.

## Core Principles

1. **GIVEN/WHEN/THEN structure** — every test body must have these three clearly delineated sections as comments
2. **One assertion per test** — each test verifies exactly one behavior or interaction
3. **Descriptive test names** — a developer must know precisely what broke just from reading the name
4. **Minimal fixture use** — only use fixtures for setup that is genuinely shared and non-trivial; inline simple setup
5. **Unit test isolation** — unit tests must not touch the filesystem, network, database, or any external process; patch everything external with `unittest.mock`
6. **Integration tests use containers** — integration tests run against real containerized dependencies (Docker), never mocks

---

## Test Naming Convention

Test names follow this pattern:

```
test_<unit>_<condition>_<expected_outcome>
```

Examples:
```python
test_calculate_discount_when_user_is_premium_returns_20_percent
test_send_email_when_smtp_is_unavailable_raises_connection_error
test_parse_date_when_format_is_invalid_returns_none
test_create_order_when_item_is_out_of_stock_raises_out_of_stock_error
test_get_user_when_id_does_not_exist_returns_none
```

Rules:
- Use `when` to introduce the condition/context
- Use a result verb at the end: `returns_`, `raises_`, `calls_`, `saves_`, `emits_`, `logs_`
- Avoid vague names like `test_works`, `test_happy_path`, `test_error_case`
- Class names (for grouping): `class TestCalculateDiscount:` (describes the unit under test)

---

## GIVEN/WHEN/THEN Structure

Every test body must use these comment markers:

```python
def test_create_user_when_email_already_exists_raises_duplicate_error(user_repository):
    # GIVEN
    existing_user = UserFactory(email="alice@example.com")
    user_repository.save(existing_user)

    # WHEN / THEN
    with pytest.raises(DuplicateEmailError):
        create_user(email="alice@example.com", repository=user_repository)
```

When asserting a return value:

```python
def test_calculate_tax_when_region_is_exempt_returns_zero():
    # GIVEN
    price = Decimal("100.00")
    region = "OR"

    # WHEN
    result = calculate_tax(price, region)

    # THEN
    assert result == Decimal("0.00")
```

Rules:
- Never collapse GIVEN/WHEN/THEN into a single block of undivided code
- `# WHEN / THEN` is acceptable only when the assertion must be inside the act (e.g., `pytest.raises`)
- Put only the call under test under `# WHEN`; all setup goes under `# GIVEN`

---

## One Assertion Per Test

Each test must assert exactly one outcome.

**Wrong — multiple assertions:**
```python
def test_user_creation():
    user = create_user("alice", "alice@example.com")
    assert user.name == "alice"          # assertion 1
    assert user.email == "alice@example.com"  # assertion 2
    assert user.is_active is True        # assertion 3
```

**Right — separate tests per behavior:**
```python
def test_create_user_when_given_name_sets_name_on_user():
    # GIVEN / WHEN
    user = create_user("alice", "alice@example.com")
    # THEN
    assert user.name == "alice"

def test_create_user_when_given_email_sets_email_on_user():
    # GIVEN / WHEN
    user = create_user("alice", "alice@example.com")
    # THEN
    assert user.email == "alice@example.com"

def test_create_user_sets_user_as_active_by_default():
    # GIVEN / WHEN
    user = create_user("alice", "alice@example.com")
    # THEN
    assert user.is_active is True
```

Exception: asserting multiple fields of a single value object (e.g., a dataclass representing one concept) is acceptable when they describe one indivisible outcome. Use your judgment — prefer splitting.

---

## Fixtures

**Use fixtures for:**
- Shared external resources (DB session, HTTP client, container)
- Complex object construction reused across many tests in the same file
- Teardown logic (cleanup after tests)

**Do NOT use fixtures for:**
- Simple values: just inline them
- Setup used in only one test: just inline it
- Masking what inputs a test actually uses (fixtures that hide test data make tests harder to understand)

**Good fixture (shared, non-trivial):**
```python
@pytest.fixture
def payment_gateway():
    gateway = FakePaymentGateway()
    gateway.configure(api_key="test-key", timeout=5)
    return gateway
```

**Bad fixture (too simple — inline instead):**
```python
@pytest.fixture
def user_email():
    return "alice@example.com"  # just write the string in the test
```

**Fixture scope:**
- Default to `scope="function"` (one instance per test) — always safe
- Use `scope="module"` or `scope="session"` only for expensive shared resources (containers, DB connections) with explicit justification

---

## Unit Tests — Complete Isolation

Unit tests must:
- Not touch the filesystem, network, database, message queues, or external processes
- Patch all external dependencies using `unittest.mock.patch`
- Be fast (< 10ms per test is a reasonable target)
- Never require environment variables or configuration files to be present

**Pattern — patching a dependency:**
```python
from unittest.mock import patch

def test_notify_user_when_order_ships_sends_email():
    # GIVEN
    order = Order(id="ord-1", user_email="bob@example.com", status="shipped")

    # WHEN
    with patch("myapp.notifications.send_email") as send_email:
        notify_user(order)

    # THEN
    send_email.assert_called_once_with(
        to="bob@example.com",
        subject="Your order ord-1 has shipped",
    )
```

**Pattern — patching a return value:**
```python
from unittest.mock import patch, Mock

def test_get_weather_when_api_returns_data_parses_temperature():
    # GIVEN
    mock_response = Mock(json=lambda: {"temp": 22.5}, status_code=200)

    # WHEN
    with patch("myapp.weather.requests.get", return_value=mock_response):
        result = get_current_temperature(city="Berlin")

    # THEN
    assert result == 22.5
```

---

## Integration Tests — Containerized Dependencies

Integration tests run against real services in Docker containers started via `docker compose` or a similar mechanism. A session-scoped pytest fixture is responsible for starting the container(s), waiting for readiness, and tearing them down.

**Fixture pattern:**
```python
import subprocess
import pytest
from myapp.db import create_engine, run_migrations

@pytest.fixture(scope="session")
def postgres():
    subprocess.run(["docker", "compose", "up", "-d", "postgres"], check=True)
    engine = create_engine("postgresql://user:pass@localhost:5432/testdb")
    run_migrations(engine)
    yield engine
    subprocess.run(["docker", "compose", "down", "-v"], check=True)

def test_save_user_when_email_is_unique_persists_to_database(postgres):
    # GIVEN
    repo = SqlUserRepository(postgres)
    user = User(id="u-1", email="carol@example.com")

    # WHEN
    repo.save(user)

    # THEN
    saved = repo.find_by_id("u-1")
    assert saved.email == "carol@example.com"
```

**Rules:**
- Container fixtures must be `scope="session"` or `scope="module"` — never recreate per test
- Integration tests must live in a separate directory (e.g., `tests/integration/`) and be marked:
  ```python
  pytestmark = pytest.mark.integration
  ```
- Run integration tests separately from unit tests:
  ```
  pytest tests/unit/
  pytest tests/integration/ -m integration
  ```
- Never use `unittest.mock` to replace real services in integration tests — if you're mocking the DB, it's a unit test

---

## File and Directory Layout

```
tests/
  unit/
    test_orders.py
    test_users.py
    test_notifications.py
  integration/
    test_order_repository.py
    test_email_service.py
  conftest.py        # only shared fixtures that apply to all test types
```

Each test file mirrors the module it tests:
- `myapp/orders/service.py` → `tests/unit/orders/test_service.py`

---

## Parametrize for Data Variants

Use `@pytest.mark.parametrize` when the same interaction must be verified across multiple input variants — not to combine unrelated assertions.

```python
@pytest.mark.parametrize("region,expected_rate", [
    ("CA", Decimal("0.0725")),
    ("TX", Decimal("0.0625")),
    ("OR", Decimal("0.00")),
])
def test_calculate_tax_rate_returns_correct_rate_for_region(region, expected_rate):
    # GIVEN / WHEN
    rate = calculate_tax_rate(region)

    # THEN
    assert rate == expected_rate
```

---

## Common Anti-Patterns to Avoid

| Anti-pattern | What to do instead |
|---|---|
| `test_it_works` | Name the specific behavior |
| Multiple `assert` statements for different behaviors | Split into separate tests |
| Fixture that just returns a hardcoded string | Inline the value |
| Mocking the DB in an "integration" test | Use a real container |
| `time.sleep()` in tests | Use a fake clock or mock |
| Testing implementation details (private methods) | Test public behavior only |
| Giant setup blocks (30+ lines before WHEN) | Extract a factory/builder; keep GIVEN focused |
| `assert response.status_code == 200` and `assert response.json()["id"] == ...` in one test | Split into two tests |

---

## Checklist Before Submitting Tests

- [ ] Every test has `# GIVEN`, `# WHEN`, `# THEN` comments
- [ ] Each test makes exactly one assertion (or one `pytest.raises` block)
- [ ] Test name clearly states: unit, condition, and expected outcome
- [ ] Unit tests use no real I/O (patched with `unittest.mock`)
- [ ] Integration tests use a container fixture, not mocks
- [ ] No fixture is used that isn't genuinely reused or non-trivial
- [ ] Parametrize is used for data variants, not to bundle unrelated assertions
