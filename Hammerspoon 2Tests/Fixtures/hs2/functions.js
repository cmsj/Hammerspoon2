// Test function definitions and calls
// Expected output: Various function results

function add(a, b) {
    return a + b;
}

function greet(name) {
    return "Hello, " + name + "!";
}

function factorial(n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

print(add(5, 3));           // 8
print(greet("Hammerspoon")); // Hello, Hammerspoon!
print(factorial(5));         // 120
