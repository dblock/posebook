(() => {
  const format = value => {
    const input = value.trim();
    if (!/^\+?[0-9\s().-]+$/.test(input) || input.includes("(0)")) return value;

    let digits = input.replace(/\D/g, "");
    if (!input.startsWith("+")) {
      if (input.startsWith("00")) digits = digits.slice(2);
      else if (digits.length === 10) {
        if (!/^[2-9]/.test(digits)) return value;
        digits = `1${digits}`;
      }
    }
    if (!/^[1-9]\d{7,14}$/.test(digits)) return value;

    const match = digits.match(/^1(\d{3})(\d{3})(\d{4})$/);
    return match ? `+1 (${match[1]}) ${match[2]}-${match[3]}` : `+${digits}`;
  };

  document.addEventListener("focusout", event => {
    const input = event.target;
    if (input.matches?.('input[type="tel"]') && !input.readOnly && !input.disabled) {
      input.value = format(input.value);
    }
  });
})();
