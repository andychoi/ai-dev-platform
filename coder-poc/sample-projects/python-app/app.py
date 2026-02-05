"""
Sample Python Application for Coder WebIDE PoC
This application demonstrates CI/CD pipeline testing with Drone CI
"""

from typing import Optional


def calculate_sum(numbers: list[int]) -> int:
    """Calculate the sum of a list of numbers."""
    return sum(numbers)


def calculate_average(numbers: list[int]) -> Optional[float]:
    """Calculate the average of a list of numbers."""
    if not numbers:
        return None
    return sum(numbers) / len(numbers)


def find_max(numbers: list[int]) -> Optional[int]:
    """Find the maximum value in a list of numbers."""
    if not numbers:
        return None
    return max(numbers)


def find_min(numbers: list[int]) -> Optional[int]:
    """Find the minimum value in a list of numbers."""
    if not numbers:
        return None
    return min(numbers)


def is_prime(n: int) -> bool:
    """Check if a number is prime."""
    if n < 2:
        return False
    for i in range(2, int(n**0.5) + 1):
        if n % i == 0:
            return False
    return True


def fibonacci(n: int) -> list[int]:
    """Generate first n Fibonacci numbers."""
    if n <= 0:
        return []
    if n == 1:
        return [0]

    fib = [0, 1]
    for _ in range(2, n):
        fib.append(fib[-1] + fib[-2])
    return fib


class Calculator:
    """Simple calculator class for demonstration."""

    def __init__(self, initial_value: float = 0):
        self.value = initial_value

    def add(self, x: float) -> "Calculator":
        self.value += x
        return self

    def subtract(self, x: float) -> "Calculator":
        self.value -= x
        return self

    def multiply(self, x: float) -> "Calculator":
        self.value *= x
        return self

    def divide(self, x: float) -> "Calculator":
        if x == 0:
            raise ValueError("Cannot divide by zero")
        self.value /= x
        return self

    def reset(self) -> "Calculator":
        self.value = 0
        return self

    def get_value(self) -> float:
        return self.value


def main():
    """Main entry point for the application."""
    print("Sample Python Application")
    print("=" * 40)

    # Demo calculations
    numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    print(f"Numbers: {numbers}")
    print(f"Sum: {calculate_sum(numbers)}")
    print(f"Average: {calculate_average(numbers)}")
    print(f"Max: {find_max(numbers)}")
    print(f"Min: {find_min(numbers)}")

    print("\nPrime numbers up to 20:")
    primes = [n for n in range(2, 21) if is_prime(n)]
    print(primes)

    print("\nFirst 10 Fibonacci numbers:")
    print(fibonacci(10))

    print("\nCalculator demo:")
    calc = Calculator(10)
    result = calc.add(5).multiply(2).subtract(10).get_value()
    print(f"(10 + 5) * 2 - 10 = {result}")


if __name__ == "__main__":
    main()
