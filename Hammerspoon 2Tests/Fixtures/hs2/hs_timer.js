// Test hs.timer module access
// Expected output: Timer module functionality

print(typeof hs.timer);                  // object
print(hs.timer.minutes(5));              // 300
print(hs.timer.hours(2));                // 7200
print(hs.timer.days(1));                 // 86400
print(hs.timer.weeks(1));                // 604800
print(typeof hs.timer.secondsSinceEpoch);// function
