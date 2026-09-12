/// A generic option for [AppDropdown] (value + label + optional hint).
class DropdownOption<T> {
  const DropdownOption({required this.value, required this.label, this.hint});

  final T value;
  final String label;
  final String? hint;

  @override
  String toString() => label;
}
