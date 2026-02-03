local helpers = require("tests.helpers")
local kwargs = require("kwargs")

describe("generic type signatures", function()
  after_each(function()
    helpers.teardown()
  end)

  local function test_expand(description, input, expected, call_pattern)
    it(description, function()
      helpers.setup_python_file(input)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      local found = helpers.cursor_on_call(call_pattern or "result = ")
      assert.is_true(found, "Should find call pattern")

      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(expected, content)
    end)
  end

  describe("simple generics", function()
    test_expand(
      "handles List[T] parameter",
      [=[
from typing import List

def process_list(items: List[int], multiplier: int) -> List[int]:
    return [x * multiplier for x in items]

result = process_list([1, 2, 3], 2)
]=],
      [=[
from typing import List

def process_list(items: List[int], multiplier: int) -> List[int]:
    return [x * multiplier for x in items]

result = process_list(items=[1, 2, 3], multiplier=2)
]=]
    )

    test_expand(
      "handles Dict[K, V] parameter",
      [=[
from typing import Dict

def merge_dicts(base: Dict[str, int], updates: Dict[str, int]) -> Dict[str, int]:
    return {**base, **updates}

result = merge_dicts({"a": 1}, {"b": 2})
]=],
      [=[
from typing import Dict

def merge_dicts(base: Dict[str, int], updates: Dict[str, int]) -> Dict[str, int]:
    return {**base, **updates}

result = merge_dicts(base={"a": 1}, updates={"b": 2})
]=]
    )

    test_expand(
      "handles Optional[T] parameter",
      [=[
from typing import Optional

def find_item(items: list, key: str, default: Optional[str] = None) -> Optional[str]:
    return items.get(key, default)

result = find_item({}, "key", "default_value")
]=],
      [=[
from typing import Optional

def find_item(items: list, key: str, default: Optional[str] = None) -> Optional[str]:
    return items.get(key, default)

result = find_item(items={}, key="key", default="default_value")
]=]
    )

    test_expand(
      "handles Tuple[T, ...] parameter",
      [=[
from typing import Tuple

def sum_tuple(values: Tuple[int, ...], start: int = 0) -> int:
    return sum(values, start)

result = sum_tuple((1, 2, 3), 10)
]=],
      [=[
from typing import Tuple

def sum_tuple(values: Tuple[int, ...], start: int = 0) -> int:
    return sum(values, start)

result = sum_tuple(values=(1, 2, 3), start=10)
]=]
    )
  end)

  describe("generic classes", function()
    test_expand(
      "handles Generic[T] class method",
      [=[
from typing import Generic, TypeVar

T = TypeVar('T')

class Container(Generic[T]):
    def __init__(self, value: T, label: str):
        self.value = value
        self.label = label

result = Container(42, "answer")
]=],
      [=[
from typing import Generic, TypeVar

T = TypeVar('T')

class Container(Generic[T]):
    def __init__(self, value: T, label: str):
        self.value = value
        self.label = label

result = Container(value=42, label="answer")
]=]
    )

    test_expand(
      "handles multiple type parameters Generic[T, U]",
      [=[
from typing import Generic, TypeVar

T = TypeVar('T')
U = TypeVar('U')

class Pair(Generic[T, U]):
    def __init__(self, first: T, second: U):
        self.first = first
        self.second = second

result = Pair(1, "one")
]=],
      [=[
from typing import Generic, TypeVar

T = TypeVar('T')
U = TypeVar('U')

class Pair(Generic[T, U]):
    def __init__(self, first: T, second: U):
        self.first = first
        self.second = second

result = Pair(first=1, second="one")
]=]
    )
  end)

  describe("complex return types", function()
    test_expand(
      "handles Callable return type",
      [=[
from typing import Callable

def make_multiplier(factor: int) -> Callable[[int], int]:
    def multiplier(x: int) -> int:
        return x * factor
    return multiplier

result = make_multiplier(5)
]=],
      [=[
from typing import Callable

def make_multiplier(factor: int) -> Callable[[int], int]:
    def multiplier(x: int) -> int:
        return x * factor
    return multiplier

result = make_multiplier(factor=5)
]=]
    )

    test_expand(
      "handles nested generic return type",
      [=[
from typing import Dict, List

def group_by_length(words: List[str]) -> Dict[int, List[str]]:
    groups = {}
    for word in words:
        length = len(word)
        if length not in groups:
            groups[length] = []
        groups[length].append(word)
    return groups

output = group_by_length(["a", "bb", "ccc"])
]=],
      [=[
from typing import Dict, List

def group_by_length(words: List[str]) -> Dict[int, List[str]]:
    groups = {}
    for word in words:
        length = len(word)
        if length not in groups:
            groups[length] = []
        groups[length].append(word)
    return groups

output = group_by_length(words=["a", "bb", "ccc"])
]=],
      "output = "
    )
  end)

  describe("union types", function()
    test_expand(
      "handles Union types",
      [=[
from typing import Union

def stringify(value: Union[int, float, str], precision: int = 2) -> str:
    if isinstance(value, float):
        return f"{value:.{precision}f}"
    return str(value)

result = stringify(3.14159, 3)
]=],
      [=[
from typing import Union

def stringify(value: Union[int, float, str], precision: int = 2) -> str:
    if isinstance(value, float):
        return f"{value:.{precision}f}"
    return str(value)

result = stringify(value=3.14159, precision=3)
]=]
    )

    test_expand(
      "handles pipe union syntax (Python 3.10+)",
      [=[
def process(data: int | str | None, default: str = "N/A") -> str:
    if data is None:
        return default
    return str(data)

result = process(None, "unknown")
]=],
      [=[
def process(data: int | str | None, default: str = "N/A") -> str:
    if data is None:
        return default
    return str(data)

result = process(data=None, default="unknown")
]=]
    )
  end)

  describe("Protocol types", function()
    test_expand(
      "handles Protocol parameter",
      [=[
from typing import Protocol

class Sized(Protocol):
    def __len__(self) -> int: ...

def get_length(obj: Sized, fallback: int = 0) -> int:
    try:
        return len(obj)
    except:
        return fallback

result = get_length([1, 2, 3], -1)
]=],
      [=[
from typing import Protocol

class Sized(Protocol):
    def __len__(self) -> int: ...

def get_length(obj: Sized, fallback: int = 0) -> int:
    try:
        return len(obj)
    except:
        return fallback

result = get_length(obj=[1, 2, 3], fallback=-1)
]=]
    )
  end)

  describe("user-defined generic types (like Check[T, E])", function()
    test_expand(
      "handles custom generic result type",
      [=[
from typing import Generic, TypeVar
from abc import ABCMeta

_ResultType = TypeVar('_ResultType')
_ErrorType = TypeVar('_ErrorType')

class Check(Generic[_ResultType, _ErrorType], metaclass=ABCMeta):
    pass

class Result(Check[_ResultType, _ErrorType]):
    def __init__(self, value: _ResultType):
        self.value = value

def from_result(value: _ResultType, tag: str = "success") -> Check[_ResultType, Exception]:
    return Result(value)

result = from_result(42, "answer")
]=],
      [=[
from typing import Generic, TypeVar
from abc import ABCMeta

_ResultType = TypeVar('_ResultType')
_ErrorType = TypeVar('_ErrorType')

class Check(Generic[_ResultType, _ErrorType], metaclass=ABCMeta):
    pass

class Result(Check[_ResultType, _ErrorType]):
    def __init__(self, value: _ResultType):
        self.value = value

def from_result(value: _ResultType, tag: str = "success") -> Check[_ResultType, Exception]:
    return Result(value)

result = from_result(value=42, tag="answer")
]=]
    )

    test_expand(
      "handles complex Either-like type with multiple bounds",
      [=[
from typing import Generic, TypeVar, Union

T = TypeVar('T')
E = TypeVar('E', bound=Exception)

class Either(Generic[T, E]):
    pass

class Right(Either[T, E]):
    def __init__(self, value: T, metadata: dict = None):
        self.value = value
        self.metadata = metadata or {}

def make_right(value: T, label: str, metadata: dict = None) -> Either[T, Exception]:
    return Right(value, metadata)

result = make_right("success", "ok", {"source": "test"})
]=],
      [=[
from typing import Generic, TypeVar, Union

T = TypeVar('T')
E = TypeVar('E', bound=Exception)

class Either(Generic[T, E]):
    pass

class Right(Either[T, E]):
    def __init__(self, value: T, metadata: dict = None):
        self.value = value
        self.metadata = metadata or {}

def make_right(value: T, label: str, metadata: dict = None) -> Either[T, Exception]:
    return Right(value, metadata)

result = make_right(value="success", label="ok", metadata={"source": "test"})
]=]
    )
  end)

  describe("type aliases", function()
    test_expand(
      "handles TypeAlias",
      [=[
from typing import TypeAlias, List, Tuple

Coordinate: TypeAlias = Tuple[float, float]
Path: TypeAlias = List[Coordinate]

def create_path(start: Coordinate, end: Coordinate, waypoints: Path = None) -> Path:
    path = [start]
    if waypoints:
        path.extend(waypoints)
    path.append(end)
    return path

result = create_path((0.0, 0.0), (10.0, 10.0), [(5.0, 5.0)])
]=],
      [=[
from typing import TypeAlias, List, Tuple

Coordinate: TypeAlias = Tuple[float, float]
Path: TypeAlias = List[Coordinate]

def create_path(start: Coordinate, end: Coordinate, waypoints: Path = None) -> Path:
    path = [start]
    if waypoints:
        path.extend(waypoints)
    path.append(end)
    return path

result = create_path(start=(0.0, 0.0), end=(10.0, 10.0), waypoints=[(5.0, 5.0)])
]=]
    )
  end)

  describe("ParamSpec (Python 3.10+)", function()
    test_expand(
      "handles ParamSpec in decorator",
      [=[
from typing import Callable, TypeVar, ParamSpec

P = ParamSpec('P')
R = TypeVar('R')

def logged(func: Callable[P, R], prefix: str = "CALL") -> Callable[P, R]:
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        print(f"{prefix}: {func.__name__}")
        return func(*args, **kwargs)
    return wrapper

def my_func(x: int) -> int:
    return x * 2

result = logged(my_func, "DEBUG")
]=],
      [=[
from typing import Callable, TypeVar, ParamSpec

P = ParamSpec('P')
R = TypeVar('R')

def logged(func: Callable[P, R], prefix: str = "CALL") -> Callable[P, R]:
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        print(f"{prefix}: {func.__name__}")
        return func(*args, **kwargs)
    return wrapper

def my_func(x: int) -> int:
    return x * 2

result = logged(func=my_func, prefix="DEBUG")
]=]
    )
  end)
end)
