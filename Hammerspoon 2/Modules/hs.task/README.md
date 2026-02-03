# hs.task

Execute and manage external processes with full control over stdin, stdout, stderr, and process lifecycle.

## Overview

The `hs.task` module provides a modern API for running external processes in Hammerspoon 2. It supports both callback-based and async/await patterns, making it easy to integrate external commands into your automation scripts.

## Key Features

- **Process Execution**: Run any executable with arguments
- **Streaming I/O**: Real-time access to stdout and stderr
- **stdin Control**: Write data to process stdin
- **Process Control**: Start, stop, pause, resume, and interrupt processes
- **Environment Variables**: Set custom environment for processes
- **Working Directory**: Control the working directory for processes
- **Async/Await**: Modern Promise-based API for easy async programming
- **Fluent Builder**: Chainable API for constructing complex tasks

## Basic Usage

### Callback-Based API (Compatible with original Hammerspoon)

```javascript
// Simple execution with completion callback
const task = hs.task.new("/bin/ls", ["-la"], function(exitCode, reason) {
    console.log(`Task completed with exit code: ${exitCode}`);
});
task.start();

// With streaming output
const task = hs.task.new(
    "/bin/ls",
    ["-la"],
    function(exitCode, reason) {
        console.log(`Completed: ${exitCode}`);
    },
    function(stream, data) {
        console.log(`${stream}: ${data}`);
    }
);
task.start();

// With environment variables
const task = hs.task.new(
    "/usr/bin/env",
    ["bash", "-c", "echo $MY_VAR"],
    { MY_VAR: "Hello!" },
    function(exitCode) {
        console.log(`Done: ${exitCode}`);
    }
);
task.start();
```

### Modern Async/Await API

```javascript
// Simple async execution
const result = await hs.task.run("/bin/echo", ["Hello World"]);
console.log(result.stdout); // "Hello World\n"
console.log(result.exitCode); // 0

// With options
const result = await hs.task.run("/bin/pwd", [], {
    workingDirectory: "/tmp",
    environment: { MY_VAR: "value" },
    onOutput: (stream, data) => {
        console.log(`[${stream}] ${data}`);
    }
});

// Shell command helper
const result = await hs.task.shell("ls -la | grep .js");
console.log(result.stdout);

// Parallel execution
const results = await hs.task.parallel([
    { path: "/bin/echo", args: ["Task 1"] },
    { path: "/bin/echo", args: ["Task 2"] }
]);

// Sequential execution
const results = await hs.task.sequence([
    { path: "/bin/echo", args: ["First"] },
    { path: "/bin/echo", args: ["Second"] }
]);
```

### Fluent Builder API

```javascript
const result = await hs.task.builder("/usr/bin/python3")
    .withArgs("script.py", "--verbose")
    .withEnvironment({ PYTHONPATH: "/custom/path" })
    .inDirectory("/path/to/project")
    .onOutput((stream, data) => console.log(data))
    .run();
```

## API Reference

### Module Functions

#### `hs.task.new(launchPath, arguments, [callbackOrEnvironment], [streamCallbackOrEnvironment])`

Create a new task object. Flexible argument handling supports multiple call styles:
- `new(path, args, callback)` - Basic completion callback
- `new(path, args, callback, streamCallback)` - With streaming output
- `new(path, args, environment, callback)` - With environment variables
- `new(path, args, environment, callback, streamCallback)` - Full control

**Returns**: HSTask object

#### `hs.task.run(launchPath, arguments, [options])`

Run a task and return a Promise that resolves with the result.

**Parameters**:
- `launchPath` (string): Full path to executable
- `arguments` (array): Array of string arguments
- `options` (object, optional):
  - `environment` (object): Environment variables
  - `workingDirectory` (string): Working directory path
  - `onOutput` (function): Callback for streaming output: `(stream, data) => {}`

**Returns**: Promise<{exitCode, stdout, stderr, reason}>

#### `hs.task.shell(command, [options])`

Run a shell command and return a Promise.

**Parameters**:
- `command` (string): Shell command to execute
- `options` (object, optional): Same as `hs.task.run`

**Returns**: Promise<{exitCode, stdout, stderr, reason}>

#### `hs.task.parallel(tasks)`

Run multiple tasks in parallel.

**Parameters**:
- `tasks` (array): Array of task specifications: `[{path, args, options}, ...]`

**Returns**: Promise<Array> of results

#### `hs.task.sequence(tasks)`

Run multiple tasks sequentially.

**Parameters**:
- `tasks` (array): Array of task specifications: `[{path, args, options}, ...]`

**Returns**: Promise<Array> of results

#### `hs.task.builder(launchPath)`

Create a TaskBuilder for fluent API.

**Returns**: TaskBuilder instance

### TaskBuilder Methods

- `.withArgs(...args)` - Add arguments
- `.withEnvironment(env)` - Set environment variables
- `.inDirectory(path)` - Set working directory
- `.onOutput(callback)` - Set output callback
- `.run()` - Build and run the task (returns Promise)
- `.build()` - Build without running (returns HSTask)

### HSTask Object Methods

#### Process Control

- `start()` - Start the task
- `terminate()` - Send SIGTERM to terminate
- `interrupt()` - Send SIGINT to interrupt
- `pause()` - Send SIGSTOP to pause
- `resume()` - Send SIGCONT to resume
- `waitUntilExit()` - Block until task completes (use sparingly)

#### stdin Control

- `sendInput(data)` - Write string data to stdin
- `closeInput()` - Close stdin pipe

#### Status and Information

- `pid()` - Get process ID (returns -1 if not running)
- `isRunning()` - Check if task is currently running
- `terminationStatus()` - Get exit code (returns nil if not terminated)
- `terminationReason()` - Get termination reason string

#### Configuration (must be called before start())

- `setEnvironmentVariable(key, value)` - Set an environment variable
- `setWorkingDirectory(path)` - Set working directory
- `environment()` - Get current environment variables
- `workingDirectory()` - Get current working directory

## Examples

See `examples/task-example.js` for comprehensive usage examples.

## Comparison with Original Hammerspoon

This implementation is spiritually equivalent to the original hs.task but with several improvements:

1. **Async/Await Support**: Modern Promise-based API alongside callback API
2. **Fluent Builder**: Chainable API for constructing tasks
3. **Better Process Control**: Added pause/resume functionality
4. **Cleaner API**: Simplified method names and more consistent behavior
5. **Working Directory**: Explicit working directory control
6. **Parallel/Sequential Helpers**: Built-in support for running multiple tasks

The callback-based API remains compatible with original Hammerspoon scripts, making migration easier.

## Notes

- Tasks automatically clean up when the object is garbage collected
- All running tasks are terminated when the module shuts down
- Streaming callbacks run on the main thread
- Use `hs.task.shell()` for simple shell commands instead of constructing `/bin/sh -c` manually
- For long-running processes, use the streaming callback to avoid buffering all output
