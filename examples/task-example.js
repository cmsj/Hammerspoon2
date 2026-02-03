/**
 * hs.task Examples
 *
 * This file demonstrates the various ways to use hs.task for running external processes.
 */

console.log("=== hs.task Examples ===\n");

// Example 1: Basic task with callbacks (original API style)
console.log("Example 1: Basic task with callbacks");
const task1 = hs.task.new(
    "/bin/ls",
    ["-la", "/tmp"],
    function(exitCode, reason) {
        console.log(`Task completed with exit code: ${exitCode}, reason: ${reason}`);
    },
    function(stream, data) {
        console.log(`${stream}: ${data}`);
    }
);
task1.start();

// Example 2: Async/await style (modern API)
console.log("\nExample 2: Async/await style");
(async function() {
    try {
        const result = await hs.task.run("/bin/echo", ["Hello from hs.task!"]);
        console.log(`Exit code: ${result.exitCode}`);
        console.log(`Output: ${result.stdout.trim()}`);
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 3: Shell command helper
console.log("\nExample 3: Shell command helper");
(async function() {
    try {
        const result = await hs.task.shell("echo 'Current directory:' && pwd");
        console.log(result.stdout.trim());
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 4: Fluent builder API
console.log("\nExample 4: Fluent builder API");
(async function() {
    try {
        const result = await hs.task.builder("/usr/bin/env")
            .withArgs("bash", "-c", "echo $MY_VAR")
            .withEnvironment({ MY_VAR: "Hello from environment!" })
            .run();
        console.log(`Output: ${result.stdout.trim()}`);
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 5: Streaming output with async/await
console.log("\nExample 5: Streaming output");
(async function() {
    try {
        const result = await hs.task.run("/bin/sh", ["-c", "echo 'Line 1'; echo 'Line 2' >&2"], {
            onOutput: (stream, data) => {
                console.log(`[${stream}] ${data.trim()}`);
            }
        });
        console.log(`Task completed with exit code: ${result.exitCode}`);
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 6: Working directory
console.log("\nExample 6: Working directory");
(async function() {
    try {
        const result = await hs.task.run("/bin/pwd", [], {
            workingDirectory: "/tmp"
        });
        console.log(`Working directory was: ${result.stdout.trim()}`);
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 7: Parallel execution
console.log("\nExample 7: Parallel execution");
(async function() {
    try {
        const results = await hs.task.parallel([
            { path: "/bin/echo", args: ["Task 1"] },
            { path: "/bin/echo", args: ["Task 2"] },
            { path: "/bin/echo", args: ["Task 3"] }
        ]);
        results.forEach((result, index) => {
            console.log(`Task ${index + 1}: ${result.stdout.trim()}`);
        });
    } catch (error) {
        console.error(`Error: ${error}`);
    }
})();

// Example 8: Manual control (start, pause, resume, terminate)
console.log("\nExample 8: Manual control");
const task8 = hs.task.new(
    "/bin/sh",
    ["-c", "for i in 1 2 3 4 5; do echo $i; sleep 1; done"],
    function(exitCode) {
        console.log(`Long-running task completed with exit code: ${exitCode}`);
    },
    function(stream, data) {
        console.log(`Output: ${data.trim()}`);
    }
);
task8.start();
console.log(`Task started with PID: ${task8.pid()}`);

// After 2 seconds, pause the task
hs.timer.doAfter(2, function() {
    console.log("Pausing task...");
    task8.pause();
});

// After 4 seconds, resume the task
hs.timer.doAfter(4, function() {
    console.log("Resuming task...");
    task8.resume();
});

// Example 9: stdin interaction
console.log("\nExample 9: stdin interaction");
const task9 = hs.task.new(
    "/bin/cat",
    [],
    function(exitCode) {
        console.log(`Cat task completed with exit code: ${exitCode}`);
    },
    function(stream, data) {
        console.log(`Cat echoed: ${data.trim()}`);
    }
);
task9.start();
task9.sendInput("Hello stdin!\n");
task9.sendInput("This is line 2\n");
hs.timer.doAfter(1, function() {
    task9.closeInput(); // This will cause cat to exit
});

console.log("\n=== Examples completed ===");
