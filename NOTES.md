# Notes on Keyword Arguments in Various Languages

## Language Support for Keyword Arguments

1. **JavaScript/TypeScript**: 
   - Supports default parameters and object destructuring to simulate keyword arguments.
   - Does not natively support mixing keyword and non-keyword arguments.

2. **Ruby**: 
   - Supports keyword arguments.
   - Can mix them with positional arguments.

3. **Swift**: 
   - Supports mixing keyword and positional arguments.

4. **Kotlin**: 
   - Supports named arguments.
   - Can mix them with positional arguments.

5. **Julia**: 
   - Supports keyword arguments.
   - Can mix them with positional arguments.

6. **R**: 
   - Supports mixing keyword and positional arguments.

7. **C#**: 
   - Supports named arguments.
   - Can mix them with positional arguments.

8. **PHP**: 
   - Supports named arguments (from PHP 8.0).
   - Can mix them with positional arguments.

## Lua and Keyword Arguments

In Lua, there are no native keyword arguments. To simulate keyword arguments:
- Refactor the function to take a table as input.
- Update every reference that calls the function to pass a table with the arguments.
- This is more complicated than just adding keyword arguments to the function signature.

## Additional Functionalities

### Renaming Variables
- Could be used to rename variables that go into a function call as keyword arguments into the name of the variable in the function definition.
- This could make the variable names more consistent in certain places.
- Or move expressions defined in keyword arguments to a variable definition above the function call.

#### Example
```python
foo(a=1, b=2 + 3 * 4)
```
would become
```python
b = 2 + 3 * 4
foo(a=1, b=b)
```

## Proposed Features

1. **Keyword Argument Toggle**
   - Allow toggling between positional and keyword arguments in a function call.
   - Example: Toggle `foo(a=1, b=2)` back to `foo(1, 2)`.

2. **Auto-Insert Default Values**
   - When calling a function, the plugin could suggest inserting default values for omitted keyword arguments.
   - Example:
     ```python
     def foo(a, b=42, c="hello"):
         return a + b
     ```
     Input: `foo(1)`
     Output: `foo(a=1, b=42, c="hello")`

3. **Dynamic Argument Rearranging**
   - Provide a shortcut to reorder function arguments based on their order in the function definition.
   - Example:
     ```python
     foo(b=2, a=1)
     ```
     Shortcut: Rearranges to `foo(a=1, b=2)`.

## Interesting Idea

### Transform Kwargs to Dataclass Parameters
- Refactor keyword arguments into a dataclass and update the function signature.

### Example Method
Suppose we have a method called `func`:
```python
def func(self, param1, param2, /, param3, *, param4, param5):
    print(param1, param2, param3, param4, param5)
```
It must be called with:
```python
obj.func(10, 20, 30, param4=50, param5=60)
```
OR
```python
obj.func(10, 20, param3=30, param4=50, param5=60)
```

Options
- Recursive option -> go up all function calls vs only the local one
- Option to insert default kwargs
