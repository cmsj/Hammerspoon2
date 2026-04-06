// Test arrays and objects
// Expected output: Array and object operations

var arr = [1, 2, 3, 4, 5];
print(arr.length);          // 5
print(arr[2]);              // 3

var doubled = arr.map(function(x) { return x * 2; });
print(doubled.join(", "));  // 2, 4, 6, 8, 10

var sum = arr.reduce(function(a, b) { return a + b; }, 0);
print(sum);                 // 15

var person = {
    name: "John",
    age: 30,
    city: "New York"
};

print(person.name);         // John
print(person.age);          // 30
print(person.city);         // New York
