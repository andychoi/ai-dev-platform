"""
Tests for Sample Python Application
Run with: pytest test_app.py -v
"""

import pytest
from app import (
    calculate_sum,
    calculate_average,
    find_max,
    find_min,
    is_prime,
    fibonacci,
    Calculator,
)


class TestCalculations:
    """Test basic calculation functions."""

    def test_calculate_sum_positive(self):
        assert calculate_sum([1, 2, 3, 4, 5]) == 15

    def test_calculate_sum_empty(self):
        assert calculate_sum([]) == 0

    def test_calculate_sum_negative(self):
        assert calculate_sum([-1, -2, -3]) == -6

    def test_calculate_average_positive(self):
        assert calculate_average([1, 2, 3, 4, 5]) == 3.0

    def test_calculate_average_empty(self):
        assert calculate_average([]) is None

    def test_calculate_average_single(self):
        assert calculate_average([10]) == 10.0

    def test_find_max_positive(self):
        assert find_max([1, 5, 3, 9, 2]) == 9

    def test_find_max_empty(self):
        assert find_max([]) is None

    def test_find_max_negative(self):
        assert find_max([-5, -2, -10]) == -2

    def test_find_min_positive(self):
        assert find_min([1, 5, 3, 9, 2]) == 1

    def test_find_min_empty(self):
        assert find_min([]) is None


class TestPrime:
    """Test prime number function."""

    def test_is_prime_true(self):
        primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
        for p in primes:
            assert is_prime(p) is True, f"{p} should be prime"

    def test_is_prime_false(self):
        non_primes = [0, 1, 4, 6, 8, 9, 10, 12, 15]
        for n in non_primes:
            assert is_prime(n) is False, f"{n} should not be prime"

    def test_is_prime_negative(self):
        assert is_prime(-5) is False


class TestFibonacci:
    """Test Fibonacci function."""

    def test_fibonacci_zero(self):
        assert fibonacci(0) == []

    def test_fibonacci_one(self):
        assert fibonacci(1) == [0]

    def test_fibonacci_ten(self):
        expected = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
        assert fibonacci(10) == expected

    def test_fibonacci_negative(self):
        assert fibonacci(-5) == []


class TestCalculator:
    """Test Calculator class."""

    def test_initial_value(self):
        calc = Calculator(10)
        assert calc.get_value() == 10

    def test_default_value(self):
        calc = Calculator()
        assert calc.get_value() == 0

    def test_add(self):
        calc = Calculator(10)
        calc.add(5)
        assert calc.get_value() == 15

    def test_subtract(self):
        calc = Calculator(10)
        calc.subtract(3)
        assert calc.get_value() == 7

    def test_multiply(self):
        calc = Calculator(10)
        calc.multiply(3)
        assert calc.get_value() == 30

    def test_divide(self):
        calc = Calculator(10)
        calc.divide(2)
        assert calc.get_value() == 5

    def test_divide_by_zero(self):
        calc = Calculator(10)
        with pytest.raises(ValueError, match="Cannot divide by zero"):
            calc.divide(0)

    def test_chaining(self):
        calc = Calculator(10)
        result = calc.add(5).multiply(2).subtract(10).get_value()
        assert result == 20

    def test_reset(self):
        calc = Calculator(100)
        calc.reset()
        assert calc.get_value() == 0


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_large_numbers(self):
        large_list = list(range(1, 10001))
        assert calculate_sum(large_list) == 50005000

    def test_floating_point_average(self):
        result = calculate_average([1, 2])
        assert result == 1.5

    def test_calculator_float_operations(self):
        calc = Calculator(10.5)
        calc.add(0.5).multiply(2)
        assert calc.get_value() == 22.0
